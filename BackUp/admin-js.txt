// admin.js
console.log("admin.js loaded ✅ v20260206_1");

const TOKEN_KEY = "admin_token";

// ===================== Elements =====================
const adminLoginCard = document.getElementById("adminLoginCard");
const adminApp = document.getElementById("adminApp");

const adminLoginForm = document.getElementById("adminLoginForm");
const adminPassword = document.getElementById("adminPassword");
const adminLoginMsg = document.getElementById("adminLoginMsg");

const adminSignOutBtn = document.getElementById("adminSignOutBtn");

const addEmployeeForm = document.getElementById("addEmployeeForm");
const newCode = document.getElementById("newCode");
const newName = document.getElementById("newName");
const newPin = document.getElementById("newPin");
const addEmployeeMsg = document.getElementById("addEmployeeMsg");

const refreshEmployeesBtn = document.getElementById("refreshEmployeesBtn");
const employeesTbody = document.getElementById("employeesTbody");
const employeesMsg = document.getElementById("employeesMsg");

// Export
const exportForm = document.getElementById("exportForm");
const exportStart = document.getElementById("exportStart");
const exportEnd = document.getElementById("exportEnd");
const downloadExcelBtn = document.getElementById("downloadExcelBtn");
const exportMsg = document.getElementById("exportMsg");

// Fix Employee Time
const fixSearch = document.getElementById("fixSearch");
const fixSearchBtn = document.getElementById("fixSearchBtn");
const fixMsg = document.getElementById("fixMsg");

const fixPanel = document.getElementById("fixPanel");
const fixSelected = document.getElementById("fixSelected");
const fixCancelBtn = document.getElementById("fixCancelBtn");
const fixTimeInfo = document.getElementById("fixTimeInfo");


const fixDate = document.getElementById("fixDate");
const checkOpenBtn = document.getElementById("checkOpenBtn");

// Fix buttons
const fixInBtn = document.getElementById("fixInBtn");
const fixOutBtn = document.getElementById("fixOutBtn");
const fixMealStartBtn = document.getElementById("fixMealStartBtn");
const fixMealEndBtn = document.getElementById("fixMealEndBtn");
const fixPaid10StartBtn = document.getElementById("fixPaid10StartBtn");
const fixPaid10EndBtn = document.getElementById("fixPaid10EndBtn");

// Fix action message
const fixActionMsg = document.getElementById("fixActionMsg");

// Modal elements (MUST exist in admin.html)
const fixTimeModal = document.getElementById("fixTimeModal");
const fixTimeTitle = document.getElementById("fixTimeTitle");
const fixTimeInput = document.getElementById("fixTimeInput");
const fixTimeConfirmBtn = document.getElementById("fixTimeConfirmBtn");
const fixTimeCancelBtn = document.getElementById("fixTimeCancelBtn");

// Multiple results container (must exist in HTML for this version)
const fixResultsWrap = document.getElementById("fixResultsWrap");
const fixResultsList = document.getElementById("fixResultsList");

// ===================== State =====================
let selectedEmployee = null;
let lastOpen = null;
let pendingFix = null; // { eventType, defaultTime }

// ===================== Force button types (prevents accidental GET navigation) =====================
[
  adminSignOutBtn,
  refreshEmployeesBtn,
  fixSearchBtn,
  fixCancelBtn,
  checkOpenBtn,
  fixInBtn,
  fixOutBtn,
  fixMealStartBtn,
  fixMealEndBtn,
  fixPaid10StartBtn,
  fixPaid10EndBtn,
  fixTimeConfirmBtn,
  fixTimeCancelBtn,
].forEach((btn) => {
  if (btn && btn.tagName === "BUTTON") btn.type = "button";
});

// ===================== Token helpers =====================
function getToken() {
  return sessionStorage.getItem(TOKEN_KEY);
}
function setToken(token) {
  sessionStorage.setItem(TOKEN_KEY, token);
}
function clearToken() {
  sessionStorage.removeItem(TOKEN_KEY);
}

// ===================== UI helpers =====================
function setMsg(el, text, ok = false) {
  if (!el) return;
  el.textContent = text;
  el.className = ok
    ? "mt-3 text-sm text-emerald-300"
    : "mt-3 text-sm text-rose-300";
}

