import os from "node:os";
import path from "node:path";

export function expandHome(value) {
  if (!value) return value;
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

export function defaultRoot() {
  return expandHome(process.env.CODEXN_ROOT || "~/.codex-profiles");
}

export function defaultElectronUserData() {
  return path.join(os.homedir(), "Library", "Application Support", "Codex");
}

export function profileCodexHome(root, id) {
  return path.join(root, id, "codex-home");
}

export function profileElectronUserData(root, id) {
  return path.join(root, id, "electron-user-data");
}

export function profileLogDir(root, id) {
  return path.join(root, id, "logs");
}

export function storePath(root = defaultRoot()) {
  return path.join(root, "profiles.json");
}
