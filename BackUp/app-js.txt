// ===============================
// Punch In/Out Kiosk - Option A (Backend-connected)
// One employee at a time (shared kiosk)
// After any action: show message + auto sign out
// Uses backend:
//   POST /auth/login
//   POST /events
//   GET  /totals/today?employee_code=...
// ===============================

console.log("app.js loaded ✅");

const API_BASE = "http://localhost:3001";

// ====== State ======
let currentEmployee = null;

// ====== Grab elements ======
const loginSection = document.getElementById("loginSection");
const appSection = document.getElementById("appSection");

const loginForm = document.getElementById("loginForm");
const employeeIdInput = document.getElementById("employeeId");
const pinInput = document.getElementById("pin");
const loginMsg = document.getElementById("loginMsg");

const signedInAs = document.getElementById("signedInAs");
const signOutBtn = document.getElementById("signOutBtn");

// Kiosk message element
const kioskMsgEl = document.getElementById("kioskMsg");

const currentStatusEl = document.getElementById("currentStatus");
const todayLabelEl = document.getElementById("todayLabel");


// Action buttons
const punchInBtn = document.getElementById("punchInBtn");
const punchOutBtn = document.getElementById("punchOutBtn");
const mealStartBtn = document.getElementById("mealStartBtn");
const mealEndBtn = document.getElementById("mealEndBtn");
const paid10StartBtn = document.getElementById("paid10StartBtn");
const paid10EndBtn = document.getElementById("paid10EndBtn");

// (Optional) Summary UI elements
const totalWorkedEl = document.getElementById("totalWorked");
const totalMealBreaksEl = document.getElementById("totalMealBreaks");
const paid10CountEl = document.getElementById("paid10Count");
const lastActionEl = document.getElementById("lastAction");

// ====== Totals formatting ======
function formatInterval(v) {
  if (!v) return "00:00:00";

  // Most common: postgres returns interval as a string like "01:23:45.123456"
  if (typeof v === "string") return v.split(".")[0];

  // Sometimes drivers/queries return an object for intervals
  if (typeof v === "object") {
    if (typeof v.value === "string") return v.value.split(".")[0];
    if (typeof v.interval === "string") return v.interval.split(".")[0];

    const h = Number(v.hours ?? 0);
    const m = Number(v.minutes ?? 0);
    const s = Number(v.seconds ?? 0);

    const hh = String(h).padStart(2, "0");
    const mm = String(m).padStart(2, "0");
    const ss = String(Math.floor(s)).padStart(2, "0");
    return `${hh}:${mm}:${ss}`;
  }

  return String(v);
}

function updateTotalsUI(totals) {
  if (!totals) return;

  if (totalWorkedEl) totalWorkedEl.textContent = formatInterval(totals.net_worked_time);
  if (totalMealBreaksEl) totalMealBreaksEl.textContent = formatInterval(totals.meal_total);
  if (paid10CountEl) paid10CountEl.textContent = String(totals.paid10_count ?? 0);
}

// ✅ NEW: clear totals so the next employee never sees previous totals
function clearTotalsUI() {
  if (totalWorkedEl) totalWorkedEl.textContent = "00:00:00";
  if (totalMealBreaksEl) totalMealBreaksEl.textContent = "00:00:00";
  if (paid10CountEl) paid10CountEl.textContent = "0";
  if (lastActionEl) lastActionEl.textContent = "-";
}

// ====== Helpers: show/hide screens ======
function showLogin(message = "") {
  currentEmployee = null;

  loginSection.classList.remove("hidden");
  appSection.classList.add("hidden");

  if (loginMsg) loginMsg.textContent = message;
  if (kioskMsgEl) kioskMsgEl.textContent = "";

  // ✅ Clear totals when going back to login
  clearTotalsUI();

  // Clear PIN so next person can't see it
  pinInput.value = "";

  employeeIdInput.focus();
}



function showApp(employee) {
  currentEmployee = employee;

  loginSection.classList.add("hidden");
  appSection.classList.remove("hidden");

  // show employee
  signedInAs.textContent = `${employee.full_name} (Code: ${employee.employee_code})`;

  if (loginMsg) loginMsg.textContent = "";
  if (kioskMsgEl) kioskMsgEl.textContent = "";

  // Optional: reset last action display on login
  if (lastActionEl) lastActionEl.textContent = "-";
}

// ====== Kiosk message + auto sign out ======
const AUTO_SIGNOUT_DELAY_MS = 2000; // 2 seconds

function showKioskMessageAndSignOut(message) {
  if (!currentEmployee) return;

  if (kioskMsgEl) kioskMsgEl.textContent = message;

  setTimeout(() => {
    employeeIdInput.value = "";
    showLogin("");
  }, AUTO_SIGNOUT_DELAY_MS);
}