function showLogin(message = "") {
  if (adminLoginCard) adminLoginCard.classList.remove("hidden");
  if (adminApp) adminApp.classList.add("hidden");
  if (adminLoginMsg) adminLoginMsg.textContent = message;
  stopIdleTimer?.();
}

function showApp() {
  if (adminLoginCard) adminLoginCard.classList.add("hidden");
  if (adminApp) adminApp.classList.remove("hidden");
  if (adminLoginMsg) adminLoginMsg.textContent = "";
  resetIdleTimer?.();
}

function setFixMsg(text, ok = false) {
  setMsg(fixMsg, text, ok);
}
function setFixActionMsg(text, ok = false) {
  setMsg(fixActionMsg, text, ok);
}

// ===================== API helper =====================
async function api(path, { method = "GET", body } = {}) {
  const headers = {};
  const token = getToken();
  if (token) headers["x-admin-token"] = token;
  if (body !== undefined) headers["Content-Type"] = "application/json";

  // IMPORTANT: log what is being sent so we can prove it is POST
  console.log(`[API] ${method} ${path}`, body !== undefined ? body : "");

  const resp = await fetch(path, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });

  const contentType = resp.headers.get("content-type") || "";
  let data;

  try {
    if (contentType.includes("application/json")) {
      data = await resp.json();
    } else {
      const t = await resp.text();
      data = { ok: false, error: t || "(non-json response)" };
    }
  } catch {
    data = { ok: false, error: "(failed to parse response)" };
  }

  return { resp, data };
}

// ===================== Export helpers =====================
function getFilenameFromDisposition(disposition) {
  if (!disposition) return null;
  const match = /filename="([^"]+)"/.exec(disposition);
  return match ? match[1] : null;
}

async function downloadExcel(start, end) {
  const token = getToken();
  if (!token) {
    showLogin("Session expired. Please sign in again.");
    return;
  }

  if (exportMsg) {
    exportMsg.className = "sm:col-span-3 text-sm text-rose-300";
    exportMsg.textContent = "";
  }
  if (downloadExcelBtn) {
    downloadExcelBtn.disabled = true;
    downloadExcelBtn.textContent = "Downloading...";
  }

  try {
    const resp = await fetch(
      `/admin/export.xlsx?start=${encodeURIComponent(start)}&end=${encodeURIComponent(end)}`,
      { method: "GET", headers: { "x-admin-token": token } }
    );

    if (resp.status === 401) {
      clearToken();
      showLogin("Session expired. Please sign in again.");
      return;
    }

    if (!resp.ok) {
      let errText = `Export failed (${resp.status})`;
      try {
        const maybeJson = await resp.json();
        errText = maybeJson.error || errText;
      } catch {}
      if (exportMsg) exportMsg.textContent = errText;
      return;
    }

    const blob = await resp.blob();
    const disposition = resp.headers.get("content-disposition");
    const filename =
      getFilenameFromDisposition(disposition) || `timesheet_${start}_to_${end}.xlsx`;

    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);

    if (exportMsg) {
      exportMsg.className = "sm:col-span-3 text-sm text-emerald-300";
      exportMsg.textContent = "Download started ✅";
    }
  } catch (err) {
    console.error(err);
    if (exportMsg) exportMsg.textContent = "Export failed (network error).";
  } finally {
    if (downloadExcelBtn) {
      downloadExcelBtn.disabled = false;
      downloadExcelBtn.textContent = "Download Excel";
    }
  }
}

// ===================== Auto sign-out after 5 minutes idle =====================
const IDLE_TIMEOUT_MS = 5 * 60 * 1000;
let idleTimer = null;

function startIdleTimer() {
  stopIdleTimer();
  idleTimer = setTimeout(() => {
    if (getToken()) {
      clearToken();
      showLogin("Signed out (idle timeout). Please sign in again.");
    }
  }, IDLE_TIMEOUT_MS);
}
function stopIdleTimer() {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = null;
}
function resetIdleTimer() {
  if (!getToken()) return;
  startIdleTimer();
}
["mousemove", "mousedown", "keydown", "touchstart", "scroll"].forEach((evt) => {
  window.addEventListener(evt, resetIdleTimer, { passive: true });
});

