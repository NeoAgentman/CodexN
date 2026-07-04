import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  createProfile,
  backupProfile,
  doctorProfile,
  getProfile,
  importCurrentCodex,
  listProfiles,
  renameProfile,
  revealProfile,
  updateProfile,
} from "./profile-store.js";
import { readConfigSummary, setModelProvider, upsertProvider } from "./config-toml.js";
import { openCliInTerminal, openCodexDesktop, openLoginInTerminal, openUrl } from "./macos-launch.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const publicDir = path.join(__dirname, "..", "public");

export async function startServer({ port = 14573, openBrowser = true } = {}) {
  const server = http.createServer((request, response) => {
    handleRequest(request, response).catch((error) => {
      sendJson(response, 500, { status: "error", message: error.message });
    });
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", resolve);
  });
  const actualPort = server.address().port;
  if (openBrowser) await openUrl(`http://127.0.0.1:${actualPort}`);
  return { server, port: actualPort };
}

async function handleRequest(request, response) {
  const url = new URL(request.url, "http://127.0.0.1");
  if (url.pathname.startsWith("/api/")) {
    await handleApi(request, response, url);
    return;
  }
  serveStatic(response, url.pathname);
}

async function handleApi(request, response, url) {
  const method = request.method || "GET";
  const body = method === "GET" ? {} : await readJsonBody(request);
  if (method === "GET" && url.pathname === "/api/profiles") {
    sendJson(response, 200, { profiles: listProfiles().map(profileView) });
    return;
  }
  if (method === "POST" && url.pathname === "/api/profiles") {
    const profile = createProfile({
      id: body.id,
      name: body.name || body.id,
      fromCurrent: Boolean(body.fromCurrent),
    });
    sendJson(response, 201, { profile: profileView(profile) });
    return;
  }
  const match = url.pathname.match(/^\/api\/profiles\/([^/]+)(?:\/([^/]+))?$/);
  if (!match) {
    sendJson(response, 404, { status: "error", message: "Not found" });
    return;
  }
  const id = decodeURIComponent(match[1]);
  const action = match[2] || "";
  if (method === "GET" && action === "doctor") {
    sendJson(response, 200, doctorView(id));
    return;
  }
  if (method === "GET" && action === "config") {
    sendJson(response, 200, { config: readConfigSummary(getProfile(id)) });
    return;
  }
  if (method === "POST" && action === "backup") {
    sendJson(response, 200, { status: "ok", backupPath: backupProfile(id) });
    return;
  }
  if (method === "POST" && action === "import-current") {
    importCurrentCodex(getProfile(id));
    sendJson(response, 200, { status: "ok", profile: profileView(getProfile(id)) });
    return;
  }
  if (method === "POST" && action === "reveal") {
    sendJson(response, 200, { status: "ok", path: revealProfile(id) });
    return;
  }
  if (method === "PATCH" && !action) {
    const profile = body.name ? renameProfile(id, body.name) : updateProfile(id, body);
    sendJson(response, 200, { profile: profileView(profile) });
    return;
  }
  if (method === "POST" && action === "desktop") {
    await openCodexDesktop(getProfile(id), { project: body.project || undefined });
    sendJson(response, 200, { status: "ok", message: "Desktop opened" });
    return;
  }
  if (method === "POST" && action === "terminal") {
    await openCliInTerminal(getProfile(id), { project: body.project || undefined });
    sendJson(response, 200, { status: "ok", message: "Terminal opened" });
    return;
  }
  if (method === "POST" && action === "login") {
    await openLoginInTerminal(getProfile(id));
    sendJson(response, 200, { status: "ok", message: "Login terminal opened" });
    return;
  }
  if (method === "POST" && action === "provider") {
    const profile = getProfile(id);
    upsertProvider(profile, {
      id: body.providerId,
      name: body.name || body.providerId,
      baseUrl: body.baseUrl,
      apiKey: body.apiKey,
      model: body.model,
      wireApi: body.wireApi,
    });
    setModelProvider(profile, body.providerId);
    updateProfile(id, { defaultProvider: body.providerId });
    sendJson(response, 200, { config: readConfigSummary(getProfile(id)) });
    return;
  }
  sendJson(response, 404, { status: "error", message: "Not found" });
}

function profileView(profile) {
  return {
    ...profile,
    config: readConfigSummary(profile),
    doctor: doctorView(profile.id),
  };
}

function doctorView(id) {
  const report = doctorProfile(id);
  return {
    ok: report.ok,
    checks: report.checks,
  };
}

function serveStatic(response, pathname) {
  const safePath = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  const file = path.resolve(publicDir, safePath);
  if (!file.startsWith(publicDir) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    sendText(response, 404, "Not found", "text/plain; charset=utf-8");
    return;
  }
  const ext = path.extname(file);
  const type = ext === ".js"
    ? "text/javascript; charset=utf-8"
    : ext === ".css"
      ? "text/css; charset=utf-8"
      : "text/html; charset=utf-8";
  sendText(response, 200, fs.readFileSync(file), type);
}

function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    let data = "";
    request.on("data", (chunk) => {
      data += chunk;
      if (data.length > 1_000_000) {
        request.destroy();
        reject(new Error("Request body too large"));
      }
    });
    request.on("end", () => {
      if (!data.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(data));
      } catch {
        reject(new Error("Invalid JSON body"));
      }
    });
    request.on("error", reject);
  });
}

function sendJson(response, status, value) {
  sendText(response, status, `${JSON.stringify(value, null, 2)}\n`, "application/json; charset=utf-8");
}

function sendText(response, status, body, type) {
  response.writeHead(status, {
    "content-type": type,
    "cache-control": "no-store",
  });
  response.end(body);
}
