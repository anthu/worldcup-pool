-- Finished matches with typed columns ready for scoring
with source as (
    select * from {{ source('provider', 'matches') }}
)

select
    id::varchar as match_id,
    external_match_id::varchar as external_match_id,
    upper(trim(coalesce(stage, ''))) as stage,
    matchday::int as matchday,
    upper(trim(group_key)) as group_key,
    upper(trim(home_team_code)) as home_team_code,
    upper(trim(away_team_code)) as away_team_code,
    home_team_name,
    away_team_name,
    kickoff_utc,
    upper(trim(status)) as status,
    home_score::int as home_score,
    away_score::int as away_score,
    upper(trim(winner_team_code)) as winner_team_code,
    goal_events
from source
where status = 'FINISHED'
  and home_score is not null
  and away_score is not null
