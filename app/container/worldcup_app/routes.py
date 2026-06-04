from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, model_validator

from worldcup_app.auth import UserContext, get_user_context, is_admin
from worldcup_app.config import get_settings
from worldcup_app.db import get_cursor

router = APIRouter(prefix="/api")


# ── Pydantic models (match existing frontend contract) ─────────────


class MeOut(BaseModel):
    user_id: str
    email: str | None = None
    is_admin: bool = False


class UserProfileIn(BaseModel):
    display_name: str | None = Field(default=None, max_length=120)
    nationality: str | None = Field(default=None, max_length=80)
    profile_picture: str | None = Field(default=None, max_length=1_500_000)


class UserProfileOut(BaseModel):
    user_id: str
    display_name: str | None = None
    nationality: str | None = None
    profile_picture: str | None = None
    updated_at: datetime | None = None


class MatchPredictionIn(BaseModel):
    match_id: str
    home_goals: int | None = Field(default=None, ge=0, le=30)
    away_goals: int | None = Field(default=None, ge=0, le=30)
    advance_team_code: str | None = Field(default=None, max_length=16)

    @model_validator(mode="after")
    def both_or_neither(self) -> "MatchPredictionIn":
        if (self.home_goals is None) != (self.away_goals is None):
            raise ValueError("home_goals and away_goals must both be set or both null")
        return self


class PutMatchPredictionsIn(BaseModel):
    predictions: list[MatchPredictionIn]


class MatchPredictionError(BaseModel):
    match_id: str
    detail: str


class PutMatchPredictionsOut(BaseModel):
    updated: int
    errors: list[MatchPredictionError] = []


class MatchOut(BaseModel):
    id: str
    external_match_id: str
    competition_code: str
    stage: str | None = None
    matchday: int | None = None
    group_key: str | None = None
    home_team_code: str
    away_team_code: str
    home_team_name: str
    away_team_name: str
    kickoff_utc: datetime
    prediction_deadline_utc: datetime
    status: str
    home_score: int | None = None
    away_score: int | None = None
    winner_team_code: str | None = None
    prediction_open: bool
    pred_home_goals: int | None = None
    pred_away_goals: int | None = None
    pred_advance_team_code: str | None = None
    points_outcome: int = 0
    points_exact: int = 0
    points_scorer_goals: int = 0
    points_advancer: int = 0


class TopScorerPickIn(BaseModel):
    player_name: str = Field(min_length=1, max_length=160)
    country_code: str = Field(min_length=1, max_length=16)


class TopScorerPickOut(BaseModel):
    player_name: str
    country_code: str
    country_name: str = ""
    points_awarded: int = 0


class TournamentPredictionsIn(BaseModel):
    tournament_winner_team_code: str | None = None
    top_scorer_player_name: str | None = None
    top_scorers: list[TopScorerPickIn] = Field(default_factory=list)
    notes_json: dict[str, Any] = Field(default_factory=dict)


class TournamentPredictionsOut(BaseModel):
    tournament_winner_team_code: str | None = None
    top_scorer_player_name: str | None = None
    top_scorers: list[TopScorerPickOut] = Field(default_factory=list)
    notes_json: dict[str, Any] = Field(default_factory=dict)
    tournament_open: bool = True
    tournament_picks_lock_at_utc: datetime | None = None
    tournament_lock_hours_before_first_kickoff: int = 1
    points_tournament_winner: int = 0


class PoolSummaryOut(BaseModel):
    total_matches: int
    predicted_matches: int
    next_deadline_utc: datetime | None = None
    next_deadline_label: str | None = None


class PoolRankingEntryOut(BaseModel):
    rank: int
    user_id: str
    display_name: str | None = None
    email: str | None = None
    profile_picture: str | None = None
    match_predictions_filled: int = 0
    total_points: int = 0
    points_outcome: int = 0
    points_exact: int = 0
    points_scorer_goals: int = 0
    points_advancer: int = 0
    points_tournament_winner: int = 0


class PoolRankingOut(BaseModel):
    entries: list[PoolRankingEntryOut] = []


class PoolDashboardOut(BaseModel):
    predictors_count: int = 0
    leaderboard: PoolRankingOut = Field(default_factory=PoolRankingOut)


class PoolConfigOut(BaseModel):
    custom_logo: str | None = None
    pool_name: str | None = None


