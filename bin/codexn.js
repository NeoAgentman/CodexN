#!/usr/bin/env node
import process from "node:process";
import {
  backupProfile,
  createProfile,
  deleteProfile,
  ensureStore,
  getProfile,
  importDefaultProfile,
  listProfiles,
} from "../src/profile-store.js";
import { openCodexDesktop, runCodexCli } from "../src/macos-launch.js";

const args = process.argv.slice(2);

function usage() {
  return `codexn - macOS Codex profile launcher

Usage:
  codexn init <id> [--name <name>]
  codexn import-default <id> [--name <name>]
  codexn list [--json]
  codexn desktop <id> [--project <path>] [--app <Codex|/path/Codex.app>]
  codexn cli <id> [-- <codex args...>]
  codexn backup <id>
  codexn remove <id> [--yes]

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
    case "import-default": {
      const id = requireId(args.shift());
      const name = takeFlag("--name") ?? id;
      const profile = importDefaultProfile({ id, name });
      printJson({ status: "imported", profile });
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
    case "backup": {
      const id = requireId(args.shift());
      printJson({ backupPath: backupProfile(id) });
      return;
    }
    case "remove": {
      const id = requireId(args.shift());
      if (!hasFlag("--yes")) throw new Error("Refusing to remove without --yes.");
      printJson({ removed: deleteProfile(id) });
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
