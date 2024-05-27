-- Fixes the `scoreboardpos` field in player_game_stats records
-- where they were sent incorrectly.
--
-- 1. Create a temporary table to drive the fixes and track status.
-- 2. Iterate over the records in that table, fixing on a per-game basis. 
-- 3. Drop the table.
-- 4. Repeat with a different selection of games to fix!

DROP TABLE IF EXISTS tmp_scoreboardpos_game_ids;

CREATE TABLE tmp_scoreboardpos_game_ids AS
SELECT game_id, FALSE::boolean processed
FROM (
    SELECT game_id, min(scoreboardpos) scoreboardpos
    FROM player_game_stats
    WHERE create_dt >= '2024-01-01' and create_dt <= '2024-12-31'
    GROUP BY 1
) sbp
WHERE sbp.scoreboardpos != 1;

-- After the table is created, we can examine its origin with this query.
-- SELECT g.game_id, g.game_type_cd, s.server_id, s.name 
-- FROM games g 
-- JOIN tmp_scoreboardpos_game_ids tmp ON g.game_id = tmp.game_id 
-- JOIN servers s ON g.server_id = s.server_id;

CREATE OR REPLACE FUNCTION fix_scoreboardpos(in_game_id IN games.game_id%TYPE)
RETURNS VOID AS $$
BEGIN
    WITH fixed AS (
        SELECT player_game_stat_id, row_number() over(order by scoreboardpos, score desc, fastest) fixedpos, scoreboardpos, score, fastest 
        FROM player_game_stats where game_id = in_game_id
    )
    UPDATE player_game_stats pgs
    SET scoreboardpos = fixed.fixedpos
    FROM fixed
    WHERE pgs.player_game_stat_id = fixed.player_game_stat_id AND game_id = in_game_id;

END
$$ LANGUAGE plpgsql;

-- You can check the before and after modifications to spot check with this query:
-- select scoreboardpos, score from player_game_stats where game_id = 123456 order by scoreboardpos;

DO $$
DECLARE
    cur REFCURSOR;
    l_game_id games.game_id%TYPE;
BEGIN
    OPEN cur FOR SELECT game_id from tmp_scoreboardpos_game_ids WHERE processed = FALSE;
    LOOP
        FETCH cur into l_game_id;
        EXIT WHEN NOT FOUND;

        PERFORM fix_scoreboardpos(l_game_id);

        UPDATE tmp_scoreboardpos_game_ids SET processed=TRUE WHERE game_id = l_game_id;

    END LOOP;
    CLOSE cur;
END
$$ LANGUAGE plpgsql;
