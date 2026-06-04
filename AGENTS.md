# Deployment Guide

Step-by-step instructions to deploy the World Cup 2026 Prediction Pool on Snowflake.

## Prerequisites

- Snowflake account (Enterprise or higher recommended)
- ACCOUNTADMIN role (or equivalent privileges)
- Docker installed locally
- A football-data.org API key (free tier works) for match data sync

## Step 1: Create Snowflake Infrastructure

Run these SQL statements in your Snowflake account:

```sql
-- Database and schema
CREATE DATABASE IF NOT EXISTS WORLDCUP_POOL;
CREATE SCHEMA IF NOT EXISTS WORLDCUP_POOL.PROVIDER;

-- Warehouse (XSMALL with auto-suspend)
CREATE WAREHOUSE IF NOT EXISTS WORLDCUP_XS_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- Compute pool for SPCS
CREATE COMPUTE POOL IF NOT EXISTS WORLDCUP_POOL_COMPUTE
  MIN_NODES = 1
  MAX_NODES = 1
  INSTANCE_FAMILY = CPU_X64_XS
  AUTO_SUSPEND_SECS = 3600;

-- Image repository
CREATE IMAGE REPOSITORY IF NOT EXISTS WORLDCUP_POOL.PROVIDER.IMAGES;

-- External Access Integration (for football-data.org sync)
CREATE OR REPLACE NETWORK RULE FOOTBALL_DATA_RULE
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('api.football-data.org:443');

CREATE OR REPLACE NETWORK RULE SNOWFLAKE_EGRESS_RULE
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('<your-org>-<your-account>.snowflakecomputing.com:443');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION SNOWFLAKE_EGRESS_ACCESS
  ALLOWED_NETWORK_RULES = (FOOTBALL_DATA_RULE, SNOWFLAKE_EGRESS_RULE)
  ENABLED = TRUE;
```

## Step 2: Create Application Tables

```sql
USE SCHEMA WORLDCUP_POOL.PROVIDER;

CREATE TABLE IF NOT EXISTS USER_PROFILES (
  EMAIL VARCHAR NOT NULL PRIMARY KEY,
  DISPLAY_NAME VARCHAR,
  PROFILE_PICTURE VARCHAR,
  IS_ADMIN BOOLEAN DEFAULT FALSE,
  CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS MATCHES (
  MATCH_ID INTEGER NOT NULL PRIMARY KEY,
  HOME_TEAM VARCHAR NOT NULL,
  AWAY_TEAM VARCHAR NOT NULL,
  HOME_SCORE INTEGER,
  AWAY_SCORE INTEGER,
  MATCH_DATE TIMESTAMP_NTZ NOT NULL,
  STAGE VARCHAR NOT NULL,
  GROUP_NAME VARCHAR,
  STATUS VARCHAR DEFAULT 'SCHEDULED',
  VENUE VARCHAR,
  UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS PREDICTIONS (
  EMAIL VARCHAR NOT NULL,
  MATCH_ID INTEGER NOT NULL,
  HOME_SCORE INTEGER NOT NULL,
  AWAY_SCORE INTEGER NOT NULL,
  SUBMITTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (EMAIL, MATCH_ID)
);

CREATE TABLE IF NOT EXISTS TOURNAMENT_PICKS (
  EMAIL VARCHAR NOT NULL,
  PICK_TYPE VARCHAR NOT NULL,
  PICK_VALUE VARCHAR NOT NULL,
  SUBMITTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (EMAIL, PICK_TYPE, PICK_VALUE)
);
```

## Step 3: Build and Push the Docker Image

```bash
# Build for linux/amd64 (required for SPCS)
docker buildx build --platform linux/amd64 \
  -t worldcup-pool:v1 \
  -f app/container/Dockerfile \
  --load .

# Get your image registry URL
# Format: <orgname>-<acctname>.registry.snowflakecomputing.com/<db>/<schema>/images
REGISTRY="<orgname>-<acctname>.registry.snowflakecomputing.com/worldcup_pool/provider/images"

# Authenticate to the registry
docker login ${REGISTRY%%/*} -u <your_username>

# Tag and push
docker tag worldcup-pool:v1 ${REGISTRY}/worldcup-pool:v1
docker push ${REGISTRY}/worldcup-pool:v1
```

> **Important**: Always build with `--platform linux/amd64`. Building on Apple Silicon
> without this flag produces ARM images that fail with `exec format error` on SPCS.

## Step 4: Create the Service