class PoolConfigIn(BaseModel):
    custom_logo: str | None = Field(default=None, max_length=1_500_000)
    pool_name: str | None = Field(default=None, max_length=200)


class PublicParticipantProfileOut(BaseModel):
    user_id: str
    display_name: str | None = None
    nationality: str | None = None
    profile_picture: str | None = None
    updated_at: datetime | None = None
    tournament_winner_team_code: str | None = None
    top_scorers: list[TopScorerPickOut] = Field(default_factory=list)
    match_predictions_saved: int = 0


# ── Helpers ────────────────────────────────────────────────────────


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _prediction_lock_deadline(kickoff_utc: datetime, hours: int) -> datetime:
    return kickoff_utc - timedelta(hours=hours)


def _tournament_picks_lock_at_utc() -> datetime:
    raw = (get_settings().tournament_picks_lock_at_utc or "").strip()
    if not raw:
        raw = "2026-06-11T18:00:00+00:00"
    s = raw[:-1] + "+00:00" if raw.endswith("Z") else raw
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _tournament_editing_open() -> bool:
    return _now() < _tournament_picks_lock_at_utc()


def _is_knockout_stage(stage: str | None) -> bool:
    if not stage:
        return False
    s = stage.strip().upper()
    return s != "" and s != "GROUP_STAGE"


def _row_to_dict(row: dict) -> dict:
    """Normalize Snowflake DictCursor row keys to lowercase."""
    return {k.lower(): v for k, v in row.items()}


# ── Routes ─────────────────────────────────────────────────────────


@router.get("/health")
def health_check():
    return {"status": "ok"}


@router.get("/me", response_model=MeOut)
def get_me(user: UserContext = Depends(get_user_context)):
    return MeOut(
        user_id=user.user_id,
        email=user.email,
        is_admin=is_admin(user),
    )


# ── Profile ────────────────────────────────────────────────────────


@router.get("/profile", response_model=UserProfileOut)
def get_my_profile(user: UserContext = Depends(get_user_context)):
    uid = user.user_id
    with get_cursor() as cur:
        cur.execute(
            """
            SELECT user_id, display_name, nationality, profile_picture, updated_at
            FROM user_profiles
            WHERE user_id = %s
            """,
            (uid,),
        )
        row = cur.fetchone()
    if not row:
        return UserProfileOut(user_id=uid)
    r = _row_to_dict(row)
    return UserProfileOut(
        user_id=r["user_id"],
        display_name=r["display_name"],
        nationality=r["nationality"],
        profile_picture=r["profile_picture"],
        updated_at=r["updated_at"],
    )


@router.put("/profile", response_model=UserProfileOut)
def put_my_profile(body: UserProfileIn, user: UserContext = Depends(get_user_context)):
    uid = user.user_id
    display_name = (body.display_name or "").strip() or None
    nationality = (body.nationality or "").strip() or None
    picture = body.profile_picture
    if picture:
        if len(picture) > 1_500_000:
            raise HTTPException(400, "Profile picture is too large")
        if not picture.startswith("data:image/"):
            raise HTTPException(400, "Profile picture must be an uploaded image")

    with get_cursor() as cur:
        cur.execute(
            """
            MERGE INTO user_profiles AS t
            USING (SELECT %s AS user_id, %s AS display_name, %s AS nationality, %s AS profile_picture) AS s
            ON t.user_id = s.user_id
            WHEN MATCHED THEN UPDATE SET
                display_name = s.display_name,
                nationality = s.nationality,
                profile_picture = s.profile_picture,
                updated_at = CURRENT_TIMESTAMP()
            WHEN NOT MATCHED THEN INSERT (user_id, display_name, nationality, profile_picture, updated_at)
                VALUES (s.user_id, s.display_name, s.nationality, s.profile_picture, CURRENT_TIMESTAMP())
            """,
            (uid, display_name, nationality, picture),
        )
        cur.execute(
            "SELECT user_id, display_name, nationality, profile_picture, updated_at FROM user_profiles WHERE user_id = %s",
            (uid,),
        )
        row = cur.fetchone()
    r = _row_to_dict(row)
    return UserProfileOut(
        user_id=r["user_id"],
        display_name=r["display_name"],
        nationality=r["nationality"],
        profile_picture=r["profile_picture"],
        updated_at=r["updated_at"],
    )


