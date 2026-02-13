-- Enable gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create enum type only if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'event_type'
  ) THEN
    CREATE TYPE event_type AS ENUM (
      'IN',
      'OUT',
      'MEAL_START',
      'MEAL_END',
      'PAID10_START',
      'PAID10_END'
    );
  END IF;
END $$;

-- Employees table
CREATE TABLE IF NOT EXISTS employees (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_code text NOT NULL UNIQUE,
  full_name     text NOT NULL,
  pin_hash      text NOT NULL,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Automatically set updated_at on UPDATE
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS employees_set_updated_at ON employees;

CREATE TRIGGER employees_set_updated_at
BEFORE UPDATE ON employees
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Time events table
CREATE TABLE IF NOT EXISTS time_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id   uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  event_type    event_type NOT NULL,
  event_time    timestamptz NOT NULL DEFAULT now(),
  kiosk_id      text,
  meta          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Helpful indexes for queries
CREATE INDEX IF NOT EXISTS idx_time_events_employee_time
ON time_events (employee_id, event_time);

CREATE INDEX IF NOT EXISTS idx_time_events_time
ON time_events (event_time);
