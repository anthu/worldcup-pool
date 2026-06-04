# World Cup 2026 Prediction Pool

Run a company-wide FIFA World Cup 2026 prediction pool — entirely inside Snowflake. No external services, no API keys, no infrastructure to manage.

## What You Get

After installing this app, your team can:

- **Predict all 104 matches** — group stage through the final
- **Pick tournament winners** — champion, runner-up, third place, top scorer
- **Compete on a live leaderboard** — scores update automatically as results come in
- **Access via browser** — SSO-authenticated, no passwords to manage

## Features

| Feature | Description |
|---------|-------------|
| Match Predictions | Predict exact scores for all 104 World Cup matches |
| Tournament Picks | Champion, runner-up, third place, and Golden Boot winner |
| Live Leaderboard | Real-time standings updated as matches finish |
| Auto-Scoring | Points calculated automatically — no manual work |
| SSO Authentication | Uses your existing Snowflake credentials |
| Company Branding | Customize pool name and logo |
| Data Privacy | All predictions stay in YOUR account — never shared |

## Scoring System

| Prediction Type | Criteria | Points |
|----------------|----------|--------|
| Exact Score | Correct home AND away goals | 5 |
| Goal Difference | Correct margin (e.g., 2-0 vs 3-1) | 3 |
| Correct Outcome | Right winner or draw | 1 |
| Wrong | Incorrect outcome | 0 |

### Stage Multipliers

Points are multiplied based on tournament stage:

| Stage | Multiplier |
|-------|-----------|
| Group Stage | 1x |
| Round of 32 | 1.5x |
| Round of 16 | 2x |
| Quarter-Finals | 2.5x |
| Semi-Finals | 3x |
| Third Place Play-off | 3x |
| Final | 4x |

### Tournament Predictions

| Pick | Points |
|------|--------|
| Champion | 20 |
| Runner-Up | 10 |
| Third Place | 7 |
| Top Scorer (Golden Boot) | 15 |

## What Happens After Install

1. The app creates local tables for your predictions and user profiles
2. A Snowpark Container Services (SPCS) service starts with your pool's web UI
3. A public endpoint URL is generated with Snowflake SSO authentication
4. Share the URL with your team — anyone with a Snowflake account can participate
5. Match scores update automatically from shared provider data (no action needed)

## Prerequisites

- **Snowflake Enterprise Edition** (or higher)
- **Snowpark Container Services** enabled on your account
- A warehouse for scoring computations (XS is sufficient)

## Estimated Cost

During the tournament (~6 weeks, June–July 2026):

| Component | Monthly Cost |
|-----------|-------------|
| SPCS Compute Pool (CPU_X64_XS, always-on) | ~$131/mo |
| Warehouse (XS, auto-suspend, scoring queries) | ~$20–150/mo |
| Hybrid Table storage (<100 MB) | ~$1/mo |
| **Total** | **~$150–300/mo** |

**Cost-saving tip:** Suspend the compute pool outside tournament hours or after the tournament ends. You only pay when it's running.

## Configuration

After installation, configure your pool via the admin interface or SQL:

| Setting | Description | Default |
|---------|-------------|---------|
| `POOL_NAME` | Display name for your prediction pool | "World Cup 2026 Pool" |
| `ADMIN_EMAILS` | Comma-separated list of admin email addresses | (installer's email) |
| `COMPANY_LOGO_URL` | URL to your company logo (shown in UI header) | Snowflake logo |

## Support

This is a free community app. For issues, visit the GitHub repository or contact the provider through the Marketplace listing.