# ── Matches ────────────────────────────────────────────────────────


@router.get("/matches", response_model=list[MatchOut])
def list_matches(user: UserContext = Depends(get_user_context)):
    uid = user.user_id
    lock_h = get_settings().prediction_lock_before_kickoff_hours
    with get_cursor() as cur:
        cur.execute(
            """
            SELECT
                m.id, m.external_match_id, m.competition_code, m.stage, m.matchday,
                m.group_key,
                m.home_team_code, m.away_team_code, m.home_team_name, m.away_team_name,
                m.kickoff_utc, m.status, m.home_score, m.away_score, m.winner_team_code,
                p.home_goals AS pred_home, p.away_goals AS pred_away, p.advance_team_code AS pred_adv
            FROM matches m
            LEFT JOIN match_predictions p ON p.match_id = m.id AND p.user_id = %s
            ORDER BY m.kickoff_utc ASC, m.stage NULLS LAST
            """,
            (uid,),
        )
        rows = cur.fetchall()

    now = _now()
    out: list[MatchOut] = []
    for raw in rows:
        row = _row_to_dict(raw)
        kick = row["kickoff_utc"]
        if kick and kick.tzinfo is None:
            kick = kick.replace(tzinfo=timezone.utc)
        deadline = _prediction_lock_deadline(kick, lock_h) if kick else now
        prediction_open = (
            row["status"] not in ("FINISHED", "LIVE", "IN_PLAY", "PAUSED", "POSTPONED")
            and now < deadline
        )
        out.append(
            MatchOut(
                id=str(row["id"]),
                external_match_id=str(row["external_match_id"] or ""),
                competition_code=str(row["competition_code"] or ""),
                stage=row["stage"],
                matchday=row["matchday"],
                group_key=row.get("group_key"),
                home_team_code=str(row["home_team_code"] or ""),
                away_team_code=str(row["away_team_code"] or ""),
                home_team_name=str(row["home_team_name"] or ""),
                away_team_name=str(row["away_team_name"] or ""),
                kickoff_utc=kick,
                prediction_deadline_utc=deadline,
                status=str(row["status"] or "SCHEDULED"),
                home_score=row["home_score"],
                away_score=row["away_score"],
                winner_team_code=row.get("winner_team_code"),
                prediction_open=prediction_open,
                pred_home_goals=row["pred_home"],
                pred_away_goals=row["pred_away"],
                pred_advance_team_code=row.get("pred_adv"),
                # Points computed client-side or via leaderboard view in SPCS version
                points_outcome=0,
                points_exact=0,
                points_scorer_goals=0,
                points_advancer=0,
            )
        )
    return out


# ── Match Predictions ──────────────────────────────────────────────


