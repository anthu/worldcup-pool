-- Final leaderboard: aggregate all point types per user
-- Tournament winner bonus: +25 flat if champion pick matches final winner

with match_pts as (
    select
        user_id,
        sum(points_outcome) as total_outcome,
        sum(points_exact) as total_exact
    from {{ ref('int_match_points') }}
    group by user_id
),

advancer_pts as (
    select
        user_id,
        sum(points_advancer) as total_advancer
    from {{ ref('int_advancer_points') }}
    group by user_id
),

scorer_pts as (
    select
        user_id,
        sum(points_scorer_goals) as total_scorer_goals_v2
    from {{ ref('int_scorer_points') }}
    group by user_id
),

-- Determine actual tournament winner from final match
actual_winner as (
    select
        case
            when winner_team_code is not null
                 and (winner_team_code = home_team_code or winner_team_code = away_team_code)
                then winner_team_code
            when home_score > away_score then home_team_code
            when away_score > home_score then away_team_code
            else null
        end as champion_team_code
    from {{ ref('stg_matches') }}
    where stage = 'FINAL'
    order by kickoff_utc desc
    limit 1
),

-- User tournament picks
tournament_winner_pts as (
    select
        tp.user_id,
        case
            when aw.champion_team_code is not null
                 and upper(trim(tp.winner_team_code)) = aw.champion_team_code
                then 25
            else 0
        end as points_tournament_winner
    from {{ ref('stg_tournament_picks') }} tp
    cross join actual_winner aw
),

-- All eligible users: anyone with predictions or a profile
eligible_users as (
    select distinct user_id
    from {{ source('app', 'match_predictions') }}
    where home_goals is not null and away_goals is not null
    union
    select distinct user_id::varchar as user_id
    from {{ source('app', 'user_profiles') }}
),

aggregated as (
    select
        eu.user_id,
        coalesce(mp.total_outcome, 0) as points_outcome,
        coalesce(mp.total_exact, 0) as points_exact,
        coalesce(sp.total_scorer_goals_v2, 0) as points_scorer_goals,
        coalesce(ap.total_advancer, 0) as points_advancer,
        coalesce(tw.points_tournament_winner, 0) as points_tournament_winner
    from eligible_users eu
    left join match_pts mp on mp.user_id = eu.user_id
    left join advancer_pts ap on ap.user_id = eu.user_id
    left join scorer_pts sp on sp.user_id = eu.user_id
    left join tournament_winner_pts tw on tw.user_id = eu.user_id
),

with_total as (
    select
        *,
        points_outcome + points_exact + points_scorer_goals
            + points_advancer + points_tournament_winner as total_points
    from aggregated
),

ranked as (
    select
        wt.*,
        up.display_name,
        rank() over (order by wt.total_points desc) as rank
    from with_total wt
    left join {{ source('app', 'user_profiles') }} up
        on up.user_id::varchar = wt.user_id
)

select
    rank,
    user_id,
    display_name,
    total_points,
    points_outcome,
    points_exact,
    points_scorer_goals,
    points_advancer,
    points_tournament_winner
from ranked
order by rank asc, lower(coalesce(display_name, '')), user_id