// ===================== Employees table =====================
function makeButton(label) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.textContent = label;
  btn.className =
    "rounded-xl border border-slate-700 bg-slate-950/40 hover:bg-slate-950/70 px-3 py-1 font-medium transition";
  return btn;
}

function renderEmployees(employees) {
  if (!employeesTbody) return;
  employeesTbody.innerHTML = "";

  for (const e of employees) {
    const tr = document.createElement("tr");
    tr.className = "border-b border-slate-900";

    const tdCode = document.createElement("td");
    tdCode.className = "py-2 pr-3";
    tdCode.textContent = e.employee_code;

    const tdName = document.createElement("td");
    tdName.className = "py-2 pr-3";
    tdName.textContent = e.full_name;

    const tdActive = document.createElement("td");
    tdActive.className = "py-2 pr-3";
    tdActive.textContent = e.is_active ? "Yes" : "No";

    const tdActions = document.createElement("td");
    tdActions.className = "py-2 pr-3 flex flex-wrap gap-2";

    const toggleBtn = makeButton(e.is_active ? "Deactivate" : "Activate");
    toggleBtn.addEventListener("click", async () => {
      setMsg(employeesMsg, "");
      const { resp, data } = await api(`/admin/employees/${e.id}/active`, {
        method: "PATCH",
        body: { is_active: !e.is_active },
      });

      if (resp.status === 401) {
        clearToken();
        showLogin("Session expired. Please sign in again.");
        return;
      }
      if (!resp.ok || !data.ok) {
        setMsg(employeesMsg, data.error || `Failed (${resp.status})`);
        return;
      }
      await loadEmployees();
    });

    const resetBtn = makeButton("Reset PIN");
    resetBtn.addEventListener("click", async () => {
      setMsg(employeesMsg, "");
      const pin = prompt(`Enter new PIN for ${e.full_name} (${e.employee_code})`);
      if (!pin) return;

      const { resp, data } = await api(`/admin/employees/${e.id}/reset-pin`, {
        method: "POST",
        body: { pin },
      });

      if (resp.status === 401) {
        clearToken();
        showLogin("Session expired. Please sign in again.");
        return;
      }
      if (!resp.ok || !data.ok) {
        setMsg(employeesMsg, data.error || `Failed (${resp.status})`);
        return;
      }

      setMsg(employeesMsg, "PIN updated ✅", true);
    });

    tdActions.appendChild(toggleBtn);
    tdActions.appendChild(resetBtn);

    tr.appendChild(tdCode);
    tr.appendChild(tdName);
    tr.appendChild(tdActive);
    tr.appendChild(tdActions);

    employeesTbody.appendChild(tr);
  }
}

async function loadEmployees() {
  setMsg(employeesMsg, "");
  const { resp, data } = await api("/admin/employees");

  if (resp.status === 401) {
    clearToken();
    showLogin("Session expired. Please sign in again.");
    return;
  }
  if (!resp.ok || !data.ok) {
    setMsg(employeesMsg, data.error || `Failed (${resp.status})`);
    return;
  }

  renderEmployees(data.employees);
}

// ===================== FIX EMPLOYEE TIME =====================
function hideResultsList() {
  if (!fixResultsWrap || !fixResultsList) return;
  fixResultsWrap.classList.add("hidden");
  fixResultsList.innerHTML = "";
}

function showResultsList(employees) {
  if (!fixResultsWrap || !fixResultsList) return;

  fixResultsList.innerHTML = "";
  for (const e of employees) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className =
      "text-left rounded-xl border border-slate-800 bg-slate-950/30 hover:bg-slate-950/60 px-4 py-3 transition";
    btn.textContent = `${e.employee_code} — ${e.full_name}${e.is_active ? "" : " (inactive)"}`;
    btn.addEventListener("click", () => {
      selectEmployee(e);
      hideResultsList();
      setFixMsg("Employee selected ✅", true);
    });
    fixResultsList.appendChild(btn);
  }
  fixResultsWrap.classList.remove("hidden");
}

function closeFixTimeModal() {
  if (!fixTimeModal) return;
  fixTimeModal.classList.add("hidden");
  pendingFix = null;
}