@router.put("/predictions/matches", response_model=PutMatchPredictionsOut)
def put_match_predictions(body: PutMatchPredictionsIn, user: UserContext = Depends(get_user_context)):
    uid = user.user_id
    preds = body.predictions
    if not preds:
        return PutMatchPredictionsOut(updated=0, errors=[])

    by_mid: dict[str, MatchPredictionIn] = {}
    for pr in preds:
        by_mid[str(pr.match_id)] = pr
    ids = list(by_mid.keys())

    errors: list[MatchPredictionError] = []
    updated = 0
    lock_h = get_settings().prediction_lock_before_kickoff_hours
    now = _now()

    with get_cursor() as cur:
        # Fetch match info for validation
        placeholders = ", ".join(["%s"] * len(ids))
        cur.execute(
            f"""
            SELECT id, kickoff_utc, status, stage, home_team_code, away_team_code
            FROM matches
            WHERE id IN ({placeholders})
            """,
            ids,
        )
        found_rows = cur.fetchall()
        found: dict[str, dict] = {}
        for raw in found_rows:
            r = _row_to_dict(raw)
            found[str(r["id"])] = r

        for mid, pr in by_mid.items():
            match = found.get(mid)
            if not match:
                errors.append(MatchPredictionError(match_id=mid, detail="Unknown match"))
                continue
            if match["status"] in ("FINISHED", "LIVE", "IN_PLAY", "PAUSED", "POSTPONED"):
                errors.append(MatchPredictionError(match_id=mid, detail="Match no longer open for predictions"))
                continue
            kick = match["kickoff_utc"]
            if kick and kick.tzinfo is None:
                kick = kick.replace(tzinfo=timezone.utc)
            deadline = _prediction_lock_deadline(kick, lock_h)
            if now >= deadline:
                errors.append(MatchPredictionError(match_id=mid, detail="Prediction deadline has passed"))
                continue

            if pr.home_goals is None and pr.away_goals is None:
                # Delete prediction
                cur.execute(
                    "DELETE FROM match_predictions WHERE user_id = %s AND match_id = %s",
                    (uid, mid),
                )
                updated += 1
                continue

            h, a = pr.home_goals, pr.away_goals
            adv = (pr.advance_team_code or "").strip().upper() or None

            # Validate knockout advance pick
            if _is_knockout_stage(match["stage"]) and h == a:
                hc = str(match["home_team_code"]).strip().upper()
                ac = str(match["away_team_code"]).strip().upper()
                if not adv or (adv != hc and adv != ac and hc != "?" and ac != "?"):
                    errors.append(MatchPredictionError(
                        match_id=mid,
                        detail="Knockout: predicted draw — pick which team advances (penalties).",
                    ))
                    continue
            else:
                adv = None

            cur.execute(
                """
                MERGE INTO match_predictions AS t
                USING (SELECT %s AS user_id, %s AS match_id, %s AS home_goals, %s AS away_goals, %s AS advance_team_code) AS s
                ON t.user_id = s.user_id AND t.match_id = s.match_id
                WHEN MATCHED THEN UPDATE SET
                    home_goals = s.home_goals,
                    away_goals = s.away_goals,
                    advance_team_code = s.advance_team_code,
                    updated_at = CURRENT_TIMESTAMP()
                WHEN NOT MATCHED THEN INSERT (id, user_id, match_id, home_goals, away_goals, advance_team_code, updated_at)
                    VALUES (UUID_STRING(), s.user_id, s.match_id, s.home_goals, s.away_goals, s.advance_team_code, CURRENT_TIMESTAMP())
                """,
                (uid, mid, h, a, adv),
            )
            updated += 1

    return PutMatchPredictionsOut(updated=updated, errors=errors)


# ── Tournament Predictions ─────────────────────────────────────────


@router.get("/predictions/tournament", response_model=TournamentPredictionsOut)
def get_tournament_predictions(user: UserContext = Depends(get_user_context)):
    uid = user.user_id
    lock_at = _tournament_picks_lock_at_utc()
    open_ed = _tournament_editing_open()
    lock_h = get_settings().prediction_lock_before_kickoff_hours

    with get_cursor() as cur:
        cur.execute(
            """
            SELECT tournament_winner_team_code, top_scorer_player_name, notes_json
            FROM tournament_predictions WHERE user_id = %s
            """,
            (uid,),
        )
        row = cur.fetchone()

    if not row:
        return TournamentPredictionsOut(
            tournament_open=open_ed,
            tournament_picks_lock_at_utc=lock_at,
            tournament_lock_hours_before_first_kickoff=lock_h,
        )

    r = _row_to_dict(row)
    nj = r["notes_json"]
    if isinstance(nj, str):
        try:
            nj = json.loads(nj)
        except (json.JSONDecodeError, TypeError):
            nj = {}
    if not isinstance(nj, dict):
        nj = {}

    picks = _parse_top_scorers(nj, r["top_scorer_player_name"])

    return TournamentPredictionsOut(
        tournament_winner_team_code=r["tournament_winner_team_code"],
        top_scorer_player_name=r["top_scorer_player_name"],
        top_scorers=picks,
        notes_json=nj,
        tournament_open=open_ed,
        tournament_picks_lock_at_utc=lock_at,
        tournament_lock_hours_before_first_kickoff=lock_h,
    )


