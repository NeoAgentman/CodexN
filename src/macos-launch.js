import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { profileEnv } from "./profile-store.js";

function codexBinary() {
  return process.env.CODEXN_CODEX_BIN || "codex";
}

function spawnPromise(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, options);
    child.on("error", reject);
    child.on("close", (code) => resolve(code ?? 0));
  });
}

export async function runCodexCli(profile, args = []) {
  return spawnPromise(codexBinary(), args, {
    env: profileEnv(profile),
    stdio: "inherit",
  });
}

export async function openCodexDesktop(profile, { project, app } = {}) {
  const appTarget = app || profile.appBundle || "Codex";
  const openArgs = ["-n"];
  if (appTarget.endsWith(".app") || appTarget.startsWith("/")) {
    if (!fs.existsSync(appTarget)) throw new Error(`Codex app not found: ${appTarget}`);
    openArgs.push(appTarget);
  } else {
    openArgs.push("-a", appTarget);
  }
  openArgs.push(
    "--env",
    `CODEX_HOME=${profile.codexHome}`,
    "--env",
    `CODEX_ELECTRON_USER_DATA_PATH=${profile.electronUserData}`,
    "--args",
    `--user-data-dir=${profile.electronUserData}`,
  );
  if (project) openArgs.push(path.resolve(project));
  const code = await spawnPromise("open", openArgs, { stdio: "inherit" });
  if (code !== 0) throw new Error(`open exited with code ${code}`);
}
