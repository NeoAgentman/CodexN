import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  backupProfile,
  createProfile,
  doctorProfile,
  listProfiles,
} from "../src/profile-store.js";
import {
  readConfigSummary,
  setModelProvider,
  upsertProvider,
} from "../src/config-toml.js";

function tempRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "codexn-test-"));
}

test("creates isolated profile directories and config", () => {
  const root = tempRoot();
  const profile = createProfile({ id: "work", name: "Work" }, root);

  assert.equal(profile.id, "work");
  assert.ok(profile.codexHome.startsWith(root));
  assert.ok(profile.electronUserData.startsWith(root));
  assert.ok(fs.existsSync(path.join(profile.codexHome, "config.toml")));
  assert.doesNotMatch(
    fs.readFileSync(path.join(profile.codexHome, "config.toml"), "utf8"),
    /\[model_providers\.openai\]/,
  );
  assert.deepEqual(listProfiles(root).map((item) => item.id), ["work"]);
});

test("upserts provider and switches model_provider", () => {
  const root = tempRoot();
  const profile = createProfile({ id: "relay", name: "Relay" }, root);

  upsertProvider(profile, {
    id: "custom",
    name: "Custom",
    baseUrl: "https://example.test/v1",
    apiKey: "CUSTOM_KEY",
    model: "gpt-test",
    wireApi: "responses",
  });
  setModelProvider(profile, "custom");

  const summary = readConfigSummary(profile);
  assert.equal(summary.modelProvider, "custom");
  assert.deepEqual(summary.providers.sort(), ["custom"]);
  const text = fs.readFileSync(summary.path, "utf8");
  assert.match(text, /base_url = "https:\/\/example\.test\/v1"/);
  assert.match(text, /env_key = "CUSTOM_KEY"/);
});

test("refuses to override built-in providers", () => {
  const root = tempRoot();
  const profile = createProfile({ id: "work", name: "Work" }, root);

  assert.throws(
    () => upsertProvider(profile, { id: "openai", name: "OpenAI" }),
    /Refusing to override built-in provider/,
  );
});

test("doctor treats missing auth as non-fatal for new profiles", () => {
  const root = tempRoot();
  createProfile({ id: "personal", name: "Personal" }, root);

  const report = doctorProfile("personal", root);
  assert.equal(report.ok, true);
  assert.equal(report.checks.find((check) => check.label === "auth.json").ok, false);
});

test("backup creates zip archive", () => {
  const root = tempRoot();
  createProfile({ id: "work", name: "Work" }, root);

  const backup = backupProfile("work", root);
  assert.ok(fs.existsSync(backup));
  assert.equal(path.extname(backup), ".zip");
});