function resetFixPanel() {
  selectedEmployee = null;
  lastOpen = null;
  pendingFix = null;

  hideResultsList();
  closeFixTimeModal();

  if (fixPanel) fixPanel.classList.add("hidden");
  if (fixSelected) fixSelected.textContent = "—";
  if (fixDate) fixDate.value = "";

  setFixMsg("");
  setFixActionMsg("");
}

function selectEmployee(emp) {
  selectedEmployee = emp;
  lastOpen = null;

  if (fixSelected) fixSelected.textContent = `${emp.employee_code} — ${emp.full_name}`;
  if (fixPanel) fixPanel.classList.remove("hidden");

  if (fixDate && !fixDate.value) {
    const today = new Date();
    const yyyy = today.getFullYear();
    const mm = String(today.getMonth() + 1).padStart(2, "0");
    const dd = String(today.getDate()).padStart(2, "0");
    fixDate.value = `${yyyy}-${mm}-${dd}`;
  }
}

async function runEmployeeSearch() {
  setFixMsg("");
  setFixActionMsg("");
  hideResultsList();
  closeFixTimeModal();

  const q = String(fixSearch?.value || "").trim();
  if (!q) {
    setFixMsg("Type an employee code or name first.");
    return;
  }

  const { resp, data } = await api(`/admin/employees/search?q=${encodeURIComponent(q)}`);

  if (resp.status === 401) {
    clearToken();
    showLogin("Session expired. Please sign in again.");
    return;
  }
  if (!resp.ok || !data.ok) {
    setFixMsg(data.error || `Search failed (${resp.status})`);
    return;
  }

  const list = data.employees || [];
  if (list.length === 0) {
    setFixMsg("No employee found.");
    return;
  }

  if (list.length === 1) {
    selectEmployee(list[0]);
    setFixMsg("Employee found ✅", true);
    return;
  }

  setFixMsg(`Found ${list.length} employees. Click the correct one below:`);
  showResultsList(list);
}

if (fixSearchBtn) fixSearchBtn.addEventListener("click", runEmployeeSearch);
if (fixSearch) {
  fixSearch.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      runEmployeeSearch();
    }
  });
}
if (fixCancelBtn) fixCancelBtn.addEventListener("click", resetFixPanel);

async function checkMissing() {
  setFixMsg("");
  setFixActionMsg("");

  if (!selectedEmployee) {
    setFixMsg("Search and select an employee first.");
    return null;
  }
  const date = fixDate?.value;
  if (!date) {
    setFixMsg("Pick a date first.");
    return null;
  }

  const { resp, data } = await api(
    `/admin/employees/${encodeURIComponent(selectedEmployee.id)}/open?date=${encodeURIComponent(date)}`
  );

  if (resp.status === 401) {
    clearToken();
    showLogin("Session expired. Please sign in again.");
    return null;
  }
  if (!resp.ok || !data.ok) {
    setFixMsg(data.error || `Failed to check missing (${resp.status})`);
    return null;
  }

  lastOpen = data;

  const o = data.open || {};
  const missing = [];
  if (o.missing_out) missing.push("Missing OUT");
  if (o.missing_meal_end) missing.push("Missing MEAL_END");
  if (o.missing_paid10_end) missing.push("Missing PAID10_END");

  if (missing.length === 0) setFixMsg("No missing punches found ✅", true);
  else setFixMsg(`Open items: ${missing.join(", ")}`);

  return data;
}
if (checkOpenBtn) checkOpenBtn.addEventListener("click", checkMissing);

function fmtTimeLocal(isoString) {
  if (!isoString) return "";
  const d = new Date(isoString);
  // shows like 9:15 PM
  return d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}
async function ensureLastOpenLoaded() {
  if (!selectedEmployee || !fixDate?.value) return null;
  if (lastOpen && lastOpen.date === fixDate.value) return lastOpen;
  return await checkMissing(); // this sets lastOpen internally
}


