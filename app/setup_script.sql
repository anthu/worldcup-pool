-- World Cup Prediction Pool - Native App Setup Script (v1 - no SPCS)
CREATE SCHEMA IF NOT EXISTS app_data;
CREATE APPLICATION ROLE IF NOT EXISTS app_user;
CREATE APPLICATION ROLE IF NOT EXISTS app_admin;
GRANT USAGE ON SCHEMA app_data TO APPLICATION ROLE app_user;
GRANT USAGE ON SCHEMA app_data TO APPLICATION ROLE app_admin;

-- Tables for consumer-local predictions
CREATE TABLE IF NOT EXISTS app_data.match_predictions (
    id VARCHAR(36) DEFAULT UUID_STRING(),
    user_id VARCHAR NOT NULL,
    match_id VARCHAR(36) NOT NULL,
    home_goals INT,
    away_goals INT,
    advance_team_code VARCHAR,
    created_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS app_data.tournament_predictions (
    id VARCHAR(36) DEFAULT UUID_STRING(),
    user_id VARCHAR NOT NULL,
    tournament_winner_team_code VARCHAR,
    top_scorer_player_name VARCHAR,
    notes_json VARIANT DEFAULT PARSE_JSON('{}'),
    created_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS app_data.user_profiles (
    user_id VARCHAR NOT NULL,
    display_name VARCHAR,
    nationality VARCHAR,
    expected_winner_team_code VARCHAR,
    profile_picture VARCHAR,
    created_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS app_data.pool_config (
    id INT DEFAULT 1,
    custom_logo VARCHAR,
    pool_name VARCHAR,
    updated_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Views over shared provider data
CREATE OR REPLACE VIEW app_data.matches AS SELECT * FROM shared_data.matches;
CREATE OR REPLACE VIEW app_data.teams AS SELECT * FROM shared_data.teams;

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app_data TO APPLICATION ROLE app_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA app_data TO APPLICATION ROLE app_user;
GRANT SELECT ON ALL VIEWS IN SCHEMA app_data TO APPLICATION ROLE app_user;
GRANT SELECT ON ALL VIEWS IN SCHEMA app_data TO APPLICATION ROLE app_admin;
