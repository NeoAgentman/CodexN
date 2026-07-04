import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  defaultRoot,
  expandHome,
  profileCodexHome,
  profileElectronUserData,
  profileLogDir,
  storePath,
} from "./paths.js";
import { readConfigSummary } from "./config-toml.js";

const STORE_VERSION = 1;

export function ensureStore(root = defaultRoot()) {
  fs.mkdirSync(root, { recursive: true });
  const file = storePath(root);
  if (!fs.existsSync(file)) {
    fs.writeFileSync(file, JSON.stringify({ version: STORE_VERSION, profiles: [] }, null, 2));
  }
}

export function loadStore(root = defaultRoot()) {
  ensureStore(root);
  const value = JSON.parse(fs.readFileSync(storePath(root), "utf8"));
  return {
    version: value.version ?? STORE_VERSION,
    profiles: Array.isArray(value.profiles) ? value.profiles : [],
  };
}

export function saveStore(store, root = defaultRoot()) {
  fs.mkdirSync(root, { recursive: true });
  fs.writeFileSync(storePath(root), `${JSON.stringify(store, null, 2)}\n`);
}

export function listProfiles(root = defaultRoot()) {
  return loadStore(root).profiles.slice().sort((a, b) => a.id.localeCompare(b.id));
}

export function getProfile(id, root = defaultRoot()) {
  const profile = loadStore(root).profiles.find((item) => item.id === id);
  if (!profile) throw new Error(`Profile not found: ${id}`);
  return normalizeProfile(profile, root);
}

export function createProfile({ id, name = id, fromCurrent = false }, root = defaultRoot()) {
  const store = loadStore(root);
  if (store.profiles.some((item) => item.id === id)) {
    throw new Error(`Profile already exists: ${id}`);
  }
  const profile = normalizeProfile(
    {
      id,
      name,
      codexHome: profileCodexHome(root, id),
      electronUserData: profileElectronUserData(root, id),
      logDir: profileLogDir(root, id),
      appBundle: "/Applications/Codex.app",
      defaultProvider: "openai",
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
    root,
  );
  materializeProfile(profile, { fromCurrent });
  store.profiles.push(profile);
  saveStore(store, root);
  return profile;
}

export function updateProfile(id, patch, root = defaultRoot()) {
  const store = loadStore(root);
  const index = store.profiles.findIndex((item) => item.id === id);
  if (index === -1) throw new Error(`Profile not found: ${id}`);
  const next = normalizeProfile(
    {
      ...store.profiles[index],
      ...patch,
      updatedAt: new Date().toISOString(),
    },
    root,
  );
  materializeProfile(next, { fromCurrent: false });
  store.profiles[index] = next;
  saveStore(store, root);
  return next;
}

export function renameProfile(id, name, root = defaultRoot()) {
  return updateProfile(id, { name }, root);
}

export function deleteProfile(id, root = defaultRoot()) {
  const store = loadStore(root);
  const index = store.profiles.findIndex((item) => item.id === id);
  if (index === -1) throw new Error(`Profile not found: ${id}`);
  const [profile] = store.profiles.splice(index, 1);
  saveStore(store, root);
  return normalizeProfile(profile, root);
}

export function backupProfile(id, root = defaultRoot()) {
  const profile = getProfile(id, root);
  const profileRoot = path.dirname(profile.codexHome);
  const backupRoot = path.join(root, "backups");
  fs.mkdirSync(backupRoot, { recursive: true });
  const target = path.join(backupRoot, `${id}-${timestamp()}.zip`);
  const result = spawnSync(
    "ditto",
    ["-c", "-k", "--sequesterRsrc", "--keepParent", profileRoot, target],
    { encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error(result.stderr?.trim() || `ditto exited with code ${result.status}`);
  }
  return target;
}

export function revealProfile(id, root = defaultRoot()) {
  const profile = getProfile(id, root);
  const result = spawnSync("open", [path.dirname(profile.codexHome)], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(result.stderr?.trim() || `open exited with code ${result.status}`);
  }
  return path.dirname(profile.codexHome);
}

export function normalizeProfile(profile, root = defaultRoot()) {
  return {
    id: profile.id,
    name: profile.name || profile.id,
    codexHome: expandHome(profile.codexHome || profileCodexHome(root, profile.id)),
    electronUserData: expandHome(
      profile.electronUserData || profileElectronUserData(root, profile.id),
    ),
    logDir: expandHome(profile.logDir || profileLogDir(root, profile.id)),
    appBundle: expandHome(profile.appBundle || "/Applications/Codex.app"),
    defaultProvider: profile.defaultProvider || "openai",
    createdAt: profile.createdAt || new Date().toISOString(),
    updatedAt: profile.updatedAt || new Date().toISOString(),
  };
}

export function materializeProfile(profile, { fromCurrent = false } = {}) {
  fs.mkdirSync(profile.codexHome, { recursive: true });
  fs.mkdirSync(profile.electronUserData, { recursive: true });
  fs.mkdirSync(profile.logDir, { recursive: true });
  const configPath = path.join(profile.codexHome, "config.toml");
  if (fromCurrent && !fs.existsSync(configPath)) {
    const current = path.join(os.homedir(), ".codex", "config.toml");
    if (fs.existsSync(current)) fs.copyFileSync(current, configPath);
  }
  if (!fs.existsSync(configPath)) {
    fs.writeFileSync(configPath, `model_provider = "${profile.defaultProvider}"\n`);
  }
}

export function importCurrentCodex(profile) {
  const current = path.join(os.homedir(), ".codex");
  if (!fs.existsSync(current)) throw new Error("Current ~/.codex does not exist.");
  fs.mkdirSync(profile.codexHome, { recursive: true });
  const result = spawnSync("ditto", [current, profile.codexHome], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(result.stderr?.trim() || `ditto exited with code ${result.status}`);
  }
}

export function profileEnv(profile) {
  return {
    ...process.env,
    CODEX_HOME: profile.codexHome,
    CODEX_ELECTRON_USER_DATA_PATH: profile.electronUserData,
  };
}

export function doctorProfile(id, root = defaultRoot()) {
  const profile = getProfile(id, root);
  const config = readConfigSummary(profile);
  const checks = [
    {
      label: "Codex home",
      ok: fs.existsSync(profile.codexHome),
      detail: profile.codexHome,
    },
    {
      label: "Electron user data",
      ok: fs.existsSync(profile.electronUserData),
      detail: profile.electronUserData,
    },
    {
      label: "config.toml",
      ok: fs.existsSync(path.join(profile.codexHome, "config.toml")),
      detail: path.join(profile.codexHome, "config.toml"),
    },
    {
      label: "auth.json",
      ok: fs.existsSync(path.join(profile.codexHome, "auth.json")),
      detail: path.join(profile.codexHome, "auth.json"),
    },
    {
      label: "Codex.app",
      ok: fs.existsSync(profile.appBundle),
      detail: profile.appBundle,
    },
    {
      label: "Built-in provider overrides",
      ok: config.builtInOverrides.length === 0,
      detail: config.builtInOverrides.length
        ? `Remove sections: ${config.builtInOverrides.join(", ")}`
        : "none",
    },
  ];
  return { profile, checks, ok: checks.every((check) => check.ok || check.label === "auth.json") };
}

function timestamp() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\..+$/, "").replace("T", "-");
}