// ===================== FIX TIME MODAL (inline) =====================
async function openFixTimeModal({ title, defaultTime, eventType }) {
  if (!fixTimeModal || !fixTimeTitle || !fixTimeInput) {
    setFixActionMsg("Fix modal elements are missing in admin.html.", false);
    return;
  }
  if (!selectedEmployee) {
    setFixActionMsg("Search and select an employee first.");
    return;
  }
  if (!fixDate?.value) {
    setFixActionMsg("Pick a date first.");
    return;
  }

  // Load latest "last" info so we can show start times
  const data = await ensureLastOpenLoaded();
  const last = data?.last || {};

  // Build info line (only for certain actions)
  let infoText = "";
  if (eventType === "MEAL_END") {
    const t = fmtTimeLocal(last.meal_start);
    infoText = t ? `Meal started at: ${t}` : "Meal start time not found for this date.";
  } else if (eventType === "PAID10_END") {
    const t = fmtTimeLocal(last.paid10_start);
    infoText = t ? `Paid 10 started at: ${t}` : "Paid 10 start time not found for this date.";
  } else if (eventType === "OUT") {
    const t = fmtTimeLocal(last.in_time);
    infoText = t ? `Last IN was at: ${t}` : "";
  }

  pendingFix = { eventType };

  fixTimeTitle.textContent = title;
  fixTimeInput.value = defaultTime || "22:00";
  if (fixTimeInfo) fixTimeInfo.textContent = infoText;

  fixTimeModal.classList.remove("hidden");
  setFixActionMsg("");
}

function closeFixTimeModal() {
  if (!fixTimeModal) return;
  fixTimeModal.classList.add("hidden");
  if (fixTimeInfo) fixTimeInfo.textContent = "";
  pendingFix = null;
}

if (fixTimeCancelBtn) {
  fixTimeCancelBtn.addEventListener("click", (e) => {
    e.preventDefault();
    closeFixTimeModal();
  });
}

if (fixTimeConfirmBtn) {
  fixTimeConfirmBtn.addEventListener("click", async (e) => {
    e.preventDefault();
    e.stopPropagation();

    if (!pendingFix) {
      setFixActionMsg("No fix operation selected.");
      return;
    }

    const timeVal = (fixTimeInput?.value || "").trim();
    if (!timeVal) {
      setFixActionMsg("Please pick a time.");
      return;
    }

    fixTimeConfirmBtn.disabled = true;
    fixTimeConfirmBtn.textContent = "Saving...";

    try {
      const ok = await addFixEvent(pendingFix.eventType, timeVal);
      if (ok) closeFixTimeModal();
    } finally {
      fixTimeConfirmBtn.disabled = false;
      fixTimeConfirmBtn.textContent = "Confirm Fix";
    }
  });
}

// ===================== Add fix event =====================
async function addFixEvent(eventType, timeHHMM) {
  const token = getToken();
  if (!token) {
    showLogin("Session expired. Please sign in again.");
    return false;
  }
  if (!selectedEmployee) {
    setFixActionMsg("No employee selected.");
    return false;
  }

  const date = fixDate?.value;
  if (!date) {
    setFixActionMsg("Pick a date first.");
    return false;
  }

  const event_time = `${date}T${timeHHMM}`;

  const { resp, data } = await api("/admin/events/add", {
    method: "POST",
    body: {
      employee_id: selectedEmployee.id,
      event_type: eventType,
      event_time,
      reason: "Admin fix",
    },
  });

  // If you STILL see "Cannot GET /admin/events/add",
  // that means the browser is NOT running this file, or something navigated.
  const errText = String(data?.error || "");
  if (errText.includes("Cannot GET /admin/events/add")) {
    setFixActionMsg(
      "You are still hitting GET /admin/events/add. This is either (1) cached old admin.js or (2) the server route is not mounted correctly. Do the cache-busting change in admin.html and hard-refresh.",
      false
    );
    return false;
  }

  if (resp.status === 401) {
    clearToken();
    showLogin("Session expired. Please sign in again.");
    return false;
  }

  if (!resp.ok || !data.ok) {
    setFixActionMsg(data.error || `Fix failed (${resp.status})`);
    return false;
  }

  setFixActionMsg(`Saved ✅ (${eventType} @ ${timeHHMM})`, true);
  await checkMissing();
  return true;
}