@router.put("/predictions/tournament", response_model=TournamentPredictionsOut)
def put_tournament_predictions(body: TournamentPredictionsIn, user: UserContext = Depends(get_user_context)):
    uid = user.user_id
    lock_at = _tournament_picks_lock_at_utc()
    lock_h = get_settings().prediction_lock_before_kickoff_hours

    if not _tournament_editing_open():
        raise HTTPException(
            status_code=409,
            detail=f"Tournament predictions are locked — deadline was {lock_at.strftime('%Y-%m-%d %H:%M')} UTC.",
        )

    # Build merged notes
    merged_notes: dict[str, Any] = {}
    with get_cursor() as cur:
        cur.execute("SELECT notes_json FROM tournament_predictions WHERE user_id = %s", (uid,))
        prev = cur.fetchone()
        if prev:
            prev_r = _row_to_dict(prev)
            raw_nj = prev_r["notes_json"]
            if isinstance(raw_nj, str):
                try:
                    merged_notes = json.loads(raw_nj)
                except (json.JSONDecodeError, TypeError):
                    merged_notes = {}
            elif isinstance(raw_nj, dict):
                merged_notes = dict(raw_nj)

    merged_notes.update(body.notes_json or {})
    merged_notes.pop("golden_boot", None)

    if body.top_scorers:
        merged_notes["top_scorers"] = [
            {"player_name": p.player_name.strip(), "country_code": p.country_code.strip().upper()}
            for p in body.top_scorers
        ]
    elif body.top_scorer_player_name and body.top_scorer_player_name.strip():
        merged_notes["top_scorers"] = [{"player_name": body.top_scorer_player_name.strip(), "country_code": "?"}]
    else:
        merged_notes["top_scorers"] = []

    # Legacy top_scorer_player_name column
    picks_list = merged_notes.get("top_scorers") or []
    legacy_ts = None
    if isinstance(picks_list, list) and picks_list:
        legacy_ts = "; ".join(
            f'{p.get("player_name", "").strip()} ({p.get("country_code", "").strip()})'
            for p in picks_list
            if isinstance(p, dict) and p.get("player_name")
        )
    elif body.top_scorer_player_name and body.top_scorer_player_name.strip():
        legacy_ts = body.top_scorer_player_name.strip()

    winner = (body.tournament_winner_team_code or "").strip().upper() or None
    notes_str = json.dumps(merged_notes)

    with get_cursor() as cur:
        cur.execute(
            """
            MERGE INTO tournament_predictions AS t
            USING (SELECT %s AS user_id, %s AS tournament_winner_team_code, %s AS top_scorer_player_name, PARSE_JSON(%s) AS notes_json) AS s
            ON t.user_id = s.user_id
            WHEN MATCHED THEN UPDATE SET
                tournament_winner_team_code = s.tournament_winner_team_code,
                top_scorer_player_name = s.top_scorer_player_name,
                notes_json = s.notes_json,
                updated_at = CURRENT_TIMESTAMP()
            WHEN NOT MATCHED THEN INSERT (id, user_id, tournament_winner_team_code, top_scorer_player_name, notes_json, updated_at)
                VALUES (UUID_STRING(), s.user_id, s.tournament_winner_team_code, s.top_scorer_player_name, s.notes_json, CURRENT_TIMESTAMP())
            """,
            (uid, winner, legacy_ts, notes_str),
        )
        cur.execute(
            "SELECT tournament_winner_team_code, top_scorer_player_name, notes_json FROM tournament_predictions WHERE user_id = %s",
            (uid,),
        )
        row = cur.fetchone()

    r = _row_to_dict(row)
    nj = r["notes_json"]
    if isinstance(nj, str):
        try:
            nj = json.loads(nj)
        except (json.JSONDecodeError, TypeError):
            nj = {}
    if not isinstance(nj, dict):
        nj = {}
    picks = _parse_top_scorers(nj, r["top_scorer_player_name"])

    return TournamentPredictionsOut(
        tournament_winner_team_code=r["tournament_winner_team_code"],
        top_scorer_player_name=r["top_scorer_player_name"],
        top_scorers=picks,
        notes_json=nj,
        tournament_open=_tournament_editing_open(),
        tournament_picks_lock_at_utc=lock_at,
        tournament_lock_hours_before_first_kickoff=lock_h,
    )


def _parse_top_scorers(nj: dict, legacy_name: str | None) -> list[TopScorerPickOut]:
    """Extract top scorer picks from notes_json or legacy column."""
    picks_raw = nj.get("top_scorers") or []
    if not picks_raw and legacy_name:
        return [TopScorerPickOut(player_name=legacy_name, country_code="?", country_name="")]
    out = []
    for p in picks_raw:
        if isinstance(p, dict) and p.get("player_name"):
            out.append(TopScorerPickOut(
                player_name=str(p["player_name"]),
                country_code=str(p.get("country_code", "?")),
                country_name="",
            ))
    return out