// ✅ NEW: load totals right after login
async function loadTodayTotalsFor(employee_code) {
  try {
    const resp = await fetch(
      `${API_BASE}/totals/today?employee_code=${encodeURIComponent(employee_code)}`
    );
    const data = await resp.json().catch(() => ({}));

    if (!resp.ok || !data.ok) {
      console.warn("Failed to load totals:", data.error || "Unknown error");
      return;
    }

    updateTotalsUI(data.totals);
  } catch (err) {
    console.error("Error loading totals:", err);
  }
}


// ================= STATUS + TODAY =================
function setTodayLabel() {
  if (!todayLabelEl) return;
  todayLabelEl.textContent = new Date().toLocaleDateString();
}

function setCurrentStatus(text) {
  if (!currentStatusEl) return;
  currentStatusEl.textContent = text || "—";
}

async function loadTodayStatus(employee_code) {
  try {
    const resp = await fetch(
      `${API_BASE}/status/today?employee_code=${encodeURIComponent(employee_code)}`
    );

    const data = await resp.json().catch(() => ({}));

    if (!resp.ok || !data.ok) {
      console.warn("Failed to load status:", data.error || "Unknown error");
      setCurrentStatus("—");
      return;
    }

    setCurrentStatus(data.status?.label || "—");
  } catch (err) {
    console.error("Error loading status:", err);
    setCurrentStatus("—");
  }
}


// ====== Login handler (BACKEND) ======
loginForm.addEventListener("submit", async (e) => {
  e.preventDefault();

  const employee_code = employeeIdInput.value.trim();
  const pin = pinInput.value.trim();

  try {
    const resp = await fetch(`${API_BASE}/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ employee_code, pin }),
    });

    const data = await resp.json().catch(() => ({}));

    if (!resp.ok || !data.ok) {
      showLogin(data.error || "Login failed. Try again.");
      return;
    }

    showApp(data.employee);
    setTodayLabel();              // show today's date
    setCurrentStatus("Loading...");

    await loadTodayTotalsFor(data.employee.employee_code);
    await loadTodayStatus(data.employee.employee_code);

  } catch (err) {
    console.error(err);
    showLogin("Cannot reach backend. Is the server running?");
  }
});

// ====== Sign out button ======
signOutBtn.addEventListener("click", () => {
  showLogin("Signed out. Next employee can sign in.");
});

// ====== Record action via backend (/events) ======
async function recordAction(type) {
  if (!currentEmployee) return { ok: false, error: "Not signed in" };

  try {
    const resp = await fetch(`${API_BASE}/events`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        employee_code: currentEmployee.employee_code,
        event_type: type,
      }),
    });

    const data = await resp.json().catch(() => ({}));

    if (!resp.ok || !data.ok) {
      return { ok: false, error: data.error || "Action blocked" };
    }

    // Update UI totals after event
    updateTotalsUI(data.totals);

    await loadTodayStatus(currentEmployee.employee_code);


    if (lastActionEl) {
      lastActionEl.textContent = `${type} @ ${new Date().toLocaleTimeString()}`;
    }

    return { ok: true, data };
  } catch (err) {
    console.error(err);
    return { ok: false, error: "Cannot reach backend" };
  }
}

// ====== Button actions ======

// Punch In
punchInBtn.addEventListener("click", async () => {
  if (!currentEmployee) return;

  const result = await recordAction("IN");
  if (!result.ok) {
    if (kioskMsgEl) kioskMsgEl.textContent = result.error;
    return;
  }

  showKioskMessageAndSignOut("Get to work");
});

// Punch Out
punchOutBtn.addEventListener("click", async () => {
  if (!currentEmployee) return;

  const result = await recordAction("OUT");
  if (!result.ok) {
    if (kioskMsgEl) kioskMsgEl.textContent = result.error;
    return;
  }

  showKioskMessageAndSignOut("Have a nice day");
});

// Meal Start
mealStartBtn.addEventListener("click", async () => {
  if (!currentEmployee) return;

  const result = await recordAction("MEAL_START");
  if (!result.ok) {
    if (kioskMsgEl) kioskMsgEl.textContent = result.error;
    return;
  }

  showKioskMessageAndSignOut("Enjoy your meal");
});

// Meal End
mealEndBtn.addEventListener("click", async () => {
  if (!currentEmployee) return;

  const result = await recordAction("MEAL_END");
  if (!result.ok) {
    if (kioskMsgEl) kioskMsgEl.textContent = result.error;
    return;
  }

  showKioskMessageAndSignOut("Get to work");
});

// Paid10 Start
paid10StartBtn.addEventListener("click", async () => {
  if (!currentEmployee) return;

  const result = await recordAction("PAID10_START");
  if (!result.ok) {
    if (kioskMsgEl) kioskMsgEl.textContent = result.error;
    return;
  }

  showKioskMessageAndSignOut("Enjoy your break");
});

// Paid10 End
paid10EndBtn.addEventListener("click", async () => {
  if (!currentEmployee) return;

  const result = await recordAction("PAID10_END");
  if (!result.ok) {
    if (kioskMsgEl) kioskMsgEl.textContent = result.error;
    return;
  }

  showKioskMessageAndSignOut("Get to work");
});

// ====== Initial view ======
showLogin("");
