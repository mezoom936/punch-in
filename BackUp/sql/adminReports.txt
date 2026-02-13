WITH events AS (
  SELECT
    e.id AS employee_id,
    e.employee_code,
    e.full_name,
    (te.event_time AT TIME ZONE 'America/Los_Angeles')::date AS work_date,
    te.id AS event_id,
    te.event_type,
    te.event_time,

    -- Next OUT after this row (same employee/day)
    MIN(te.event_time) FILTER (WHERE te.event_type = 'OUT')
      OVER (
        PARTITION BY e.id, (te.event_time AT TIME ZONE 'America/Los_Angeles')::date
        ORDER BY te.event_time, te.id
        ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING
      ) AS next_out_time,

    -- Next IN after this row (prevents pairing across shifts)
    MIN(te.event_time) FILTER (WHERE te.event_type = 'IN')
      OVER (
        PARTITION BY e.id, (te.event_time AT TIME ZONE 'America/Los_Angeles')::date
        ORDER BY te.event_time, te.id
        ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
      ) AS next_in_time,

    -- Next row (for meal/p10 pairing)
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

daily AS (
  SELECT
    events.employee_code,
    events.full_name,
    events.work_date,

    MIN(events.event_time) FILTER (WHERE events.event_type = 'IN')  AS in_time,
    MAX(events.event_time) FILTER (WHERE events.event_type = 'OUT') AS out_time,

    -- Gross = sum IN -> next OUT (no crossing into next shift)
    COALESCE(
      SUM(events.next_out_time - events.event_time) FILTER (
        WHERE events.event_type = 'IN'
          AND events.next_out_time IS NOT NULL
          AND (events.next_in_time IS NULL OR events.next_out_time < events.next_in_time)
      ),
      interval '0'
    ) AS gross_time,

    COALESCE(
      SUM(events.next_time - events.event_time) FILTER (
        WHERE events.event_type = 'MEAL_START' AND events.next_type = 'MEAL_END'
      ),
      interval '0'
    ) AS meal_total,

    COUNT(*) FILTER (WHERE events.event_type = 'PAID10_END') AS paid10_count,

    COALESCE(
      SUM(
        GREATEST((events.next_time - events.event_time) - interval '10 minutes', interval '0')
      ) FILTER (
        WHERE events.event_type = 'PAID10_START' AND events.next_type = 'PAID10_END'
      ),
      interval '0'
    ) AS paid10_overage_unpaid

  FROM events
  GROUP BY events.employee_code, events.full_name, events.work_date
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