# ── Dashboard / Leaderboard ────────────────────────────────────────


@router.get("/pool-summary", response_model=PoolSummaryOut)
def pool_summary(user: UserContext = Depends(get_user_context)):
    uid = user.user_id
    lock_h = get_settings().prediction_lock_before_kickoff_hours
    with get_cursor() as cur:
        cur.execute("SELECT COUNT(*) AS cnt FROM matches")
        total = cur.fetchone()["CNT"]
        cur.execute(
            """
            SELECT COUNT(*) AS cnt FROM match_predictions
            WHERE user_id = %s AND home_goals IS NOT NULL AND away_goals IS NOT NULL
            """,
            (uid,),
        )
        predicted = cur.fetchone()["CNT"]
        cur.execute(
            """
            SELECT DATEADD('hour', -%s, MIN(kickoff_utc)) AS next_deadline
            FROM matches
            WHERE kickoff_utc IS NOT NULL
              AND status NOT IN ('FINISHED', 'POSTPONED')
              AND DATEADD('hour', -%s, kickoff_utc) > CURRENT_TIMESTAMP()
            """,
            (lock_h, lock_h),
        )
        row = cur.fetchone()
        next_d = _row_to_dict(row)["next_deadline"] if row else None

    label = None
    if next_d:
        if next_d.tzinfo is None:
            next_d = next_d.replace(tzinfo=timezone.utc)
        label = next_d.strftime("%Y-%m-%d %H:%M UTC")

    return PoolSummaryOut(
        total_matches=int(total),
        predicted_matches=int(predicted),
        next_deadline_utc=next_d,
        next_deadline_label=label,
    )


@router.get("/ranking", response_model=PoolRankingOut)
def pool_ranking(_user: UserContext = Depends(get_user_context)):
    """Leaderboard from the pre-computed view."""
    with get_cursor() as cur:
        cur.execute(
            """
            SELECT * FROM leaderboard_view
            ORDER BY total_points DESC, user_id ASC
            """
        )
        rows = cur.fetchall()

    entries = []
    for i, raw in enumerate(rows, start=1):
        r = _row_to_dict(raw)
        entries.append(PoolRankingEntryOut(
            rank=i,
            user_id=r["user_id"],
            display_name=r.get("display_name"),
            email=r.get("email"),
            profile_picture=r.get("profile_picture"),
            match_predictions_filled=int(r.get("match_predictions_filled", 0)),
            total_points=int(r.get("total_points", 0)),
            points_outcome=int(r.get("points_outcome", 0)),
            points_exact=int(r.get("points_exact", 0)),
            points_scorer_goals=int(r.get("points_scorer_goals", 0)),
            points_advancer=int(r.get("points_advancer", 0)),
            points_tournament_winner=int(r.get("points_tournament_winner", 0)),
        ))
    return PoolRankingOut(entries=entries)


@router.get("/dashboard", response_model=PoolDashboardOut)
def pool_dashboard(_user: UserContext = Depends(get_user_context)):
    """Predictor count plus full leaderboard."""
    with get_cursor() as cur:
        cur.execute(
            """
            SELECT COUNT(DISTINCT user_id) AS cnt FROM (
                SELECT user_id FROM match_predictions WHERE home_goals IS NOT NULL AND away_goals IS NOT NULL
                UNION
                SELECT user_id FROM user_profiles
            )
            """
        )
        predictors = cur.fetchone()["CNT"]

        cur.execute("SELECT * FROM leaderboard_view ORDER BY total_points DESC, user_id ASC")
        rows = cur.fetchall()

    entries = []
    for i, raw in enumerate(rows, start=1):
        r = _row_to_dict(raw)
        entries.append(PoolRankingEntryOut(
            rank=i,
            user_id=r["user_id"],
            display_name=r.get("display_name"),
            email=r.get("email"),
            profile_picture=r.get("profile_picture"),
            match_predictions_filled=int(r.get("match_predictions_filled", 0)),
            total_points=int(r.get("total_points", 0)),
            points_outcome=int(r.get("points_outcome", 0)),
            points_exact=int(r.get("points_exact", 0)),
            points_scorer_goals=int(r.get("points_scorer_goals", 0)),
            points_advancer=int(r.get("points_advancer", 0)),
            points_tournament_winner=int(r.get("points_tournament_winner", 0)),
        ))
    return PoolDashboardOut(
        predictors_count=int(predictors),
        leaderboard=PoolRankingOut(entries=entries),
    )


