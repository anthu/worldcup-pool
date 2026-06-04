-- Tournament winner and top scorer picks per user
with source as (
    select * from {{ source('app', 'tournament_predictions') }}
)

select
    user_id::varchar as user_id,
    upper(trim(tournament_winner_team_code)) as winner_team_code,
    trim(top_scorer_player_name) as legacy_top_scorer,
    notes_json
from source
