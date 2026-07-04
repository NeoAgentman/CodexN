import fs from "node:fs";
import path from "node:path";

function configPath(profile) {
  return path.join(profile.codexHome, "config.toml");
}

const BUILTIN_PROVIDERS = new Set(["openai", "chatgpt", "ollama", "lmstudio"]);

function readConfig(profile) {
  const file = configPath(profile);
  return fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
}

function writeConfig(profile, text) {
  fs.mkdirSync(profile.codexHome, { recursive: true });
  fs.writeFileSync(configPath(profile), text.endsWith("\n") ? text : `${text}\n`);
}

function tomlString(value) {
  return JSON.stringify(String(value));
}

function rootValue(text, key) {
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed.startsWith("[")) return "";
    const match = trimmed.match(new RegExp(`^${escapeRegExp(key)}\\s*=\\s*(['"])(.*?)\\1`));
    if (match) return match[2];
  }
  return "";
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function readConfigSummary(profile) {
  const text = readConfig(profile);
  const providers = [];
  for (const line of text.split(/\r?\n/)) {
    const match = line.trim().match(/^\[model_providers\.([^\]]+)\]$/);
    if (match) providers.push(match[1]);
  }
  return {
    path: configPath(profile),
    modelProvider: rootValue(text, "model_provider") || profile.defaultProvider || "openai",
    model: rootValue(text, "model"),
    providers,
    builtInOverrides: providers.filter((provider) => BUILTIN_PROVIDERS.has(provider)),
  };
}

export function repairConfig(profile) {
  let text = readConfig(profile);
  for (const provider of BUILTIN_PROVIDERS) {
    text = removeProviderSection(text, provider);
  }
  if (!rootValue(text, "model_provider")) {
    text = `model_provider = "openai"\n${text.trimStart()}`;
  }
  writeConfig(profile, text.replace(/\n{3,}/g, "\n\n"));
  return readConfigSummary(profile);
}

export function writeRootConfigValue(profile, key, value) {
  const text = readConfig(profile);
  const lines = text.split(/\r?\n/);
  let inserted = false;
  let replaced = false;
  const next = [];
  for (const line of lines) {
    if (!inserted && line.trim().startsWith("[")) {
      if (!replaced) next.push(`${key} = ${tomlString(value)}`);
      inserted = true;
    }
    if (!inserted && line.trim().match(new RegExp(`^${escapeRegExp(key)}\\s*=`))) {
      next.push(`${key} = ${tomlString(value)}`);
      replaced = true;
      continue;
    }
    next.push(line);
  }
  if (!inserted && !replaced) next.unshift(`${key} = ${tomlString(value)}`);
  writeConfig(profile, next.join("\n").replace(/\n{3,}/g, "\n\n"));
}

export function setModelProvider(profile, providerId) {
  writeRootConfigValue(profile, "model_provider", providerId);
}

export function upsertProvider(profile, provider) {
  const id = provider.id;
  if (!id || !/^[A-Za-z0-9._-]+$/.test(id)) {
    throw new Error("Provider id must use letters, numbers, dot, underscore, or dash.");
  }
  if (BUILTIN_PROVIDERS.has(id)) {
    throw new Error(`Refusing to override built-in provider: ${id}. Use a custom id like ${id}-custom.`);
  }
  const text = readConfig(profile);
  const lines = text.split(/\r?\n/);
  const header = `[model_providers.${id}]`;
  const start = lines.findIndex((line) => line.trim() === header);
  let end = lines.length;
  if (start !== -1) {
    for (let index = start + 1; index < lines.length; index += 1) {
      if (lines[index].trim().startsWith("[")) {
        end = index;
        break;
      }
    }
  }
  const block = [
    header,
    `name = ${tomlString(provider.name || id)}`,
    `wire_api = ${tomlString(provider.wireApi || "responses")}`,
  ];
  if (provider.baseUrl) block.push(`base_url = ${tomlString(provider.baseUrl)}`);
  if (provider.apiKey) block.push(`env_key = ${tomlString(provider.apiKey.startsWith("sk-") ? "" : provider.apiKey)}`);
  if (provider.apiKey?.startsWith("sk-")) {
    block.push(`experimental_bearer_token = ${tomlString(provider.apiKey)}`);
  }
  if (provider.model) block.push(`model = ${tomlString(provider.model)}`);
  const next = start === -1
    ? `${text.trimEnd()}\n\n${block.join("\n")}\n`
    : [...lines.slice(0, start), ...block, ...lines.slice(end)].join("\n");
  writeConfig(profile, next.replace(/\n{3,}/g, "\n\n"));
}

function removeProviderSection(text, providerId) {
  const lines = text.split(/\r?\n/);
  const header = `[model_providers.${providerId}]`;
  const start = lines.findIndex((line) => line.trim() === header);
  if (start === -1) return text;
  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    if (lines[index].trim().startsWith("[")) {
      end = index;
      break;
    }
  }
  return [...lines.slice(0, start), ...lines.slice(end)].join("\n");
}
