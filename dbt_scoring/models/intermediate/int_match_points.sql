-- Per-user, per-match scoring: outcome + exact points
-- PT_OUTCOME=2, PT_EXACT=5
-- Exact score is EXCLUSIVE with outcome (5 pts not 7)
-- Scorer goals are computed separately in int_scorer_points.sql

with predictions as (
    select * from {{ ref('stg_predictions') }}
),

scored as (
    select
        p.user_id,
        p.match_id,
        p.stage,
        {{ stage_multiplier('p.stage') }} as mult,

        -- Outcome check: both predict same winner/draw direction
        case
            when p.pred_home > p.pred_away and p.act_home > p.act_away then true
            when p.pred_home < p.pred_away and p.act_home < p.act_away then true
            when p.pred_home = p.pred_away and p.act_home = p.act_away then true
            else false
        end as outcome_correct,

        -- Exact score check
        case
            when p.pred_home = p.act_home and p.pred_away = p.act_away then true
            else false
        end as exact_correct

    from predictions p
)

select
    user_id,
    match_id,
    stage,
    mult,
    -- Exact is exclusive: if exact, award 5*mult; if only outcome, award 2*mult; else 0
    case
        when exact_correct then round(5 * mult)
        else 0
    end as points_exact,
    case
        when not exact_correct and outcome_correct then round(2 * mult)
        else 0
    end as points_outcome
from scored
