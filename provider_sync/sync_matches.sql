-- ============================================================
-- Provider-side: Sync matches from football-data.org API
-- Python stored procedure using External Access Integration
-- ============================================================

CREATE OR REPLACE PROCEDURE WORLDCUP_POOL.PROVIDER.SYNC_MATCHES()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python', 'requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (FOOTBALL_DATA_API_ACCESS)
SECRETS = ('api_token' = WORLDCUP_POOL.PROVIDER.FOOTBALL_DATA_TOKEN)
EXECUTE AS OWNER
AS
$$
import json
import time
import requests
from snowflake.snowpark import Session


# TLA canonicalization (subset of team_tla.py logic)
_TLA_MAP = {
    "KSA": "KSA", "KOR": "KOR", "RSA": "RSA", "CRC": "CRC",
    "NZL": "NZL", "BIH": "BIH", "CZE": "CZE", "CIV": "CIV",
    "CPV": "CPV", "COD": "COD", "CUW": "CUW",
}

def canonical_tla(raw: str) -> str:
    s = (raw or "").strip().upper()[:3]
    return _TLA_MAP.get(s, s) if s else "?"


def map_status(api_status: str) -> str:
    s = (api_status or "").upper()
    if s in ("FINISHED", "AWARDED"):
        return "FINISHED"
    if s in ("IN_PLAY", "PAUSED"):
        return "LIVE"
    if s in ("POSTPONED", "CANCELLED", "SUSPENDED"):
        return "POSTPONED"
    return "SCHEDULED"


def is_knockout_stage(stage: str) -> bool:
    s = (stage or "").strip().upper()
    return bool(s) and s != "GROUP_STAGE"


def block_pair(block) -> tuple:
    if not isinstance(block, dict):
        return None, None
    h, a = block.get("home"), block.get("away")
    if h is None and block.get("homeTeam") is not None:
        h, a = block.get("homeTeam"), block.get("awayTeam")
    try:
        if h is not None and a is not None:
            return int(h), int(a)
    except (TypeError, ValueError):
        pass
    return None, None


def pool_scores(stage, score, status):
    """Returns (home, away, pen_home, pen_away)."""
    if status not in ("LIVE", "FINISHED"):
        return None, None, None, None
    ph, pa = block_pair(score.get("penalties") or {})
    if is_knockout_stage(stage):
        ft_h, ft_a = block_pair(score.get("fullTime") or {})
        if ft_h is not None:
            return ft_h, ft_a, ph, pa
        rt_h, rt_a = block_pair(score.get("regularTime") or {})
        if rt_h is not None:
            return rt_h, rt_a, ph, pa
        return None, None, ph, pa
    for key in ("fullTime", "regularTime"):
        h, a = block_pair(score.get(key) or {})
        if h is not None:
            return h, a, ph, pa
    return None, None, ph, pa


def winner_team(home_code, away_code, hs, aw, pen_h, pen_a):
    if hs is None or aw is None:
        return None
    if hs > aw:
        return home_code
    if aw > hs:
        return away_code
    if pen_h is not None and pen_a is not None:
        if pen_h > pen_a:
            return home_code
        if pen_a > pen_h:
            return away_code
    return None


def extract_goal_events(raw: dict) -> list:
    home = raw.get("homeTeam") or {}
    away = raw.get("awayTeam") or {}
    hid, aid = home.get("id"), away.get("id")
    htla = canonical_tla(str(home.get("tla") or home.get("shortName") or "?"))
    atla = canonical_tla(str(away.get("tla") or away.get("shortName") or "?"))
    out = []
    for g in raw.get("goals") or []:
        scorer = g.get("scorer") or {}
        name = (scorer.get("name") or "").strip()
        if not name:
            continue
        team = g.get("team") or {}
        tid = team.get("id")
        tla = ""
        if hid is not None and tid == hid:
            tla = htla
        elif aid is not None and tid == aid:
            tla = atla
        else:
            tl = canonical_tla(str(team.get("tla") or team.get("shortName") or "?"))
            if tl == htla:
                tla = htla
            elif tl == atla:
                tla = atla
            else:
                continue
        if not tla or tla == "?":
            continue
        out.append({"player_name": name, "team_code": tla})
    return out


