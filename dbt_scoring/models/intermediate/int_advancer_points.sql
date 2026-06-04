-- Knockout advancer bonus: 3 base pts * stage multiplier
-- Credit for correctly predicting a team advances from any match in that round.
-- Round-level logic: build predicted advancers set per stage, match against actual.

with knockout_matches as (
    -- All knockout matches (finished or not) from provider
    select
        m.id::varchar as match_id,
        upper(trim(m.stage)) as stage,
        upper(trim(m.home_team_code)) as home_team_code,
        upper(trim(m.away_team_code)) as away_team_code,
        m.home_score::int as home_score,
        m.away_score::int as away_score,
        upper(trim(m.winner_team_code)) as winner_team_code,
        upper(trim(m.status)) as status
    from {{ source('provider', 'matches') }} m
    where upper(trim(coalesce(nullif(trim(m.stage), ''), 'GROUP_STAGE'))) <> 'GROUP_STAGE'
),

user_predictions as (
    select
        mp.user_id::varchar as user_id,
        mp.match_id::varchar as match_id,
        mp.home_goals::int as pred_home,
        mp.away_goals::int as pred_away,
        upper(trim(mp.advance_team_code)) as pred_advance_team_code
    from {{ source('app', 'match_predictions') }} mp
    where mp.home_goals is not null
      and mp.away_goals is not null
),

-- Determine predicted advancer per user per match
predicted_advancers as (
    select
        up.user_id,
        km.match_id,
        km.stage,
        case
            when up.pred_home > up.pred_away then km.home_team_code
            when up.pred_away > up.pred_home then km.away_team_code
            -- Draw: use advance_team_code pick
            when up.pred_advance_team_code = km.home_team_code then km.home_team_code
            when up.pred_advance_team_code = km.away_team_code then km.away_team_code
            else null
        end as predicted_team
    from user_predictions up
    inner join knockout_matches km
        on km.match_id = up.match_id
    where km.home_team_code <> '?'
      and km.away_team_code <> '?'
),

-- Actual advancer from finished knockout matches
actual_advancers as (
    select
        match_id,
        stage,
        case
            when winner_team_code is not null
                 and (winner_team_code = home_team_code or winner_team_code = away_team_code)
                then winner_team_code
            when home_score > away_score then home_team_code
            when away_score > home_score then away_team_code
            else null  -- draw without winner_team_code (penalties unknown)
        end as actual_team
    from knockout_matches
    where status = 'FINISHED'
      and home_score is not null
      and away_score is not null
),

-- Per user per stage: did they predict any team that actually advanced?
-- Award points on the match where the team actually advanced.
stage_predicted_sets as (
    select
        user_id,
        stage,
        predicted_team
    from predicted_advancers
    where predicted_team is not null
    group by user_id, stage, predicted_team
),

matched as (
    select
        sps.user_id,
        aa.match_id,
        aa.stage,
        aa.actual_team,
        row_number() over (
            partition by sps.user_id, aa.stage, aa.actual_team
            order by aa.match_id
        ) as rn
    from stage_predicted_sets sps
    inner join actual_advancers aa
        on aa.stage = sps.stage
       and aa.actual_team = sps.predicted_team
)

select
    user_id,
    match_id,
    stage,
    round(3 * {{ stage_multiplier('stage') }}) as points_advancer
from matched
where rn = 1  -- each predicted team earns credit only once per stage
