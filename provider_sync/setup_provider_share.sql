-- ============================================================
-- Provider-side: Setup shared objects for the Native App listing
-- Run once as ACCOUNTADMIN or role with CREATE SHARE privileges
-- ============================================================

-- 1. Create the provider schema
CREATE SCHEMA IF NOT EXISTS WORLDCUP_POOL.PROVIDER;

-- 2. Matches table (synced from football-data.org)
CREATE TABLE IF NOT EXISTS WORLDCUP_POOL.PROVIDER.MATCHES (
    id                  NUMBER AUTOINCREMENT PRIMARY KEY,
    external_match_id   VARCHAR(50) NOT NULL UNIQUE,
    competition_code    VARCHAR(10) NOT NULL DEFAULT 'WC',
    stage               VARCHAR(50),
    matchday            NUMBER,
    group_key           VARCHAR(20),
    home_team_code      VARCHAR(16) NOT NULL,
    away_team_code      VARCHAR(16) NOT NULL,
    home_team_name      VARCHAR(100),
    away_team_name      VARCHAR(100),
    kickoff_utc         TIMESTAMP_NTZ NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'SCHEDULED',
    home_score          NUMBER,
    away_score          NUMBER,
    winner_team_code    VARCHAR(16),
    goal_events         VARIANT,
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 3. Teams reference table
CREATE TABLE IF NOT EXISTS WORLDCUP_POOL.PROVIDER.TEAMS (
    team_code   VARCHAR(16) NOT NULL PRIMARY KEY,
    team_name   VARCHAR(100) NOT NULL,
    group_key   VARCHAR(20) NOT NULL
);

-- Populate teams from WC2026 draw
MERGE INTO WORLDCUP_POOL.PROVIDER.TEAMS t
USING (
    SELECT column1 AS team_code, column2 AS team_name, column3 AS group_key
    FROM VALUES
        ('MEX', 'Mexico', 'GROUP_A'),
        ('RSA', 'South Africa', 'GROUP_A'),
        ('KOR', 'South Korea', 'GROUP_A'),
        ('CZE', 'Czech Republic', 'GROUP_A'),
        ('CAN', 'Canada', 'GROUP_B'),
        ('BIH', 'Bosnia and Herzegovina', 'GROUP_B'),
        ('QAT', 'Qatar', 'GROUP_B'),
        ('SUI', 'Switzerland', 'GROUP_B'),
        ('BRA', 'Brazil', 'GROUP_C'),
        ('MAR', 'Morocco', 'GROUP_C'),
        ('HAI', 'Haiti', 'GROUP_C'),
        ('SCO', 'Scotland', 'GROUP_C'),
        ('USA', 'United States', 'GROUP_D'),
        ('PAR', 'Paraguay', 'GROUP_D'),
        ('AUS', 'Australia', 'GROUP_D'),
        ('TUR', 'Turkey', 'GROUP_D'),
        ('GER', 'Germany', 'GROUP_E'),
        ('CUW', 'Curaçao', 'GROUP_E'),
        ('CIV', 'Ivory Coast', 'GROUP_E'),
        ('ECU', 'Ecuador', 'GROUP_E'),
        ('NED', 'Netherlands', 'GROUP_F'),
        ('JPN', 'Japan', 'GROUP_F'),
        ('SWE', 'Sweden', 'GROUP_F'),
        ('TUN', 'Tunisia', 'GROUP_F'),
        ('BEL', 'Belgium', 'GROUP_G'),
        ('EGY', 'Egypt', 'GROUP_G'),
        ('IRN', 'Iran', 'GROUP_G'),
        ('NZL', 'New Zealand', 'GROUP_G'),
        ('ESP', 'Spain', 'GROUP_H'),
        ('CPV', 'Cape Verde', 'GROUP_H'),
        ('KSA', 'Saudi Arabia', 'GROUP_H'),
        ('URU', 'Uruguay', 'GROUP_H'),
        ('FRA', 'France', 'GROUP_I'),
        ('SEN', 'Senegal', 'GROUP_I'),
        ('IRQ', 'Iraq', 'GROUP_I'),
        ('NOR', 'Norway', 'GROUP_I'),
        ('ARG', 'Argentina', 'GROUP_J'),
        ('ALG', 'Algeria', 'GROUP_J'),
        ('AUT', 'Austria', 'GROUP_J'),
        ('JOR', 'Jordan', 'GROUP_J'),
        ('POR', 'Portugal', 'GROUP_K'),
        ('COD', 'DR Congo', 'GROUP_K'),
        ('UZB', 'Uzbekistan', 'GROUP_K'),
        ('COL', 'Colombia', 'GROUP_K'),
        ('ENG', 'England', 'GROUP_L'),
        ('CRO', 'Croatia', 'GROUP_L'),
        ('GHA', 'Ghana', 'GROUP_L'),
        ('PAN', 'Panama', 'GROUP_L')
) s
ON t.team_code = s.team_code
WHEN MATCHED THEN UPDATE SET
    t.team_name = s.team_name,
    t.group_key = s.group_key
WHEN NOT MATCHED THEN INSERT (team_code, team_name, group_key)
    VALUES (s.team_code, s.team_name, s.group_key);

-- 4. External Access Integration for football-data.org API
CREATE OR REPLACE NETWORK RULE WORLDCUP_POOL.PROVIDER.FOOTBALL_DATA_RULE
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('api.football-data.org:443');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION FOOTBALL_DATA_API_ACCESS
    ALLOWED_NETWORK_RULES = (WORLDCUP_POOL.PROVIDER.FOOTBALL_DATA_RULE)
    ENABLED = TRUE;

-- 5. Secret for API token (user must set the value)
CREATE OR REPLACE SECRET WORLDCUP_POOL.PROVIDER.FOOTBALL_DATA_TOKEN
    TYPE = GENERIC_STRING
    SECRET_STRING = '<REPLACE_WITH_YOUR_API_TOKEN>';

-- 6. Task to auto-sync every 15 minutes during tournament
CREATE OR REPLACE TASK WORLDCUP_POOL.PROVIDER.SYNC_MATCHES_TASK
    SCHEDULE = '15 MINUTE'
    ALLOW_OVERLAPPING_EXECUTION = FALSE
    AS
    CALL WORLDCUP_POOL.PROVIDER.SYNC_MATCHES();

-- Resume when ready: ALTER TASK WORLDCUP_POOL.PROVIDER.SYNC_MATCHES_TASK RESUME;

-- 7. Create a SHARE for the listing (Declarative Sharing / Direct Share)
CREATE SHARE IF NOT EXISTS WORLDCUP_POOL_SHARE;

GRANT USAGE ON DATABASE WORLDCUP_POOL TO SHARE WORLDCUP_POOL_SHARE;
GRANT USAGE ON SCHEMA WORLDCUP_POOL.PROVIDER TO SHARE WORLDCUP_POOL_SHARE;
GRANT SELECT ON TABLE WORLDCUP_POOL.PROVIDER.MATCHES TO SHARE WORLDCUP_POOL_SHARE;
GRANT SELECT ON TABLE WORLDCUP_POOL.PROVIDER.TEAMS TO SHARE WORLDCUP_POOL_SHARE;
