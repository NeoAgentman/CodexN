let profiles = [];
let selectedId = "";

const $ = (id) => document.getElementById(id);

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      "content-type": "application/json",
      ...(options.headers || {}),
    },
  });
  const value = await response.json();
  if (!response.ok) throw new Error(value.message || `Request failed: ${response.status}`);
  return value;
}

function toast(message) {
  const el = $("toast");
  el.textContent = message;
  el.classList.add("show");
  window.clearTimeout(toast.timer);
  toast.timer = window.setTimeout(() => el.classList.remove("show"), 2600);
}

async function refresh() {
  const value = await api("/api/profiles");
  profiles = value.profiles;
  if (selectedId && !profiles.some((profile) => profile.id === selectedId)) selectedId = "";
  if (!selectedId && profiles.length) selectedId = profiles[0].id;
  render();
}

function selectedProfile() {
  return profiles.find((profile) => profile.id === selectedId) || null;
}

function render() {
  renderList();
  renderProfile();
}

function renderList() {
  const list = $("profileList");
  list.innerHTML = "";
  for (const profile of profiles) {
    const button = document.createElement("button");
    button.className = `profile${profile.id === selectedId ? " active" : ""}`;
    button.type = "button";
    button.innerHTML = `<strong>${escapeHtml(profile.name)}</strong><span>${escapeHtml(profile.id)}</span>`;
    button.onclick = () => {
      selectedId = profile.id;
      render();
    };
    list.appendChild(button);
  }
}

function renderProfile() {
  const profile = selectedProfile();
  const hasProfile = Boolean(profile);
  $("emptyState").classList.toggle("hidden", hasProfile);
  $("profilePanel").classList.toggle("hidden", !hasProfile);
  for (const id of ["desktopButton", "terminalButton", "loginButton", "backupButton", "revealButton", "repairButton", "importCurrentButton"]) $(id).disabled = !hasProfile;
  if (!profile) {
    $("profileTitle").textContent = "选择或创建 profile";
    $("profileSubtitle").textContent = "每个 profile 拥有独立 CODEX_HOME 和 Electron userData。";
    return;
  }
  $("profileTitle").textContent = profile.name;
  $("profileSubtitle").textContent = profile.id;
  $("nameInput").value = profile.name;
  $("codexHome").textContent = profile.codexHome;
  $("electronUserData").textContent = profile.electronUserData;
  $("configPath").textContent = profile.config.path;
  $("currentProvider").textContent = profile.config.modelProvider || "-";
  $("currentModel").textContent = profile.config.model || "-";
  $("providerList").textContent = profile.config.providers.length ? profile.config.providers.join(", ") : "-";
  const health = $("healthList");
  health.innerHTML = "";
  for (const check of profile.doctor.checks) {
    const row = document.createElement("div");
    row.className = "health-row";
    row.innerHTML = `<div><strong data-ok="${check.ok}">${check.ok ? "OK" : "MISS"}</strong> ${escapeHtml(check.label)}</div><span>${escapeHtml(check.detail)}</span>`;
    health.appendChild(row);
  }
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

$("createForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  const data = Object.fromEntries(new FormData(event.currentTarget));
  try {
    const value = await api("/api/profiles", {
      method: "POST",
      body: JSON.stringify({
        id: data.id,
        name: data.name || data.id,
      }),
    });
    selectedId = value.profile.id;
    event.currentTarget.reset();
    await refresh();
    toast("Profile created");
  } catch (error) {
    toast(error.message);
  }
});

$("saveNameButton").onclick = async () => {
  const profile = selectedProfile();
  if (!profile) return;
  try {
    await api(`/api/profiles/${encodeURIComponent(profile.id)}`, {
      method: "PATCH",
      body: JSON.stringify({ name: $("nameInput").value.trim() || profile.id }),
    });
    await refresh();
    toast("Name saved");
  } catch (error) {
    toast(error.message);
  }
};

$("providerForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  const profile = selectedProfile();
  if (!profile) return;
  const data = Object.fromEntries(new FormData(event.currentTarget));
  try {
    await api(`/api/profiles/${encodeURIComponent(profile.id)}/provider`, {
      method: "POST",
      body: JSON.stringify(data),
    });
    await refresh();
    toast("Provider saved");
  } catch (error) {
    toast(error.message);
  }
});

$("desktopButton").onclick = () => runAction("desktop");
$("terminalButton").onclick = () => runAction("terminal");
$("loginButton").onclick = () => runAction("login");
$("backupButton").onclick = () => runAction("backup");
$("revealButton").onclick = () => runAction("reveal");
$("repairButton").onclick = () => runAction("repair", true);
$("importCurrentButton").onclick = async () => {
  if (!window.confirm("Import current ~/.codex into this profile? Existing files may be overwritten.")) return;
  await runAction("import-current", true);
};
$("refreshButton").onclick = () => refresh().catch((error) => toast(error.message));

async function runAction(action, refreshAfter = false) {
  const profile = selectedProfile();
  if (!profile) return;
  try {
    await api(`/api/profiles/${encodeURIComponent(profile.id)}/${action}`, {
      method: "POST",
      body: JSON.stringify({ project: $("projectInput").value.trim() }),
    });
    if (refreshAfter) await refresh();
    toast(`${action} opened`);
  } catch (error) {
    toast(error.message);
  }
}

refresh().catch((error) => toast(error.message));
