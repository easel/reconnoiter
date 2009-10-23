CREATE OR REPLACE FUNCTION stratcon.rollup_metric_numeric_5m() RETURNS void
AS $$
DECLARE
 v_sql TEXT;
 v_min_whence TIMESTAMPTZ;
 v_max_rollup_5 TIMESTAMPTZ;
 v_whence TIMESTAMPTZ;
 rows INT;
 v_nrunning INT;
 v_taskid int;
 v_locked boolean;
 whenceint RECORD;

 v_rec RECORD;
 v_info stratcon.metric_numeric_rollup_segment%rowtype;
 v_offset smallint; 
 v_init boolean := false; 
BEGIN

  SELECT id INTO v_taskid FROM tasklock WHERE name = 'rollup_metric_numeric_5m';
  IF v_taskid IS NULL THEN
    INSERT INTO tasklock (id, name) VALUES (nextval('tasklock_id_seq'), 'rollup_metric_numeric_5m')
      RETURNING id into v_taskid;
  END IF;

  select pg_try_advisory_lock(43191, v_taskid) into v_locked;

  IF v_locked = false THEN
    RAISE NOTICE 'rollup_metric_numeric_5m already running';
    RETURN ;
  END IF;

  FOR whenceint IN SELECT * FROM metric_numeric_rollup_queue WHERE interval='5m' LOOP

    SELECT MIN(whence) FROM metric_numeric_rollup_queue WHERE interval='5m'
        INTO v_min_whence;
        
    SELECT MAX(rollup_time) FROM metric_numeric_rollup_5m
         INTO v_max_rollup_5;        
 
    -- Insert Log for 20 minutes rollup
   
    SELECT whence FROM metric_numeric_rollup_queue 
        WHERE whence=date_trunc('H',v_min_whence) + (round(extract('minute' from v_min_whence)/20)*20) * '1 minute'::interval and interval='20m'
        INTO v_whence;
    IF NOT FOUND THEN
       INSERT INTO  metric_numeric_rollup_queue 
           VALUES(date_trunc('H',v_min_whence) + (round(extract('minute' from v_min_whence)/20)*20) * '1 minute'::interval,'20m');
    END IF;

    -- Insert Log for 30 minutes rollup
   
    SELECT whence FROM metric_numeric_rollup_queue 
        WHERE whence=date_trunc('H',v_min_whence) + (round(extract('minute' from v_min_whence)/30)*30) * '1 minute'::interval and interval='30m'
        INTO v_whence;
    IF NOT FOUND THEN
       INSERT INTO  metric_numeric_rollup_queue 
           VALUES(date_trunc('H',v_min_whence) + (round(extract('minute' from v_min_whence)/30)*30) * '1 minute'::interval,'30m');
    END IF;

    FOR v_info IN SELECT * FROM stratcon.window_robust_derive(v_min_whence) LOOP

        v_offset := ( 12*(extract('hour' from v_min_whence at time zone 'UTC'))+floor(extract('minute' from v_min_whence at time zone 'UTC')/5) );   
        v_info.rollup_time := date_trunc('day', v_info.rollup_time AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';

        v_init := false;
        SELECT * FROM metric_numeric_rollup_5m WHERE rollup_time = v_info.rollup_time AND sid=v_info.sid AND name=v_info.name INTO v_rec;
	IF NOT FOUND THEN 
		SELECT * FROM stratcon.init_metric_numeric_rollup('5m') INTO v_rec; 
		v_init := true; 
	END IF;

	v_rec.sid := v_info.sid;
	v_rec.name := v_info.name; 
	v_rec.rollup_time := v_info.rollup_time;
        v_rec.count_rows[v_offset] := v_info.count_rows;
        v_rec.avg_value[v_offset] := v_info.avg_value;  
        v_rec.counter_dev[v_offset] := v_info.counter_dev;  

	IF v_init THEN
		INSERT INTO metric_numeric_rollup_5m (sid,name,rollup_time,count_rows,avg_value,counter_dev)
			VALUES (v_rec.sid,v_rec.name,v_rec.rollup_time,v_rec.count_rows,v_rec.avg_value,v_rec.counter_dev); 
	ELSE
		UPDATE metric_numeric_rollup_5m SET (count_rows,avg_value,counter_dev) 
			= (v_rec.count_rows,v_rec.avg_value,v_rec.counter_dev)
			WHERE rollup_time = v_info.rollup_time  AND sid = v_info.sid  AND name = v_info.name; 
	END IF;

    END LOOP;
 
    -- Delete from whence log table
    DELETE FROM metric_numeric_rollup_queue WHERE WHENCE=v_min_whence AND INTERVAL='5m';
 
    v_min_whence:= NULL;
    v_max_rollup_5:= NULL;
 
  END LOOP;

  PERFORM pg_advisory_unlock(43191, v_taskid); 
  
RETURN;

EXCEPTION
    WHEN RAISE_EXCEPTION THEN
         PERFORM pg_advisory_unlock(43191, v_taskid); 
         RAISE EXCEPTION '%', SQLERRM;
    WHEN OTHERS THEN
         PERFORM pg_advisory_unlock(43191, v_taskid); 
         RAISE NOTICE '%', SQLERRM;
END
$$
LANGUAGE plpgsql
SECURITY DEFINER
;
