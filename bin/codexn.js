#!/usr/bin/env node
import { existsSync } from "node:fs";
import path from "node:path";
import process from "node:process";
import {
  createProfile,
  backupProfile,
  deleteProfile,
  doctorProfile,
  ensureStore,
  getProfile,
  importCurrentCodex,
  listProfiles,
  renameProfile,
  revealProfile,
  updateProfile,
} from "../src/profile-store.js";
import {
  readConfigSummary,
  repairConfig,
  setModelProvider,
  upsertProvider,
  writeRootConfigValue,
} from "../src/config-toml.js";
import {
  openCliInTerminal,
  openCodexDesktop,
  openLoginInTerminal,
  runCodexCli,
} from "../src/macos-launch.js";
import { startServer } from "../src/server.js";

const args = process.argv.slice(2);

function usage() {
  return `codexn - macOS Codex profile launcher

Usage:
  codexn init <id> [--name <name>]
  codexn list [--json]
  codexn doctor <id> [--json]
  codexn desktop <id> [--project <path>] [--app <Codex|/path/Codex.app>]
  codexn cli <id> [-- <codex args...>]
  codexn terminal <id> [--project <path>] [-- <codex args...>]
  codexn login <id>
  codexn backup <id>
  codexn import-current <id>
  codexn reveal <id>
  codexn config <id> get
  codexn repair <id>
  codexn config <id> set <key> <value>
  codexn provider <id> set --id <provider> [--name <name>] [--base-url <url>] [--api-key <key>] [--model <model>] [--wire-api <responses|chat>]
  codexn rename <id> <name>
  codexn remove <id> [--yes]
  codexn gui [--port <port>] [--no-open]

Profile data defaults to ~/.codex-profiles. Override with CODEXN_ROOT.`;
}

function takeFlag(name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  const value = args[index + 1];
  args.splice(index, 2);
  return value;
}

function hasFlag(name) {
  const index = args.indexOf(name);
  if (index === -1) return false;
  args.splice(index, 1);
  return true;
}

function splitPassthrough(values) {
  const index = values.indexOf("--");
  if (index === -1) return [values, []];
  return [values.slice(0, index), values.slice(index + 1)];
}

function requireId(value) {
  if (!value || !/^[A-Za-z0-9._-]+$/.test(value)) {
    throw new Error("Profile id must use letters, numbers, dot, underscore, or dash.");
  }
  return value;
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

async function main() {
  const command = args.shift();
  if (!command || command === "-h" || command === "--help") {
    process.stdout.write(usage());
    process.stdout.write("\n");
    return;
  }

  if (process.platform !== "darwin") {
    throw new Error("codexn currently supports macOS only.");
  }

  ensureStore();

  switch (command) {
    case "init": {
      const id = requireId(args.shift());
      const name = takeFlag("--name") ?? id;
      const profile = createProfile({ id, name });
      printJson({ status: "created", profile });
      return;
    }
    case "list": {
      const json = hasFlag("--json");
      const profiles = listProfiles();
      if (json) {
        printJson({ profiles });
      } else if (profiles.length === 0) {
        process.stdout.write("No profiles yet. Run `codexn init personal`.\n");
      } else {
        for (const profile of profiles) {
          process.stdout.write(`${profile.id}\t${profile.name}\t${profile.codexHome}\n`);
        }
      }
      return;
    }
    case "doctor": {
      const id = requireId(args.shift());
      const json = hasFlag("--json");
      const report = doctorProfile(id);
      if (json) printJson(report);
      else {
        process.stdout.write(`${report.profile.id} (${report.profile.name})\n`);
        for (const check of report.checks) {
          process.stdout.write(`${check.ok ? "OK" : "!!"} ${check.label}: ${check.detail}\n`);
        }
      }
      return;
    }
    case "desktop": {
      const id = requireId(args.shift());
      const project = takeFlag("--project");
      const app = takeFlag("--app");
      const profile = getProfile(id);
      await openCodexDesktop(profile, { project, app });
      process.stdout.write(`Opened Codex Desktop for ${profile.id}.\n`);
      return;
    }
    case "cli": {
      const id = requireId(args.shift());
      const [, passthrough] = splitPassthrough(args);
      const profile = getProfile(id);
      const code = await runCodexCli(profile, passthrough);
      process.exitCode = code;
      return;
    }
    case "terminal": {
      const id = requireId(args.shift());
      const project = takeFlag("--project");
      const [, passthrough] = splitPassthrough(args);
      const profile = getProfile(id);
      await openCliInTerminal(profile, { project, args: passthrough });
      process.stdout.write(`Opened Terminal for ${profile.id}.\n`);
      return;
    }
    case "login": {
      const id = requireId(args.shift());
      const profile = getProfile(id);
      await openLoginInTerminal(profile);
      process.stdout.write(`Opened login Terminal for ${profile.id}.\n`);
      return;
    }
    case "backup": {
      const id = requireId(args.shift());
      printJson({ backupPath: backupProfile(id) });
      return;
    }
    case "import-current": {
      const id = requireId(args.shift());
      const profile = getProfile(id);
      importCurrentCodex(profile);
      printJson({ status: "imported", profile: getProfile(id) });
      return;
    }
    case "reveal": {
      const id = requireId(args.shift());
      printJson({ path: revealProfile(id) });
      return;
    }
    case "config": {
      const id = requireId(args.shift());
      const sub = args.shift();
      const profile = getProfile(id);
      if (sub === "get") {
        printJson(readConfigSummary(profile));
        return;
      }
      if (sub === "set") {
        const key = args.shift();
        const value = args.shift();
        if (!key || value == null) throw new Error("Usage: codexn config <id> set <key> <value>");
        writeRootConfigValue(profile, key, value);
        printJson(readConfigSummary(profile));
        return;
      }
      throw new Error("Usage: codexn config <id> get|set");
    }
    case "repair": {
      const id = requireId(args.shift());
      printJson({ config: repairConfig(getProfile(id)) });
      return;
    }
    case "provider": {
      const id = requireId(args.shift());
      const sub = args.shift();
      if (sub !== "set") throw new Error("Usage: codexn provider <id> set --id <provider>");
      const providerId = takeFlag("--id");
      if (!providerId) throw new Error("--id is required.");
      const profile = getProfile(id);
      upsertProvider(profile, {
        id: providerId,
        name: takeFlag("--name") ?? providerId,
        baseUrl: takeFlag("--base-url"),
        apiKey: takeFlag("--api-key"),
        model: takeFlag("--model"),
        wireApi: takeFlag("--wire-api"),
      });
      setModelProvider(profile, providerId);
      updateProfile(id, { defaultProvider: providerId });
      printJson(readConfigSummary(getProfile(id)));
      return;
    }
    case "rename": {
      const id = requireId(args.shift());
      const name = args.join(" ").trim();
      if (!name) throw new Error("New name is required.");
      printJson({ profile: renameProfile(id, name) });
      return;
    }
    case "remove": {
      const id = requireId(args.shift());
      if (!hasFlag("--yes")) throw new Error("Refusing to remove without --yes.");
      const backupPath = backupProfile(id);
      printJson({ backupPath, removed: deleteProfile(id) });
      return;
    }
    case "gui": {
      const portRaw = takeFlag("--port");
      const port = portRaw ? Number(portRaw) : 14573;
      const noOpen = hasFlag("--no-open");
      const server = await startServer({ port, openBrowser: !noOpen });
      process.stdout.write(`CodexN GUI: http://127.0.0.1:${server.port}\n`);
      return;
    }
    default:
      throw new Error(`Unknown command: ${command}\n\n${usage()}`);
  }
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
