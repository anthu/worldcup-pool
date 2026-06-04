# Architecture — World Cup 2026 Prediction Pool (Native App)

## Overview

The World Cup Prediction Pool is a Snowflake Native App distributed via the Marketplace. It uses a provider-consumer model where the provider manages shared tournament data and consumers get a self-contained prediction pool for their company.

```
┌─────────────────────────────────────┐     ┌─────────────────────────────────────┐
│        PROVIDER ACCOUNT             │     │        CONSUMER ACCOUNT             │
│                                     │     │                                     │
│  football-data.org ──► Sync Task    │     │  APPLICATION: WORLDCUP_POOL         │
│                          │          │     │    ├── Hybrid Tables (predictions)   │
│                          ▼          │     │    ├── Views (shared match data)     │
│  APPLICATION PACKAGE                │────►│    ├── Stored Procedures (scoring)   │
│    ├── Shared Data (matches/teams)  │     │    ├── Tasks (auto-refresh)          │
│    ├── Container Image              │     │    └── SPCS Service (web UI)         │
│    └── Setup Script                 │     │              │                       │
│                                     │     │              ▼                       │
└─────────────────────────────────────┘     │    Public Endpoint (SSO)             │
                                            │              │                       │
                                            │              ▼                       │
                                            │    Browser (employees)               │
                                            └─────────────────────────────────────┘
```

## Provider Account Setup

### Infrastructure (Terraform)

The provider account is configured via Terraform (`terraform/`):

| Resource | Purpose |
|----------|---------|
| `snowflake_warehouse.sync` | XS warehouse for football-data.org sync task |
| `snowflake_database.provider` | Houses sync tables and shared content |
| `snowflake_task.refresh_scores` | 5-minute CRON to pull live scores |
| `snowflake_image_repository.app` | Stores the SPCS container image |
| `snowflake_application_package.pkg` | The Native App package |
| `snowflake_stage.app_code` | Stage for app version files |

### Score Sync Pipeline

```
football-data.org API
        │
        ▼ (every 5 min during matches)
Stored Procedure: sync_scores()
        │
        ▼
WORLDCUP_POOL_PROVIDER.DATA.MATCHES (table)
        │
        ▼ (shared via app package content)
All consumer instances see updated scores
```

## Native App Package Structure

```
app/
├── manifest.yml           # Privileges, references, container images
├── setup_script.sql       # Creates all consumer-side objects
├── readme.md              # Consumer-facing documentation
├── container/             # Docker context for SPCS service
│   ├── Dockerfile
│   └── worldcup_pool/    # FastAPI + React app
├── procedures/            # SQL stored procedures
│   ├── compute_leaderboard.sql
│   └── sync_from_share.sql
└── data/                  # Seed data (fixtures, teams, players)
    ├── wc2026_fixtures.sql
    ├── wc2026_groups.csv
    └── top_scorer_candidates.csv
```

### manifest.yml Privileges

| Privilege | Why |
|-----------|-----|
| `CREATE COMPUTE POOL` | Run the SPCS web UI service |
| `CREATE WAREHOUSE` | Execute scoring queries |
| `BIND SERVICE ENDPOINT` | Expose public URL with SSO |

## Data Flow

### Provider → Consumer (Shared Data)

The application package includes shared content tables that are read-only in the consumer account:

- `matches` — All 104 fixtures with schedule, scores, and status
- `teams` — 48 participating teams with group assignments
- `groups` — 12 groups with team slots
- `top_scorer_candidates` — Player directory for Golden Boot picks

These update automatically when the provider syncs scores. Consumers see changes without any action or compute cost.

### Consumer-Side Data (Private)

Hybrid Tables store consumer-specific data:

| Table | Purpose | Key |
|-------|---------|-----|
| `match_predictions` | User predictions for each match | (user_id, match_id) |
| `tournament_predictions` | Champion/scorer picks | (user_id) |
| `user_profiles` | Display names, avatars | (user_id) |
| `pool_config` | Pool name, logo, admin list | (singleton) |

Hybrid Tables provide:
- Row-level INSERT/UPDATE for individual predictions
- Primary key enforcement (one prediction per user per match)
- Low-latency point reads for the web UI

## Auth Flow

```
Browser
  │
  ▼ (HTTPS to SPCS public endpoint)
Snowflake Ingress (OAuth/SSO)
  │
  ├── Validates Snowflake session
  ├── Sets header: Sf-Context-Current-User
  │
  ▼
SPCS Container (FastAPI)
  │
  ├── Reads Sf-Context-Current-User header
  ├── Maps to user identity (email)
  ├── No password handling needed
  │
  ▼
Snowflake Connector (service-to-Snowflake)
  │
  ├── Uses SPCS OAuth token (/snowflake/session/token)
  ├── Queries hybrid tables as the app's service user
  ├── Filters by authenticated user's email
  │
  ▼
Response to browser
```

Key points:
- Users authenticate via their existing Snowflake credentials
- No separate user database or password management
- The SPCS ingress handles SSO transparently
- The container reads `Sf-Context-Current-User` to identify who is making requests

## Scoring Pipeline

Scoring runs as a SQL stored procedure in the consumer's warehouse:

```sql
CALL WORLDCUP_POOL.APP.COMPUTE_LEADERBOARD();
```

### Scoring Logic

1. **Match Points:** For each completed match, compare prediction to actual score
   - Exact score → 5 pts
   - Correct goal difference → 3 pts
   - Correct outcome (win/draw) → 1 pt
   - Wrong → 0 pts

2. **Stage Multiplier:** Points × multiplier based on tournament round
   - Group: 1x, R32: 1.5x, R16: 2x, QF: 2.5x, SF: 3x, Final: 4x

3. **Tournament Predictions:** Bonus points for correct champion (20), runner-up (10), third (7), top scorer (15)

4. **Leaderboard:** Aggregate per user, rank by total points

### Refresh Task

A Snowflake Task runs every 5 minutes during active matches:
```sql
CREATE TASK refresh_scores_task
  WAREHOUSE = app_wh
  SCHEDULE = '5 MINUTE'
AS
  CALL compute_leaderboard();
```

## Cost Breakdown

### Provider (one-time, shared across all consumers)

| Item | Cost | Notes |
|------|------|-------|
| Sync warehouse (XS, 5-min intervals) | ~$20/mo | Only during tournament |
| Data storage | <$1/mo | <10 MB shared tables |
| Image repository | $0 | Included |
| **Total** | **~$20/mo** | |

### Consumer (per installation)

| Item | Cost | Notes |
|------|------|-------|
| SPCS Compute Pool (CPU_X64_XS) | ~$131/mo | Always-on during tournament |
| Warehouse (XS, auto-suspend 60s) | ~$20–150/mo | Depends on user activity |
| Hybrid Table storage | ~$1/mo | <100 MB predictions |
| **Total** | **~$150–300/mo** | 6 weeks during tournament |

### Cost Optimization

- Suspend compute pool overnight or after tournament
- Use XS warehouse with aggressive auto-suspend
- Scoring task can be reduced to 15-min intervals outside match hours
