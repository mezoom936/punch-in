WITH emp AS (
  SELECT id
  FROM employees
  WHERE employee_code = $1
),
today_events AS (
  SELECT
    te.id,
    te.event_type,
    te.event_time,

    -- next OUT after this row
    MIN(te.event_time) FILTER (WHERE te.event_type = 'OUT')
      OVER (
        ORDER BY te.event_time, te.id
        ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
      ) AS next_out_time,

    -- next IN after this row (prevents pairing across shifts)
    MIN(te.event_time) FILTER (WHERE te.event_type = 'IN')
      OVER (
        ORDER BY te.event_time, te.id
        ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
      ) AS next_in_time,

    LEAD(te.event_type) OVER (ORDER BY te.event_time, te.id) AS next_type,
    LEAD(te.event_time) OVER (ORDER BY te.event_time, te.id) AS next_time
  FROM time_events te
  WHERE te.employee_id = (SELECT id FROM emp)
    AND te.event_time >= (
      date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles')
      AT TIME ZONE 'America/Los_Angeles'
    )
    AND te.event_time < (
      (date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') + interval '1 day')
      AT TIME ZONE 'America/Los_Angeles'
    )
),
rollup AS (
  SELECT
    MIN(event_time) FILTER (WHERE event_type = 'IN')  AS in_time,
    MAX(event_time) FILTER (WHERE event_type = 'OUT') AS out_time,

    -- Gross = sum IN -> next OUT, only if that OUT is before the next IN
    COALESCE(
      SUM(next_out_time - event_time) FILTER (
        WHERE event_type = 'IN'
          AND next_out_time IS NOT NULL
          AND (next_in_time IS NULL OR next_out_time < next_in_time)
      ),
      interval '0'
    ) AS gross_time,

    COALESCE(
      SUM(next_time - event_time) FILTER (
        WHERE event_type = 'MEAL_START' AND next_type = 'MEAL_END'
      ),
      interval '0'
    ) AS meal_total,

    COUNT(*) FILTER (WHERE event_type = 'PAID10_END') AS paid10_count,

    COALESCE(
      SUM(
        GREATEST((next_time - event_time) - interval '10 minutes', interval '0')
      ) FILTER (
        WHERE event_type = 'PAID10_START' AND next_type = 'PAID10_END'
      ),
      interval '0'
    ) AS paid10_overage_unpaid
  FROM today_events
)
SELECT
  in_time,
  out_time,
  gross_time,
  meal_total,
  GREATEST(gross_time - meal_total - paid10_overage_unpaid, interval '0') AS net_worked_time,
  paid10_count,
  paid10_overage_unpaid
FROM rollup;
