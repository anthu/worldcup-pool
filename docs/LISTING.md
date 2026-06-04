# Marketplace Listing Management

Internal documentation for the provider on how to create, publish, and manage the World Cup 2026 Prediction Pool listing on Snowflake Marketplace.

## 1. Create the Application Package

```sql
-- Run in provider account
USE ROLE ACCOUNTADMIN;

CREATE APPLICATION PACKAGE IF NOT EXISTS WORLDCUP_POOL_PKG
  COMMENT = 'World Cup 2026 Prediction Pool - company-wide tournament predictions';

-- Grant usage to the release stage
CREATE SCHEMA IF NOT EXISTS WORLDCUP_POOL_PKG.STAGE;
CREATE STAGE IF NOT EXISTS WORLDCUP_POOL_PKG.STAGE.APP_CODE
  DIRECTORY = (ENABLE = TRUE);
```

## 2. Upload App Files to Stage

```bash
# Upload all app files
snow stage copy app/manifest.yml @WORLDCUP_POOL_PKG.STAGE.APP_CODE/ --overwrite
snow stage copy app/setup_script.sql @WORLDCUP_POOL_PKG.STAGE.APP_CODE/ --overwrite
snow stage copy app/readme.md @WORLDCUP_POOL_PKG.STAGE.APP_CODE/ --overwrite
snow stage copy app/procedures/ @WORLDCUP_POOL_PKG.STAGE.APP_CODE/procedures/ --overwrite
snow stage copy app/data/ @WORLDCUP_POOL_PKG.STAGE.APP_CODE/data/ --overwrite
```

Or use the helper script:
```bash
./scripts/create_version.sh
```

## 3. Add a Version

```sql
ALTER APPLICATION PACKAGE WORLDCUP_POOL_PKG
  ADD VERSION v1_0
  USING '@WORLDCUP_POOL_PKG.STAGE.APP_CODE';

-- Set as the default release directive
ALTER APPLICATION PACKAGE WORLDCUP_POOL_PKG
  SET DEFAULT RELEASE DIRECTIVE
  VERSION = v1_0
  PATCH = 0;
```

## 4. Create the Listing (Snowsight UI)

The listing must be created through Snowsight — there is no full CLI automation for this step.

### Steps:

1. Navigate to **Data Products → Provider Studio** in Snowsight
2. Click **+ Listing**
3. Select **"Only Specified Consumers"** (for org-internal) or **"Anyone on Snowflake Marketplace"** (for public)
4. Fill in listing details:
   - **Title:** World Cup 2026 Prediction Pool
   - **Subtitle:** Run a company-wide World Cup prediction competition inside Snowflake
   - **Description:** (use content from app/readme.md)
   - **Category:** Business Intelligence / Other
   - **App Package:** WORLDCUP_POOL_PKG
5. Add screenshots (from `docs/screenshots/`)
6. Set pricing to **Free**
7. Click **Publish**

### For Organization-Internal Listings:

If sharing only within your Snowflake org:
1. Under "Who can discover this listing", select **"Only specified consumers"**
2. Add the target account identifiers (org.account format)

## 5. Push New Versions

When you have updates to ship:

```sql
-- Upload updated files to stage first (see scripts/create_version.sh)

-- Add a new patch to existing version
ALTER APPLICATION PACKAGE WORLDCUP_POOL_PKG
  ADD PATCH FOR VERSION v1_0
  USING '@WORLDCUP_POOL_PKG.STAGE.APP_CODE';

-- Or create a new version for breaking changes
ALTER APPLICATION PACKAGE WORLDCUP_POOL_PKG
  ADD VERSION v1_1
  USING '@WORLDCUP_POOL_PKG.STAGE.APP_CODE';

ALTER APPLICATION PACKAGE WORLDCUP_POOL_PKG
  SET DEFAULT RELEASE DIRECTIVE
  VERSION = v1_1
  PATCH = 0;
```

Consumers on the default release directive will auto-upgrade on next interaction.

## 6. Monitor Consumer Installations

```sql
-- See who has installed
SELECT *
FROM SNOWFLAKE.DATA_SHARING_USAGE.MARKETPLACE_PAID_USAGE_DAILY
WHERE LISTING_DISPLAY_NAME = 'World Cup 2026 Prediction Pool';

-- Check application events (if telemetry is enabled in manifest)
SELECT *
FROM SNOWFLAKE.DATA_SHARING_USAGE.APPLICATION_TELEMETRY_DAILY
WHERE APPLICATION_PACKAGE_NAME = 'WORLDCUP_POOL_PKG'
ORDER BY EVENT_DATE DESC;

-- List all versions
SHOW VERSIONS IN APPLICATION PACKAGE WORLDCUP_POOL_PKG;
```

## 7. Update Shared Match Data

The provider account runs a scheduled task to sync match scores from football-data.org. This data is shared with all consumers via the application package's shared content.

```sql
-- Manual trigger (if needed)
EXECUTE TASK WORLDCUP_POOL_PROVIDER.SYNC.REFRESH_SCORES_TASK;

-- Check last sync
SELECT *
FROM WORLDCUP_POOL_PROVIDER.SYNC.SYNC_LOG
ORDER BY SYNC_TIMESTAMP DESC
LIMIT 5;
```

Consumers automatically see updated scores — no action needed on their side.

## 8. Decommission

After the tournament ends:

```sql
-- Option A: Unpublish but keep package (consumers keep existing installs)
-- Done via Snowsight: Provider Studio → Listing → Unpublish

-- Option B: Drop everything (forces consumer uninstall)
DROP APPLICATION PACKAGE WORLDCUP_POOL_PKG;
```
