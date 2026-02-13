// server.js
require("dotenv").config();

// ===== Imports =====
const express = require("express");
const cors = require("cors");
const bcrypt = require("bcrypt");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const ExcelJS = require("exceljs");

const { pool } = require("./db");

// ===== Load SQL files =====
const todayTotalsSql = fs.readFileSync(
  path.join(__dirname, "sql", "todayTotals.sql"),
  "utf8"
);

const adminReportSql = fs.readFileSync(
  path.join(__dirname, "sql", "adminReport.sql"),
  "utf8"
);

// ===== App setup =====
const app = express();

app.use(cors());
app.use(express.json());

// Serve frontend files from /public
app.use(express.static(path.join(__dirname, "public")));

// ===== Helpers =====
async function getTodayState(employeeId) {
  const result = await pool.query(
    `
    SELECT event_type, event_time
    FROM time_events
    WHERE employee_id = $1
      AND event_time >= (
        date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles')
        AT TIME ZONE 'America/Los_Angeles'
      )
      AND event_time < (
        (date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') + interval '1 day')
        AT TIME ZONE 'America/Los_Angeles'
      )
    ORDER BY event_time ASC
    `,
    [employeeId]
  );

  // keep the rest of your function the same...


  let isClockedIn = false;
  let mealActive = false;

  let paid10Active = false;
  let paid10CompletedCount = 0;

  for (const ev of result.rows) {
    if (ev.event_type === "IN") isClockedIn = true;

    if (ev.event_type === "OUT") {
      isClockedIn = false;
      mealActive = false;
      paid10Active = false; // safety
    }

    if (ev.event_type === "MEAL_START") mealActive = true;
    if (ev.event_type === "MEAL_END") mealActive = false;

    if (ev.event_type === "PAID10_START") paid10Active = true;
    if (ev.event_type === "PAID10_END") {
      paid10Active = false;
      paid10CompletedCount += 1; // count completed breaks
    }
  }

  return { isClockedIn, mealActive, paid10Active, paid10CompletedCount, events: result.rows };
}

// ===== Admin auth (prototype) =====
// In-memory tokens (server restart clears them)
const adminTokens = new Set();

function requireAdmin(req, res, next) {
  const token = req.header("x-admin-token");
  if (!token || !adminTokens.has(token)) {
    return res.status(401).json({ ok: false, error: "Admin unauthorized" });
  }
  next();
}
function intervalToHHMMSS(v) {
  if (!v) return "00:00:00";

  // If already a string like "01:23:45.123"
  if (typeof v === "string") {
    return v.split(".")[0];
  }

  // If postgres returned an object
  if (typeof v === "object") {
    const h = Number(v.hours ?? 0);
    const m = Number(v.minutes ?? 0);
    const s = Number(v.seconds ?? 0);

    return (
      String(h).padStart(2, "0") + ":" +
      String(m).padStart(2, "0") + ":" +
      String(Math.floor(s)).padStart(2, "0")
    );
  }

  return String(v);
}


// ===== Page routes =====
app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.get("/admin", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "admin.html"));
});

// ===== Health check =====
app.get("/health", (req, res) => {
  res.json({ ok: true, message: "Server is running" });
});

// ===== DB check =====
app.get("/db-check", async (req, res) => {
  try {
    const result = await pool.query("SELECT now() AS server_time;");
    res.json({ ok: true, db_time: result.rows[0].server_time });
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message });
  }
});


// ===== Admin routes =====

// POST /admin/login { password }
app.post("/admin/login", (req, res) => {
  const { password } = req.body;

  if (!password) {
    return res.status(400).json({ ok: false, error: "Password is required" });
  }

  if (password !== process.env.ADMIN_PASSWORD) {
    return res.status(401).json({ ok: false, error: "Invalid admin password" });
  }

  const token = crypto.randomBytes(24).toString("hex");
  adminTokens.add(token);

  return res.json({ ok: true, token });
});

