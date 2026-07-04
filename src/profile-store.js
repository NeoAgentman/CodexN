import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import {
  defaultRoot,
  expandHome,
  defaultElectronUserData,
  profileCodexHome,
  profileElectronUserData,
  profileLogDir,
  storePath,
} from "./paths.js";

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

export function createProfile({ id, name = id }, root = defaultRoot()) {
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
  assertProfileRootAvailable(profile);
  materializeProfile(profile);
  store.profiles.push(profile);
  saveStore(store, root);
  return profile;
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

export function materializeProfile(profile) {
  fs.mkdirSync(profile.codexHome, { recursive: true });
  fs.mkdirSync(profile.electronUserData, { recursive: true });
  fs.mkdirSync(profile.logDir, { recursive: true });
}

export function importDefaultProfile(
  { id, name = id },
  {
    root = defaultRoot(),
    defaultCodexHome = path.join(os.homedir(), ".codex"),
    defaultElectronUserData: sourceElectronUserData = defaultElectronUserData(),
  } = {},
) {
  const store = loadStore(root);
  if (store.profiles.some((item) => item.id === id)) {
    throw new Error(`Profile already exists: ${id}`);
  }
  if (!fs.existsSync(defaultCodexHome)) {
    throw new Error(`Default Codex home does not exist: ${defaultCodexHome}`);
  }
  if (!fs.existsSync(sourceElectronUserData)) {
    throw new Error(`Default Electron user data does not exist: ${sourceElectronUserData}`);
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
  assertProfileRootAvailable(profile);
  materializeProfile(profile);
  copyDirectory(defaultCodexHome, profile.codexHome);
  copyDirectory(sourceElectronUserData, profile.electronUserData);
  store.profiles.push(profile);
  saveStore(store, root);
  return profile;
}

export function profileEnv(profile) {
  return {
    ...process.env,
    CODEX_HOME: profile.codexHome,
    CODEX_ELECTRON_USER_DATA_PATH: profile.electronUserData,
  };
}

function timestamp() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\..+$/, "").replace("T", "-");
}

function assertProfileRootAvailable(profile) {
  const profileRoot = path.dirname(profile.codexHome);
  if (fs.existsSync(profileRoot) && fs.readdirSync(profileRoot).length > 0) {
    throw new Error(`Profile directory is not empty: ${profileRoot}`);
  }
}

function copyDirectory(source, target) {
  fs.mkdirSync(target, { recursive: true });
  const result = spawnSync("ditto", [source, target], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(result.stderr?.trim() || `ditto exited with code ${result.status}`);
  }
}
