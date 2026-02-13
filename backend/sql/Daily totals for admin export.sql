WITH events AS (
  SELECT
    e.id AS employee_id,
    e.employee_code,
    e.full_name,
    (te.event_time AT TIME ZONE 'America/Los_Angeles')::date AS work_date,
    te.id AS event_id,
    te.event_type,
    te.event_time,

    LEAD(te.event_type) OVER (
      PARTITION BY e.id, (te.event_time AT TIME ZONE 'America/Los_Angeles')::date
      ORDER BY te.event_time, te.id
    ) AS next_type,

    LEAD(te.event_time) OVER (
      PARTITION BY e.id, (te.event_time AT TIME ZONE 'America/Los_Angeles')::date
      ORDER BY te.event_time, te.id
    ) AS next_time

  FROM time_events te
  JOIN employees e ON e.id = te.employee_id
  WHERE te.event_time >= ($1::date)::timestamptz
    AND te.event_time <  (($2::date + 1)::date)::timestamptz
),

in_pairs AS (
  SELECT
    in_ev.employee_id,
    in_ev.work_date,
    in_ev.event_time AS in_time,
    out_ev.event_time AS out_time
  FROM events in_ev

  -- find the first OUT after this IN
  JOIN LATERAL (
    SELECT e2.event_time
    FROM events e2
    WHERE e2.employee_id = in_ev.employee_id
      AND e2.work_date    = in_ev.work_date
      AND e2.event_type   = 'OUT'
      AND (
        e2.event_time > in_ev.event_time
        OR (e2.event_time = in_ev.event_time AND e2.event_id > in_ev.event_id)
      )
    ORDER BY e2.event_time, e2.event_id
    LIMIT 1
  ) out_ev ON TRUE

  -- find the next IN after this IN (to prevent pairing across shifts)
  LEFT JOIN LATERAL (
    SELECT e3.event_time, e3.event_id
    FROM events e3
    WHERE e3.employee_id = in_ev.employee_id
      AND e3.work_date    = in_ev.work_date
      AND e3.event_type   = 'IN'
      AND (
        e3.event_time > in_ev.event_time
        OR (e3.event_time = in_ev.event_time AND e3.event_id > in_ev.event_id)
      )
    ORDER BY e3.event_time, e3.event_id
    LIMIT 1
  ) next_in ON TRUE

  WHERE in_ev.event_type = 'IN'
    AND (
      next_in.event_time IS NULL
      OR out_ev.event_time < next_in.event_time
      OR (out_ev.event_time = next_in.event_time AND out_ev.event_time IS NOT NULL)
    )
),

gross_by_day AS (
  SELECT
    employee_id,
    work_date,
    COALESCE(SUM(out_time - in_time), interval '0') AS gross_time
  FROM in_pairs
  GROUP BY employee_id, work_date
),

daily AS (
  SELECT
    e.employee_id,
    e.employee_code,
    e.full_name,
    e.work_date,

    MIN(e.event_time) FILTER (WHERE e.event_type = 'IN')  AS in_time,
    MAX(e.event_time) FILTER (WHERE e.event_type = 'OUT') AS out_time,

    COALESCE(MAX(g.gross_time), interval '0') AS gross_time,

    COALESCE(
      SUM(e.next_time - e.event_time) FILTER (
        WHERE e.event_type = 'MEAL_START' AND e.next_type = 'MEAL_END'
      ),
      interval '0'
    ) AS meal_total,

    COUNT(*) FILTER (WHERE e.event_type = 'PAID10_END') AS paid10_count,

    COALESCE(
      SUM(
        GREATEST((e.next_time - e.event_time) - interval '10 minutes', interval '0')
      ) FILTER (
        WHERE e.event_type = 'PAID10_START' AND e.next_type = 'PAID10_END'
      ),
      interval '0'
    ) AS paid10_overage_unpaid

  FROM events e
  LEFT JOIN gross_by_day g
    ON g.employee_id = e.employee_id
   AND g.work_date    = e.work_date

  GROUP BY e.employee_id, e.employee_code, e.full_name, e.work_date
)

SELECT
  employee_code,
  full_name,
  work_date,
  in_time,
  out_time,
  gross_time,
  meal_total,
  paid10_count,
  paid10_overage_unpaid,
  GREATEST(gross_time - meal_total - paid10_overage_unpaid, interval '0') AS net_worked_time
FROM daily
ORDER BY work_date, employee_code;