def normalize_match(raw: dict, competition_code: str) -> dict:
    home = raw.get("homeTeam") or {}
    away = raw.get("awayTeam") or {}
    score = raw.get("score") or {}
    utc = raw.get("utcDate") or ""
    mapped = map_status(raw.get("status") or "SCHEDULED")
    raw_stage = raw.get("stage")
    hs, aw, pen_h, pen_a = pool_scores(raw_stage, score, mapped)

    grp = raw.get("group")
    if isinstance(grp, str) and grp.strip():
        group_key = grp.strip().upper()
    else:
        group_key = None

    htla = canonical_tla(str(home.get("tla") or home.get("shortName") or "?"))
    atla = canonical_tla(str(away.get("tla") or away.get("shortName") or "?"))
    goals = extract_goal_events(raw) if mapped in ("LIVE", "FINISHED") else []
    mid = raw.get("id")

    win = None
    if is_knockout_stage(raw_stage) and mapped == "FINISHED":
        win = winner_team(htla, atla, hs, aw, pen_h, pen_a)

    return {
        "external_match_id": str(mid),
        "competition_code": competition_code,
        "stage": raw_stage,
        "matchday": raw.get("matchday"),
        "group_key": group_key,
        "home_team_code": htla,
        "away_team_code": atla,
        "home_team_name": (home.get("name") or home.get("shortName") or "TBD")[:100],
        "away_team_name": (away.get("name") or away.get("shortName") or "TBD")[:100],
        "kickoff_utc": utc,
        "status": mapped,
        "home_score": hs,
        "away_score": aw,
        "winner_team_code": win,
        "goal_events": json.dumps(goals) if goals else None,
    }


def run(session: Session) -> str:
    import _snowflake
    api_token = _snowflake.get_generic_secret_string('api_token')

    headers = {"X-Auth-Token": api_token}
    base_url = "https://api.football-data.org/v4"

    # 1. Fetch all matches for WC 2026
    resp = requests.get(
        f"{base_url}/competitions/WC/matches",
        headers=headers,
        params={"limit": 999},
        timeout=120
    )
    resp.raise_for_status()
    data = resp.json()

    matches = []
    for m in data.get("matches") or []:
        if not isinstance(m, dict) or m.get("id") is None:
            continue
        try:
            matches.append(normalize_match(m, "WC"))
        except Exception:
            continue

    if not matches:
        return "No matches fetched from API"

    # 2. Enrich goal events from individual match endpoints (rate-limited)
    finished_no_goals = [m for m in matches if m["status"] in ("FINISHED", "LIVE") and not m["goal_events"]]
    enriched_count = 0
    for i, m in enumerate(finished_no_goals):
        try:
            r = requests.get(
                f"{base_url}/matches/{m['external_match_id']}",
                headers=headers,
                timeout=60
            )
            if r.status_code == 429:
                break  # rate limited, stop enrichment
            r.raise_for_status()
            goals = extract_goal_events(r.json())
            if goals:
                m["goal_events"] = json.dumps(goals)
                enriched_count += 1
        except Exception:
            pass
        if i < len(finished_no_goals) - 1:
            time.sleep(2.2)

    # 3. MERGE into provider matches table
    import pandas as pd
    df = pd.DataFrame(matches)

    # Write to temp table then MERGE
    temp_table = "WORLDCUP_POOL.PROVIDER._SYNC_MATCHES_TEMP"
    snowpark_df = session.create_dataframe(df)
    snowpark_df.write.mode("overwrite").save_as_table(temp_table)

    merge_sql = f"""
    MERGE INTO WORLDCUP_POOL.PROVIDER.MATCHES t
    USING {temp_table} s
    ON t.external_match_id = s.external_match_id
    WHEN MATCHED THEN UPDATE SET
        t.competition_code = s.competition_code,
        t.stage = s.stage,
        t.matchday = s.matchday,
        t.group_key = s.group_key,
        t.home_team_code = s.home_team_code,
        t.away_team_code = s.away_team_code,
        t.home_team_name = s.home_team_name,
        t.away_team_name = s.away_team_name,
        t.kickoff_utc = s.kickoff_utc,
        t.status = s.status,
        t.home_score = s.home_score,
        t.away_score = s.away_score,
        t.winner_team_code = s.winner_team_code,
        t.goal_events = PARSE_JSON(s.goal_events)
    WHEN NOT MATCHED THEN INSERT (
        external_match_id, competition_code, stage, matchday, group_key,
        home_team_code, away_team_code, home_team_name, away_team_name,
        kickoff_utc, status, home_score, away_score, winner_team_code, goal_events
    ) VALUES (
        s.external_match_id, s.competition_code, s.stage, s.matchday, s.group_key,
        s.home_team_code, s.away_team_code, s.home_team_name, s.away_team_name,
        s.kickoff_utc, s.status, s.home_score, s.away_score, s.winner_team_code,
        PARSE_JSON(s.goal_events)
    )
    """
    result = session.sql(merge_sql).collect()
    session.sql(f"DROP TABLE IF EXISTS {temp_table}").collect()

    return f"Synced {len(matches)} matches ({enriched_count} enriched with goals). MERGE result: {result}"
$$;
