<h1 align="center">
  <img src="ui/public/favicon.png" width="36" alt="" /><br/>
  World Cup 2026 Prediction Pool
</h1>

<p align="center">
  <strong>Run a World Cup prediction pool for your team, company, or friends — deployed as a Snowflake Native App.</strong>
</p>

<p align="center">
  <a href="#quick-deploy">Quick Deploy</a> &nbsp;|&nbsp;
  <a href="#features">Features</a> &nbsp;|&nbsp;
  <a href="#how-scoring-works">Scoring</a> &nbsp;|&nbsp;
  <a href="#architecture">Architecture</a> &nbsp;|&nbsp;
  <a href="#configuration">Configuration</a>
</p>

---

Predict scorelines for all 104 World Cup matches, pick the tournament champion and top goal scorers, and compete on a live leaderboard against your colleagues. Match results sync automatically — just deploy and invite your team.

Built as a [Snowflake Native App](https://docs.snowflake.com/en/developer-guide/native-apps/native-apps-about) running on [Snowpark Container Services](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/overview) (SPCS). All data stays in your Snowflake account. Authentication is handled via Snowflake SSO — no extra logins needed.

<br/>

<p align="center">
  <img src="docs/screenshots/forecasts.png" width="720" alt="Match forecasts — predict scores for every group and knockout match" />
</p>

<p align="center"><em>Predict scores for every match — group stage through the final</em></p>

<br/>

## Features

- **104 matches** — Predict scorelines for every group and knockout match
- **Tournament picks** — Choose the champion and top 3 goal scorers before the opening match
- **Live leaderboard** — Real-time rankings with per-match point breakdowns
- **Automatic scoring** — Match results sync from football-data.org; points calculated instantly
- **SSO authentication** — Users authenticate via Snowflake; no passwords to manage
- **Prediction locks** — Each match locks 1 hour before kickoff (configurable)
- **Admin panel** — Manage users, trigger syncs, view scoring breakdowns
- **Snowflake Marketplace** — Distribute to other organizations via the Marketplace

## How Scoring Works

| Category | Points | Details |
|----------|--------|---------|
| Exact score | 5 | Predicted the exact scoreline |
| Correct result | 3 | Got the winner right (or draw) but wrong score |
| Goal difference | 1 | Bonus: correct goal difference on top of correct result |
| Stage multiplier | ×1–×3 | Knockout rounds are worth more (QF ×1.5, SF ×2, Final ×3) |
| Tournament winner | 10 | Correctly predicted the champion |
| Top scorer | 5 each | Up to 3 top scorer picks; 5 points per correct pick |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Snowflake Account                                  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  SPCS Compute Pool (CPU_X64_XS)              │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  Container Service                      │  │  │
│  │  │  • FastAPI backend (Python 3.11)        │  │  │
│  │  │  • React frontend (served as static)    │  │  │
│  │  │  • OAuth token auth (auto-injected)     │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────┐   │
│  │  Tables     │  │  Warehouse  │  │  EAI      │   │
│  │  (PROVIDER) │  │  (XSMALL)   │  │  (egress) │   │
│  └─────────────┘  └─────────────┘  └───────────┘   │
└─────────────────────────────────────────────────────┘
```

**Key components:**
- **SPCS container** — Runs the app (FastAPI + React) on a `CPU_X64_XS` compute pool
- **Snowflake tables** — All data stored in `WORLDCUP_POOL.PROVIDER` schema
- **OAuth auth** — SPCS injects tokens automatically; no credentials in code
- **External Access Integration** — Allows outbound calls to football-data.org for match data

## Quick Deploy

See [AGENTS.md](AGENTS.md) for full step-by-step deployment instructions.

**Prerequisites:**
- Snowflake account with ACCOUNTADMIN (or roles with CREATE COMPUTE POOL, CREATE WAREHOUSE, etc.)
- Docker installed locally (for building the container image)
- `snow` CLI or Snowflake web UI for SQL execution

**TL;DR:**
```bash
# 1. Build the container image
docker buildx build --platform linux/amd64 -t worldcup-pool:v1 -f app/container/Dockerfile --load .

# 2. Tag & push to your Snowflake image registry
docker tag worldcup-pool:v1 <org>-<account>.registry.snowflakecomputing.com/<db>/<schema>/images/worldcup-pool:v1
docker push <org>-<account>.registry.snowflakecomputing.com/<db>/<schema>/images/worldcup-pool:v1

# 3. Create the service (see AGENTS.md for full SQL)
```

## Configuration

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `SNOWFLAKE_DATABASE` | `WORLDCUP_POOL` | Database for app tables |
| `SNOWFLAKE_SCHEMA` | `PROVIDER` | Schema for app tables |
| `SNOWFLAKE_WAREHOUSE` | `WORLDCUP_XS_WH` | Warehouse for queries |
| `ADMIN_EMAILS` | — | Comma-separated admin email addresses |

**Scoring configuration** (in `app/container/worldcup_app/config.py`):
- `prediction_lock_before_kickoff_hours`: Hours before match to lock predictions (default: 1)
- `tournament_picks_lock_at_utc`: Deadline for champion/scorer picks
- `max_top_scorer_picks`: Maximum top scorer selections (default: 5)

## Cost

Running on Snowflake with a `CPU_X64_XS` compute pool:
- **Compute pool**: ~0.06 credits/hour = ~$4.40/month (always-on during tournament)
- **Warehouse**: XSMALL with 60s auto-suspend; negligible for this workload
- **Total**: ~$5/month during the tournament (June–July 2026)

## Project Structure

```
├── app/
│   ├── container/          # Docker container (FastAPI + React)
│   │   ├── Dockerfile
│   │   ├── requirements.txt
│   │   └── worldcup_app/   # Python backend
│   ├── manifest.yml         # Native App manifest
│   └── setup_script.sql     # Native App setup
├── ui/                      # React frontend (Vite + TypeScript)
├── terraform/               # Snowflake infrastructure as code
├── dbt_scoring/             # dbt models for scoring logic
├── provider_sync/           # Match data sync from football-data.org
├── scripts/                 # Build, push, and deploy scripts
└── docs/                    # Architecture and listing docs
```

## License

MIT — see [LICENSE](LICENSE).
