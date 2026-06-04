-- Reusable macro: graduated stage multiplier
-- GROUP_STAGE=1.0, LAST_32/ROUND_OF_32=1.5, LAST_16/ROUND_OF_16=2.0,
-- QUARTER_FINALS=2.5, SEMI_FINALS/THIRD_PLACE/FINAL=3.0

{% macro stage_multiplier(stage_column) %}
    case upper(trim(coalesce({{ stage_column }}, '')))
        when 'LAST_32'        then 1.5
        when 'ROUND_OF_32'    then 1.5
        when 'LAST_16'        then 2.0
        when 'ROUND_OF_16'    then 2.0
        when 'QUARTER_FINALS' then 2.5
        when 'SEMI_FINALS'    then 3.0
        when 'THIRD_PLACE'    then 3.0
        when 'FINAL'          then 3.0
        else 1.0
    end
{% endmacro %}
