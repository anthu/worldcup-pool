-- Top scorer goal points: 2 base pts per goal scored by a player in user's picks
-- Each goal event matched to any of the user's top_scorer picks earns points.
-- Points multiplied by stage multiplier of the match.

with predictions as (
    select * from {{ ref('stg_predictions') }}
),

-- Extract user's top scorer picks from tournament_predictions.notes_json
user_scorer_picks as (
    select
        tp.user_id::varchar as user_id,
        lower(trim(p.value:player_name::varchar)) as pick_player_name,
        upper(trim(p.value:country_code::varchar)) as pick_country_code
    from {{ source('app', 'tournament_predictions') }} tp,
        lateral flatten(input => tp.notes_json:top_scorers) p
    where tp.notes_json is not null
      and tp.notes_json:top_scorers is not null
      and p.value:player_name is not null
      and trim(p.value:country_code::varchar) <> '?'
),

-- Flatten goal events from each finished match
match_goals as (
    select
        pred.user_id,
        pred.match_id,
        pred.stage,
        lower(trim(g.value:player_name::varchar)) as scorer_name,
        upper(trim(g.value:team_code::varchar)) as scorer_team_code
    from predictions pred,
        lateral flatten(input => parse_json(pred.goal_events), outer => true) g
    where g.value:player_name is not null
),

-- Match goals to user's picks (case-insensitive name match + team code match)
-- Using substring containment for flexible name matching (>=5 chars)
matched_goals as (
    select
        mg.user_id,
        mg.match_id,
        mg.stage,
        mg.scorer_name,
        mg.scorer_team_code,
        usp.pick_player_name,
        -- Deduplicate: each pick can match at most once per goal event
        row_number() over (
            partition by mg.user_id, mg.match_id, mg.scorer_name, mg.scorer_team_code
            order by usp.pick_player_name
        ) as pick_rn
    from match_goals mg
    inner join user_scorer_picks usp
        on usp.user_id = mg.user_id
       and usp.pick_country_code = mg.scorer_team_code
       and (
           mg.scorer_name = usp.pick_player_name
           or (length(usp.pick_player_name) >= 5 and contains(mg.scorer_name, usp.pick_player_name))
           or (length(mg.scorer_name) >= 5 and contains(usp.pick_player_name, mg.scorer_name))
       )
),

-- Distinct pick matches per user per match (one pick matching multiple goals = multiple pts)
goal_counts as (
    select
        user_id,
        match_id,
        stage,
        count(*) as goals_matched
    from matched_goals
    where pick_rn = 1
    group by user_id, match_id, stage
)

select
    user_id,
    match_id,
    stage,
    goals_matched,
    round(goals_matched * 2 * {{ stage_multiplier('stage') }}) as points_scorer_goals
from goal_counts
