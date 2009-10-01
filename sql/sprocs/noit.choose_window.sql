-- Function: noit.choose_window(timestamp with time zone, timestamp with time zone, integer)

CREATE OR REPLACE FUNCTION noit.choose_window(IN in_start_time timestamp with time zone, IN in_end_time timestamp with time zone, IN in_hopeful_nperiods integer, OUT tablename text, OUT period interval, OUT nperiods integer)
  RETURNS SETOF record AS
$BODY$
declare
  window record;
begin
  -- Figure out which table we should be looking in
  for window in
    select atablename, aperiod, anperiods
    from (select aperiod, round(iv/isec) ::integer as anperiods, atablename,
                 abs(case when iv/isec - in_hopeful_nperiods < 0
                          then 10 * (in_hopeful_nperiods - iv/isec)
                          else iv/isec - in_hopeful_nperiods
                           end) as badness
            from (select extract('epoch' from in_end_time) -
                         extract('epoch' from in_start_time) as iv
                 ) i,
                 (   select 5*60 as isec, '5 minutes'::interval as aperiod,
                            'metric_numeric_rollup_5m' as atablename
                  union all
                     select 20*60 as isec, '20 minutes'::interval as aperiod,
                            'metric_numeric_rollup_20m' as atablename
                  union all
                     select 60*60 as isec, '1 hour'::interval as aperiod,
                            'metric_numeric_rollup_60m' as atablename
                  union all
                     select 6*60*60 as isec, '6 hours'::interval as aaperiod,
                            'metric_numeric_rollup_6hours' as atablename
                  union all
                     select 12*60*60 as isec, '12 hours'::interval as aperiod,
                            'metric_numeric_rollup_12hours' as atablename
                 ) ivs
         ) b
 order by badness asc
  limit 1
  loop
    tablename := window.atablename;
    period := window.aperiod;
    nperiods := window.anperiods;
    return next;
  end loop;
  return;
end
$BODY$
  LANGUAGE 'plpgsql' VOLATILE;