// GET /admin/report?start=YYYY-MM-DD&end=YYYY-MM-DD
app.get("/admin/report", requireAdmin, async (req, res) => {
  const { start, end } = req.query;

  if (!start || !end) {
    return res
      .status(400)
      .json({ ok: false, error: "start and end are required (YYYY-MM-DD)" });
  }

  try {
    const result = await pool.query(adminReportSql, [start, end]);
    return res.json({ ok: true, rows: result.rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});

// GET /admin/export.xlsx?start=YYYY-MM-DD&end=YYYY-MM-DD
app.get("/admin/export.xlsx", requireAdmin, async (req, res) => {
  const { start, end } = req.query;

  if (!start || !end) {
    return res
      .status(400)
      .json({ ok: false, error: "start and end are required (YYYY-MM-DD)" });
  }

  try {
    const result = await pool.query(adminReportSql, [start, end]);

    const wb = new ExcelJS.Workbook();
    const ws = wb.addWorksheet("Timesheet");

    // ✅ Convert timestamp/date -> "hh:mm AM/PM" in America/Los_Angeles
    function formatTimeOnlyLA(value) {
      if (!value) return "";

      // If SQL already returned a time string like "09:15 PM", keep it
      if (typeof value === "string" && !value.includes("T") && !value.includes("-")) {
        return value;
      }

      const d = new Date(value);
      if (isNaN(d.getTime())) return String(value);

      return d.toLocaleTimeString("en-US", {
        timeZone: "America/Los_Angeles",
        hour: "2-digit",
        minute: "2-digit",
        hour12: true,
      });
    }

    ws.columns = [
      { header: "Employee Code", key: "employee_code", width: 14 },
      { header: "Full Name", key: "full_name", width: 22 },
      { header: "Work Date", key: "work_date", width: 12 },
      { header: "In Time", key: "in_time", width: 22 },
      { header: "Out Time", key: "out_time", width: 22 },
      { header: "Gross Time", key: "gross_time", width: 14 },
      { header: "Meal Total", key: "meal_total", width: 14 },
      { header: "Net Worked", key: "net_worked_time", width: 14 },
      { header: "Paid 10 Count", key: "paid10_count", width: 14 },
      { header: "Paid10 Overage (Unpaid)", key: "paid10_overage_unpaid", width: 20 },
    ];

    ws.getRow(1).font = { bold: true };

    for (const r of result.rows) {
      ws.addRow({
        employee_code: r.employee_code,
        full_name: r.full_name,
        work_date: r.work_date,

        // ✅ time only (no date)
        in_time: formatTimeOnlyLA(r.in_time),
        out_time: formatTimeOnlyLA(r.out_time),

        gross_time: intervalToHHMMSS(r.gross_time),
        meal_total: intervalToHHMMSS(r.meal_total),
        net_worked_time: intervalToHHMMSS(r.net_worked_time),

        paid10_count: r.paid10_count,
        paid10_overage_unpaid: intervalToHHMMSS(r.paid10_overage_unpaid),
      });
    }

    res.setHeader(
      "Content-Type",
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );
    res.setHeader(
      "Content-Disposition",
      `attachment; filename="timesheet_${start}_to_${end}.xlsx"`
    );

    await wb.xlsx.write(res);
    res.end();
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});


// GET /admin/employees
app.get("/admin/employees", requireAdmin, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT id, employee_code, full_name, is_active, created_at
      FROM employees
      ORDER BY employee_code ASC
    `);

    res.json({ ok: true, employees: result.rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: "Server error" });
  }
});

// POST /admin/employees { employee_code, full_name, pin }
app.post("/admin/employees", requireAdmin, async (req, res) => {
  const { employee_code, full_name, pin } = req.body;

  if (!employee_code || !full_name || !pin) {
    return res.status(400).json({
      ok: false,
      error: "employee_code, full_name, and pin are required",
    });
  }

  try {
    const pin_hash = await bcrypt.hash(String(pin), 10);

    const result = await pool.query(
      `
      INSERT INTO employees (employee_code, full_name, pin_hash, is_active)
      VALUES ($1, $2, $3, true)
      RETURNING id, employee_code, full_name, is_active, created_at
      `,
      [String(employee_code), String(full_name), pin_hash]
    );

    res.json({ ok: true, employee: result.rows[0] });
  } catch (err) {
    console.error(err);

    if (err.code === "23505") {
      return res
        .status(409)
        .json({ ok: false, error: "Employee code already exists" });
    }

    res.status(500).json({ ok: false, error: "Server error" });
  }
});

// PATCH /admin/employees/:id/active  { is_active: boolean }
app.patch("/admin/employees/:id/active", requireAdmin, async (req, res) => {
  const { id } = req.params;
  const { is_active } = req.body;

  if (typeof is_active !== "boolean") {
    return res.status(400).json({ ok: false, error: "is_active must be true/false" });
  }

  try {
    const result = await pool.query(
      `
      UPDATE employees
      SET is_active = $1
      WHERE id = $2
      RETURNING id, employee_code, full_name, is_active, created_at
      `,
      [is_active, id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ ok: false, error: "Employee not found" });
    }

    res.json({ ok: true, employee: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: "Server error" });
  }
});

// POST /admin/employees/:id/reset-pin { pin }
app.post("/admin/employees/:id/reset-pin", requireAdmin, async (req, res) => {
  const { id } = req.params;
  const { pin } = req.body;

  if (!pin) {
    return res.status(400).json({ ok: false, error: "pin is required" });
  }

  try {
    const pin_hash = await bcrypt.hash(String(pin), 10);

    const result = await pool.query(
      `
      UPDATE employees
      SET pin_hash = $1
      WHERE id = $2
      RETURNING id, employee_code, full_name, is_active, created_at
      `,
      [pin_hash, id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ ok: false, error: "Employee not found" });
    }

    res.json({ ok: true, employee: result.rows[0] });
  } catch (err) {
    console.error(err);
    res.status(500).json({ ok: false, error: "Server error" });
  }
});

// GET /admin/employees/:id/open?date=YYYY-MM-DD
app.get("/admin/employees/:id/open", requireAdmin, async (req, res) => {
  const { id } = req.params;
  const { date } = req.query;

  if (!date) {
    return res.status(400).json({
      ok: false,
      error: "date is required (YYYY-MM-DD)",
    });
  }

  try {
    const evRes = await pool.query(
      `
      SELECT id, event_type, event_time
      FROM time_events
      WHERE employee_id = $1
        AND (event_time AT TIME ZONE 'America/Los_Angeles')::date = $2::date
      ORDER BY event_time ASC
      `,
      [id, date]
    );

    let isClockedIn = false;
    let mealActive = false;
    let paid10Active = false;

    let lastIn = null;
    let lastMealStart = null;
    let lastPaid10Start = null;

    for (const ev of evRes.rows) {
      if (ev.event_type === "IN") {
        isClockedIn = true;
        lastIn = ev.event_time;
      }
      if (ev.event_type === "OUT") isClockedIn = false;

      if (ev.event_type === "MEAL_START") {
        mealActive = true;
        lastMealStart = ev.event_time;
      }
      if (ev.event_type === "MEAL_END") mealActive = false;

      if (ev.event_type === "PAID10_START") {
        paid10Active = true;
        lastPaid10Start = ev.event_time;
      }
      if (ev.event_type === "PAID10_END") paid10Active = false;
    }

    return res.json({
      ok: true,
      date,
      open: {
        missing_out: isClockedIn,
        missing_meal_end: mealActive,
        missing_paid10_end: paid10Active,
      },
      last: {
        in_time: lastIn,
        meal_start: lastMealStart,
        paid10_start: lastPaid10Start,
      },
      events: evRes.rows,
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});


// GET /admin/employees/:id/events?start=YYYY-MM-DD&end=YYYY-MM-DD
app.get("/admin/employees/:id/events", requireAdmin, async (req, res) => {
  const { id } = req.params;
  const { start, end } = req.query;

  if (!start || !end) {
    return res.status(400).json({
      ok: false,
      error: "start and end are required (YYYY-MM-DD)",
    });
  }

  try {
    const result = await pool.query(
      `
      SELECT id, event_type, event_time, meta
      FROM time_events
      WHERE employee_id = $1
        AND event_time >= ($2::date)::timestamptz
        AND event_time <  (($3::date + 1)::date)::timestamptz
      ORDER BY event_time ASC
      `,
      [id, start, end]
    );

    return res.json({ ok: true, events: result.rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});

// GET /admin/employees/search?q=mina  (or q=1)
app.get("/admin/employees/search", requireAdmin, async (req, res) => {
  const q = String(req.query.q || "").trim();
  if (!q) return res.json({ ok: true, employees: [] });

  try {
    const result = await pool.query(
      `
      SELECT id, employee_code, full_name, is_active, created_at
      FROM employees
      WHERE employee_code ILIKE $1 OR full_name ILIKE $1
      ORDER BY employee_code ASC
      LIMIT 50
      `,
      [`%${q}%`]
    );

    return res.json({ ok: true, employees: result.rows });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});



// POST /admin/events/add
// Body: { employee_id, event_type, event_time, reason? }
app.post("/admin/events/add", requireAdmin, async (req, res) => {
  const { employee_id, event_type, event_time, reason } = req.body;

  if (!employee_id || !event_type || !event_time) {
    return res.status(400).json({
      ok: false,
      error: "employee_id, event_type, and event_time are required",
    });
  }

  const allowed = new Set([
    "IN",
    "OUT",
    "MEAL_START",
    "MEAL_END",
    "PAID10_START",
    "PAID10_END",
  ]);

  if (!allowed.has(event_type)) {
    return res.status(400).json({ ok: false, error: "Invalid event_type" });
  }

  try {
    // verify employee exists
    const emp = await pool.query(
      `SELECT id, employee_code, full_name FROM employees WHERE id = $1`,
      [employee_id]
    );

    if (emp.rowCount === 0) {
      return res.status(404).json({ ok: false, error: "Employee not found" });
    }

    // =========================================================
    // 🔵 CHECK if punch already exists for that day + type
    // =========================================================
    const existing = await pool.query(
      `
      SELECT id FROM time_events
      WHERE employee_id = $1
        AND event_type = $2
        AND (event_time AT TIME ZONE 'America/Los_Angeles')::date =
            ($3::timestamp AT TIME ZONE 'America/Los_Angeles')::date
      LIMIT 1
      `,
      [employee_id, event_type, event_time]
    );

    // =========================================================
    // 🔵 IF EXISTS → UPDATE IT
    // =========================================================
    if (existing.rowCount > 0) {
      await pool.query(
        `
        UPDATE time_events
        SET event_time = ($1::timestamp AT TIME ZONE 'America/Los_Angeles'),
            meta = jsonb_build_object('admin_fix', true, 'reason', $2::text)
        WHERE id = $3
        `,
        [event_time, reason ?? null, existing.rows[0].id]
      );

      return res.json({
        ok: true,
        message: "Existing punch UPDATED & recalculated ✅",
      });
    }

    // =========================================================
    // 🔵 OTHERWISE INSERT NEW
    // =========================================================
    await pool.query(
      `
      INSERT INTO time_events (employee_id, event_type, event_time, meta)
      VALUES (
        $1,
        $2,
        ($3::timestamp AT TIME ZONE 'America/Los_Angeles'),
        jsonb_build_object('admin_fix', true, 'reason', $4::text)
      )
      `,
      [employee_id, event_type, event_time, reason ?? null]
    );

    return res.json({
      ok: true,
      message: "Missing punch added & recalculated ✅",
    });

  } catch (err) {
    console.error("ADMIN FIX ERROR:", err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});



// POST /admin/events/fix
// SMART behavior:
// - If an event of that type already exists on that date -> UPDATE it
// - If it doesn't exist -> INSERT it
app.post("/admin/events/fix", requireAdmin, async (req, res) => {
  const { employee_id, event_type, event_time, reason } = req.body;

  if (!employee_id || !event_type || !event_time) {
    return res.status(400).json({
      ok: false,
      error: "employee_id, event_type, and event_time are required",
    });
  }

  const allowed = new Set([
    "IN",
    "OUT",
    "MEAL_START",
    "MEAL_END",
    "PAID10_START",
    "PAID10_END",
  ]);
  if (!allowed.has(event_type)) {
    return res.status(400).json({ ok: false, error: "Invalid event_type" });
  }

  try {
    // event_time comes like "YYYY-MM-DDTHH:mm"
    const datePart = String(event_time).slice(0, 10); // YYYY-MM-DD

    // 1) Verify employee exists
    const emp = await pool.query(
      `SELECT id FROM employees WHERE id = $1`,
      [employee_id]
    );
    if (emp.rowCount === 0) {
      return res.status(404).json({ ok: false, error: "Employee not found" });
    }

    // 2) Find an existing event of this type on that date (LA day)
    const existing = await pool.query(
      `
      SELECT id, event_time
      FROM time_events
      WHERE employee_id = $1
        AND event_type = $2
        AND (event_time AT TIME ZONE 'America/Los_Angeles')::date = $3::date
      ORDER BY event_time DESC
      LIMIT 1
      `,
      [employee_id, event_type, datePart]
    );

    // 3) If exists -> UPDATE (smart)
    if (existing.rowCount > 0) {
      const eventId = existing.rows[0].id;

      const updated = await pool.query(
        `
        UPDATE time_events
        SET
          event_time = ($1::timestamp AT TIME ZONE 'America/Los_Angeles'),
          meta = COALESCE(meta, '{}'::jsonb) || jsonb_build_object(
            'admin_fix', true,
            'reason', $2::text,
            'fixed_at', now()
          )
        WHERE id = $3
        RETURNING id, event_type, event_time
        `,
        [event_time, reason || "Admin fix", eventId]
      );

      return res.json({
        ok: true,
        action: "updated",
        event: updated.rows[0],
      });
    }

    // 4) Else -> INSERT (missing punch case)
    const inserted = await pool.query(
      `
      INSERT INTO time_events (employee_id, event_type, event_time, meta)
      VALUES (
        $1,
        $2,
        ($3::timestamp AT TIME ZONE 'America/Los_Angeles'),
        jsonb_build_object('admin_fix', true, 'reason', $4::text, 'fixed_at', now())
      )
      RETURNING id, event_type, event_time
      `,
      [employee_id, event_type, event_time, reason || "Admin fix"]
    );

    return res.json({
      ok: true,
      action: "inserted",
      event: inserted.rows[0],
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});



// ===== Employee login =====
app.post("/auth/login", async (req, res) => {
  const { employee_code, pin } = req.body;

  if (!employee_code || !pin) {
    return res.status(400).json({
      ok: false,
      error: "Employee code and PIN are required",
    });
  }

  try {
    const result = await pool.query(
      `
      SELECT id, employee_code, full_name, pin_hash, is_active
      FROM employees
      WHERE employee_code = $1
      `,
      [employee_code]
    );

    if (result.rowCount === 0) {
      return res.status(401).json({
        ok: false,
        error: "Invalid employee code or PIN",
      });
    }

    const employee = result.rows[0];

    if (!employee.is_active) {
      return res.status(403).json({
        ok: false,
        error: "Employee is inactive",
      });
    }

    const pinMatches = await bcrypt.compare(pin, employee.pin_hash);

    if (!pinMatches) {
      return res.status(401).json({
        ok: false,
        error: "Invalid employee code or PIN",
      });
    }

    return res.json({
      ok: true,
      employee: {
        id: employee.id,
        employee_code: employee.employee_code,
        full_name: employee.full_name,
      },
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});

// GET /totals/today?employee_code=123
app.get("/totals/today", async (req, res) => {
  const { employee_code } = req.query;

  if (!employee_code) {
    return res.status(400).json({ ok: false, error: "employee_code is required" });
  }

  try {
    const totalsResult = await pool.query(todayTotalsSql, [employee_code]);
    return res.json({
      ok: true,
      totals: totalsResult.rows[0] || null,
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});


// GET /status/today?employee_code=123
app.get("/status/today", async (req, res) => {
  const { employee_code } = req.query;

  if (!employee_code) {
    return res.status(400).json({ ok: false, error: "employee_code is required" });
  }

  try {
    const empResult = await pool.query(
      `
      SELECT id, employee_code, full_name, is_active
      FROM employees
      WHERE employee_code = $1
      `,
      [String(employee_code)]
    );

    if (empResult.rowCount === 0) {
      return res.status(404).json({ ok: false, error: "Employee not found" });
    }

    const employee = empResult.rows[0];
    if (!employee.is_active) {
      return res.status(403).json({ ok: false, error: "Employee is inactive" });
    }

    const state = await getTodayState(employee.id);

    // Determine a friendly status label
    let label = "Not clocked in";
    if (state.isClockedIn) label = "Clocked in";
    if (state.mealActive) label = "On meal break";
    if (state.paid10Active) label = "On paid 10-min break";

    // Last event (if any)
    const lastEvent = state.events?.length ? state.events[state.events.length - 1] : null;

    return res.json({
      ok: true,
      status: {
        label,
        isClockedIn: state.isClockedIn,
        mealActive: state.mealActive,
        paid10Active: state.paid10Active,
        lastEvent,
      },
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: "Server error" });
  }
});


// ===== Record punch / break event =====
app.post("/events", async (req, res) => {
  const { employee_code, event_type, kiosk_id } = req.body;

  if (!employee_code || !event_type) {
    return res.status(400).json({
      ok: false,
      error: "employee_code and event_type are required",
    });
  }

  const allowed = new Set([
    "IN",
    "OUT",
    "MEAL_START",
    "MEAL_END",
    "PAID10_START",
    "PAID10_END",
  ]);

  if (!allowed.has(event_type)) {
    return res.status(400).json({
      ok: false,
      error: "Invalid event_type",
    });
  }

  try {
    // 1) Find employee
    const empResult = await pool.query(
      `
      SELECT id, employee_code, full_name, is_active
      FROM employees
      WHERE employee_code = $1
      `,
      [employee_code]
    );

    if (empResult.rowCount === 0) {
      return res.status(404).json({
        ok: false,
        error: "Employee not found",
      });
    }

    const employee = empResult.rows[0];

    if (!employee.is_active) {
      return res.status(403).json({
        ok: false,
        error: "Employee is inactive",
      });
    }

    // 2) Validate event order/state (before insert)
    const state = await getTodayState(employee.id);

    if (event_type === "IN" && state.isClockedIn) {
      return res.status(409).json({
        ok: false,
        error: "Already clocked in. Cannot punch IN again.",
      });
    }

    if (event_type === "OUT") {
      if (!state.isClockedIn) {
        return res.status(409).json({
          ok: false,
          error: "Not clocked in. Cannot punch OUT.",
        });
      }
      if (state.mealActive) {
        return res.status(409).json({
          ok: false,
          error: "Meal break is active. End meal break before punching OUT.",
        });
      }
      if (state.paid10Active) {
        return res.status(409).json({
          ok: false,
          error: "Paid 10-minute break is active. End it before punching OUT.",
        });
      }
    }

    if (event_type === "MEAL_START") {
      if (!state.isClockedIn) {
        return res.status(409).json({
          ok: false,
          error: "Not clocked in. Cannot start meal break.",
        });
      }
      if (state.mealActive) {
        return res.status(409).json({
          ok: false,
          error: "Meal break already active.",
        });
      }
      if (state.paid10Active) {
        return res.status(409).json({
          ok: false,
          error: "Paid 10-minute break is active. End it before starting a meal break.",
        });
      }
    }

    if (event_type === "MEAL_END") {
      if (!state.mealActive) {
        return res.status(409).json({
          ok: false,
          error: "No active meal break to end.",
        });
      }
    }

    if (event_type === "PAID10_START") {
      if (!state.isClockedIn) {
        return res.status(409).json({
          ok: false,
          error: "Not clocked in. Cannot start a paid 10-minute break.",
        });
      }
      if (state.mealActive) {
        return res.status(409).json({
          ok: false,
          error: "Meal break is active. Cannot start a paid 10-minute break during meal.",
        });
      }
      if (state.paid10Active) {
        return res.status(409).json({
          ok: false,
          error: "Paid 10-minute break already active.",
        });
      }
      if (state.paid10CompletedCount >= 2) {
        return res.status(409).json({
          ok: false,
          error: "You already used your 2 paid 10-minute breaks for today.",
        });
      }
    }

    if (event_type === "PAID10_END") {
      if (!state.paid10Active) {
        return res.status(409).json({
          ok: false,
          error: "No active paid 10-minute break to end.",
        });
      }
    }

    // 3) Insert event
    await pool.query(
      `
      INSERT INTO time_events (employee_id, event_type, event_time, kiosk_id)
      VALUES ($1, $2, now(), $3)
      `,
      [employee.id, event_type, kiosk_id || null]
    );

    // 4) Calculate today's totals
    const totalsResult = await pool.query(todayTotalsSql, [employee_code]);

    return res.json({
      ok: true,
      employee: {
        employee_code: employee.employee_code,
        full_name: employee.full_name,
      },
      event: {
        event_type,
        event_time: new Date().toISOString(),
      },
      totals: totalsResult.rows[0] || null,
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({
      ok: false,
      error: "Server error",
    });
  }
});

// ===== Start server (KEEP LAST) =====
const port = process.env.PORT || 3001;
app.listen(port, () => {
  console.log(`API running on http://localhost:${port}`);
});
