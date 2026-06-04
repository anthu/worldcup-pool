-- Match predictions joined with match metadata for scoring context
with predictions as (
    select * from {{ source('app', 'match_predictions') }}
),

matches as (
    select * from {{ ref('stg_matches') }}
)

select
    p.user_id::varchar as user_id,
    p.match_id::varchar as match_id,
    p.home_goals::int as pred_home,
    p.away_goals::int as pred_away,
    upper(trim(p.advance_team_code)) as pred_advance_team_code,
    m.stage,
    m.home_team_code,
    m.away_team_code,
    m.home_score as act_home,
    m.away_score as act_away,
    m.winner_team_code,
    m.goal_events
from predictions p
inner join matches m
    on p.match_id::varchar = m.match_id
where p.home_goals is not null
  and p.away_goals is not null