// ===================== Wire fix buttons =====================
function wireFixButton(btn, eventType, defaultTime, label) {
  if (!btn) return;

  btn.addEventListener("click", async (e) => {
    e.preventDefault();
    setFixActionMsg("");

    if (!selectedEmployee) {
      setFixActionMsg("Search and select an employee first.");
      return;
    }
    if (!fixDate?.value) {
      setFixActionMsg("Pick a date first.");
      return;
    }

    // ✅ Make sure we have latest open/last info for this date
    const data = await ensureLastOpenLoaded();
    const last = data?.last || {};

    let infoText = "";

    if (eventType === "MEAL_END") {
      const t = fmtTimeLocal(last.meal_start);
      infoText = t ? `Meal started at: ${t}` : "Meal start time not found for this date.";
    }

    if (eventType === "PAID10_END") {
      const t = fmtTimeLocal(last.paid10_start);
      infoText = t ? `Paid 10 started at: ${t}` : "Paid 10 start time not found for this date.";
    }

    if (eventType === "OUT") {
      const t = fmtTimeLocal(last.in_time);
      infoText = t ? `Last IN was at: ${t}` : "";
    }

    openFixTimeModal({
      title: label,
      defaultTime,
      eventType,
      infoText,
    });
  });
}


wireFixButton(fixInBtn, "IN", "08:00", "Fix Punch IN");
wireFixButton(fixOutBtn, "OUT", "22:00", "Fix Punch OUT");
wireFixButton(fixMealStartBtn, "MEAL_START", "12:00", "Fix Meal START");
wireFixButton(fixMealEndBtn, "MEAL_END", "12:30", "Fix Meal END");
wireFixButton(fixPaid10StartBtn, "PAID10_START", "10:00", "Fix Paid10 START");
wireFixButton(fixPaid10EndBtn, "PAID10_END", "10:10", "Fix Paid10 END");

// ===================== Admin login =====================
if (adminLoginForm) {
  adminLoginForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    setMsg(adminLoginMsg, "");

    const password = adminPassword?.value || "";

    const { resp, data } = await api("/admin/login", {
      method: "POST",
      body: { password },
    });

    if (!resp.ok || !data.ok) {
      showLogin(data.error || `Login failed (${resp.status})`);
      return;
    }

    setToken(data.token);
    if (adminPassword) adminPassword.value = "";
    showApp();
    resetFixPanel();
    await loadEmployees();
  });
}

if (adminSignOutBtn) {
  adminSignOutBtn.addEventListener("click", (e) => {
    e.preventDefault();
    clearToken();
    showLogin("Signed out.");
    resetFixPanel();
  });
}

// Add employee
if (addEmployeeForm) {
  addEmployeeForm.addEventListener("submit", async (e) => {
    e.preventDefault();

    if (addEmployeeMsg) {
      addEmployeeMsg.className = "sm:col-span-3 text-sm text-rose-300";
      addEmployeeMsg.textContent = "";
    }

    const employee_code = newCode?.value.trim();
    const full_name = newName?.value.trim();
    const pin = newPin?.value.trim();

    const { resp, data } = await api("/admin/employees", {
      method: "POST",
      body: { employee_code, full_name, pin },
    });

    if (resp.status === 401) {
      clearToken();
      showLogin("Session expired. Please sign in again.");
      return;
    }
    if (!resp.ok || !data.ok) {
      if (addEmployeeMsg) addEmployeeMsg.textContent = data.error || `Failed (${resp.status})`;
      return;
    }

    if (addEmployeeMsg) {
      addEmployeeMsg.className = "sm:col-span-3 text-sm text-emerald-300";
      addEmployeeMsg.textContent = "Employee created ✅";
    }

    if (newCode) newCode.value = "";
    if (newName) newName.value = "";
    if (newPin) newPin.value = "";

    await loadEmployees();
  });
}

if (refreshEmployeesBtn) refreshEmployeesBtn.addEventListener("click", loadEmployees);

// Export
if (exportForm) {
  exportForm.addEventListener("submit", async (e) => {
    e.preventDefault();

    if (exportMsg) {
      exportMsg.className = "sm:col-span-3 text-sm text-rose-300";
      exportMsg.textContent = "";
    }

    const start = exportStart?.value;
    const end = exportEnd?.value;

    if (!start || !end) {
      if (exportMsg) exportMsg.textContent = "Please pick start and end dates.";
      return;
    }
    if (start > end) {
      if (exportMsg) exportMsg.textContent = "Start date must be before (or same as) end date.";
      return;
    }

    await downloadExcel(start, end);
  });
}

// ===================== Initial =====================
if (getToken()) {
  showApp();
  loadEmployees();
} else {
  showLogin("");
}