```sql
CREATE SERVICE WORLDCUP_POOL.PROVIDER.WORLDCUP_POOL_SERVICE
  IN COMPUTE POOL WORLDCUP_POOL_COMPUTE
  QUERY_WAREHOUSE = WORLDCUP_XS_WH
  MIN_INSTANCES = 1
  MAX_INSTANCES = 1
  EXTERNAL_ACCESS_INTEGRATIONS = (SNOWFLAKE_EGRESS_ACCESS)
  FROM SPECIFICATION $$
spec:
  containers:
    - name: app
      image: /worldcup_pool/provider/images/worldcup-pool:v1
      env:
        SNOWFLAKE_DATABASE: WORLDCUP_POOL
        SNOWFLAKE_SCHEMA: PROVIDER
        SNOWFLAKE_WAREHOUSE: WORLDCUP_XS_WH
        ADMIN_EMAILS: your-email@company.com
  endpoints:
    - name: app
      port: 8000
      public: true
$$;
```

## Step 5: Access the App

```sql
-- Check service status
SELECT SYSTEM$GET_SERVICE_STATUS('WORLDCUP_POOL.PROVIDER.WORLDCUP_POOL_SERVICE');

-- Get the public endpoint URL
SHOW ENDPOINTS IN SERVICE WORLDCUP_POOL.PROVIDER.WORLDCUP_POOL_SERVICE;
```

The app will be available at a URL like:
`https://<random>-<orgname>-<acctname>.snowflakecomputing.app`

Users authenticate via Snowflake SSO automatically.

## Step 6: Grant Access to Users

Users need the ability to access the service endpoint. Grant via role:

```sql
CREATE ROLE IF NOT EXISTS WORLDCUP_POOL_USER;
GRANT USAGE ON DATABASE WORLDCUP_POOL TO ROLE WORLDCUP_POOL_USER;
GRANT USAGE ON SCHEMA WORLDCUP_POOL.PROVIDER TO ROLE WORLDCUP_POOL_USER;

-- Grant to specific users
GRANT ROLE WORLDCUP_POOL_USER TO USER <username>;
```

## Updating the App

To deploy a new version:

```bash
# Rebuild with a new tag
docker buildx build --platform linux/amd64 -t worldcup-pool:v2 -f app/container/Dockerfile --load .
docker tag worldcup-pool:v2 ${REGISTRY}/worldcup-pool:v2
docker push ${REGISTRY}/worldcup-pool:v2
```

```sql
-- Update the running service
ALTER SERVICE WORLDCUP_POOL.PROVIDER.WORLDCUP_POOL_SERVICE
FROM SPECIFICATION $$
spec:
  containers:
    - name: app
      image: /worldcup_pool/provider/images/worldcup-pool:v2
      env:
        SNOWFLAKE_DATABASE: WORLDCUP_POOL
        SNOWFLAKE_SCHEMA: PROVIDER
        SNOWFLAKE_WAREHOUSE: WORLDCUP_XS_WH
        ADMIN_EMAILS: your-email@company.com
  endpoints:
    - name: app
      port: 8000
      public: true
$$;
```

## Troubleshooting

### "exec format error"
The image was built for ARM (Apple Silicon). Rebuild with `--platform linux/amd64`.

### "Account must be specified"
The `SNOWFLAKE_ACCOUNT` env var isn't being injected. SPCS injects this automatically — do NOT set it manually in the service spec. The app reads it from the environment.

### "Client is unauthorized to use Snowpark Container Services OAuth token"
You're using the wrong account identifier format. SPCS expects the account locator (e.g., `HE80908`), not the org-account format (e.g., `SFSEEUROPE-AHUCK`).

### Connection timeout
The service needs an External Access Integration to reach the Snowflake host. Make sure `SNOWFLAKE_EGRESS_ACCESS` includes a network rule for your account's hostname.

### "No active warehouse selected"
Add `QUERY_WAREHOUSE = WORLDCUP_XS_WH` to the `CREATE SERVICE` statement.

### Service status shows FAILED
Check logs: `CALL SYSTEM$GET_SERVICE_LOGS('WORLDCUP_POOL.PROVIDER.WORLDCUP_POOL_SERVICE', 0, 'app', 100);`

## Terraform (Optional)

Infrastructure can be managed with Terraform. See the `terraform/` directory:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## dbt Scoring (Optional)

The `dbt_scoring/` directory contains dbt models for calculating scores outside the app:

```bash
cd dbt_scoring
dbt run --profiles-dir .
```

This produces a `mart_leaderboard` table with full scoring breakdowns.

## Native App / Marketplace (Optional)

To distribute via the Snowflake Marketplace:

1. Create an Application Package using `app/manifest.yml` and `app/setup_script.sql`
2. Push the container image to the package's image repository
3. Create a listing in Provider Studio

See `docs/LISTING.md` for Marketplace listing content.