# ── Participant Profiles ───────────────────────────────────────────


@router.get("/profiles/{user_id}", response_model=PublicParticipantProfileOut)
def get_participant_profile(user_id: str, _user: UserContext = Depends(get_user_context)):
    target = (user_id or "").strip()
    if not target:
        raise HTTPException(400, "Missing user id")

    with get_cursor() as cur:
        cur.execute("SELECT display_name, nationality, profile_picture, updated_at FROM user_profiles WHERE user_id = %s", (target,))
        prow = cur.fetchone()
        cur.execute(
            "SELECT tournament_winner_team_code, top_scorer_player_name, notes_json FROM tournament_predictions WHERE user_id = %s",
            (target,),
        )
        trow = cur.fetchone()
        cur.execute(
            "SELECT COUNT(*) AS cnt FROM match_predictions WHERE user_id = %s AND home_goals IS NOT NULL AND away_goals IS NOT NULL",
            (target,),
        )
        mp_count = cur.fetchone()["CNT"]

    if not prow and not trow and mp_count == 0:
        raise HTTPException(404, "No pool participation found for this user")

    tw = None
    picks: list[TopScorerPickOut] = []
    if trow:
        tr = _row_to_dict(trow)
        tw = tr["tournament_winner_team_code"]
        nj = tr["notes_json"]
        if isinstance(nj, str):
            try:
                nj = json.loads(nj)
            except (json.JSONDecodeError, TypeError):
                nj = {}
        if not isinstance(nj, dict):
            nj = {}
        picks = _parse_top_scorers(nj, tr["top_scorer_player_name"])

    if prow:
        pr = _row_to_dict(prow)
        return PublicParticipantProfileOut(
            user_id=target,
            display_name=pr["display_name"],
            nationality=pr["nationality"],
            profile_picture=pr["profile_picture"],
            updated_at=pr["updated_at"],
            tournament_winner_team_code=tw,
            top_scorers=picks,
            match_predictions_saved=int(mp_count),
        )
    return PublicParticipantProfileOut(
        user_id=target,
        tournament_winner_team_code=tw,
        top_scorers=picks,
        match_predictions_saved=int(mp_count),
    )


# ── Pool Config ────────────────────────────────────────────────────


@router.get("/pool-config", response_model=PoolConfigOut)
def get_pool_config(_user: UserContext = Depends(get_user_context)):
    with get_cursor() as cur:
        try:
            cur.execute("SELECT custom_logo, pool_name FROM pool_config WHERE id = 1")
            row = cur.fetchone()
        except Exception:
            return PoolConfigOut()
    if not row:
        return PoolConfigOut()
    r = _row_to_dict(row)
    return PoolConfigOut(custom_logo=r["custom_logo"], pool_name=r["pool_name"])


@router.put("/admin/pool-config", response_model=PoolConfigOut)
def put_pool_config(body: PoolConfigIn, user: UserContext = Depends(get_user_context)):
    if not is_admin(user):
        raise HTTPException(403, "Admin access required")
    logo = (body.custom_logo or "").strip() or None
    if logo and not logo.startswith("data:image/"):
        raise HTTPException(400, "Logo must be a data:image/* URL")
    name = (body.pool_name or "").strip() or None

    with get_cursor() as cur:
        cur.execute(
            """
            MERGE INTO pool_config AS t
            USING (SELECT 1 AS id, %s AS custom_logo, %s AS pool_name) AS s
            ON t.id = s.id
            WHEN MATCHED THEN UPDATE SET
                custom_logo = s.custom_logo,
                pool_name = s.pool_name,
                updated_at = CURRENT_TIMESTAMP()
            WHEN NOT MATCHED THEN INSERT (id, custom_logo, pool_name, updated_at)
                VALUES (s.id, s.custom_logo, s.pool_name, CURRENT_TIMESTAMP())
            """,
            (logo, name),
        )
    return PoolConfigOut(custom_logo=logo, pool_name=name)
