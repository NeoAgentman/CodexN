import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  backupProfile,
  createProfile,
  importDefaultProfile,
  listProfiles,
} from "../src/profile-store.js";

function tempRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "codexn-test-"));
}

test("creates isolated profile directories without codex config", () => {
  const root = tempRoot();
  const profile = createProfile({ id: "work", name: "Work" }, root);

  assert.equal(profile.id, "work");
  assert.ok(profile.codexHome.startsWith(root));
  assert.ok(profile.electronUserData.startsWith(root));
  assert.equal(fs.existsSync(path.join(profile.codexHome, "config.toml")), false);
  assert.deepEqual(listProfiles(root).map((item) => item.id), ["work"]);
});

test("refuses to initialize over an existing non-empty profile directory", () => {
  const root = tempRoot();
  const staleHome = path.join(root, "work", "codex-home");
  fs.mkdirSync(staleHome, { recursive: true });
  fs.writeFileSync(path.join(staleHome, "config.toml"), "model_provider = \"openai\"\n");

  assert.throws(
    () => createProfile({ id: "work", name: "Work" }, root),
    /Profile directory is not empty/,
  );
});

test("imports default codex home and electron data into a new profile", () => {
  const root = tempRoot();
  const source = tempRoot();
  const codexHome = path.join(source, ".codex");
  const electronUserData = path.join(source, "Library", "Application Support", "Codex");
  fs.mkdirSync(codexHome, { recursive: true });
  fs.mkdirSync(electronUserData, { recursive: true });
  fs.writeFileSync(path.join(codexHome, "config.toml"), "model_provider = \"openai\"\n");
  fs.writeFileSync(path.join(electronUserData, "Preferences"), "{\"account\":\"default\"}\n");

  const profile = importDefaultProfile(
    { id: "default-copy", name: "Default Copy" },
    {
      root,
      defaultCodexHome: codexHome,
      defaultElectronUserData: electronUserData,
    },
  );

  assert.equal(fs.readFileSync(path.join(profile.codexHome, "config.toml"), "utf8"), "model_provider = \"openai\"\n");
  assert.equal(fs.readFileSync(path.join(profile.electronUserData, "Preferences"), "utf8"), "{\"account\":\"default\"}\n");
  assert.deepEqual(listProfiles(root).map((item) => item.id), ["default-copy"]);
});

test("backup creates zip archive", () => {
  const root = tempRoot();
  createProfile({ id: "work", name: "Work" }, root);

  const backup = backupProfile("work", root);
  assert.ok(fs.existsSync(backup));
  assert.equal(path.extname(backup), ".zip");
});
