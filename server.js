"use strict";
// Digitale Getränkekarte – Server ohne externe Abhängigkeiten (Node.js 18 oder neuer)
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || "127.0.0.1";
const PASSWORD = process.env.ADMIN_PASSWORD || "";
const DATA_FILE = process.env.DATA_FILE || path.join(__dirname, "data", "menu.json");
const INDEX_FILE = path.join(__dirname, "public", "index.html");
const SESSION_MS = 12 * 60 * 60 * 1000;
const TAGS = ["alkoholfrei", "vegan"];
const CSP = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";
const DEFAULT_MENU = { title: "Getränkekarte", cats: ["Cocktails", "Bier", "Wein", "Alkoholfrei", "Heiß"], items: [] };

if (PASSWORD.length < 8) {
  console.error("ADMIN_PASSWORD fehlt oder ist kürzer als 8 Zeichen.");
  process.exit(1);
}

const sessions = new Map();
let failedLogins = [];

function loadMenu() {
  try { return JSON.parse(fs.readFileSync(DATA_FILE, "utf8")); } catch (e) { return DEFAULT_MENU; }
}

function saveMenu(menu) {
  fs.mkdirSync(path.dirname(DATA_FILE), { recursive: true });
  if (fs.existsSync(DATA_FILE)) fs.copyFileSync(DATA_FILE, DATA_FILE + ".bak");
  const tmp = DATA_FILE + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(menu, null, 1));
  fs.renameSync(tmp, DATA_FILE);
}

const str = (v, max) => (typeof v === "string" ? v.trim().slice(0, max) : "");

// Prüft und bereinigt die Daten, die der Browser schickt. Gibt null zurück, wenn sie ungültig sind.
function clean(m) {
  if (!m || typeof m !== "object" || !Array.isArray(m.cats) || !Array.isArray(m.items)) return null;
  if (m.cats.length > 50 || m.items.length > 1000) return null;
  const cats = [];
  for (const c of m.cats) {
    const n = str(c, 60);
    if (!n || cats.includes(n)) return null;
    cats.push(n);
  }
  const items = [];
  const ids = new Set();
  for (const i of m.items) {
    if (!i || typeof i !== "object") return null;
    const name = str(i.name, 120);
    const price = Number(i.price);
    if (!name || !isFinite(price) || price < 0 || price > 9999 || !cats.includes(i.cat)) return null;
    let id = Math.floor(Number(i.id));
    if (!isFinite(id)) id = Date.now();
    while (ids.has(id)) id++;
    ids.add(id);
    items.push({
      id, cat: i.cat, name,
      desc: str(i.desc, 300),
      price: Math.round(price * 100) / 100,
      size: str(i.size, 40),
      tags: (Array.isArray(i.tags) ? i.tags : []).filter((t) => TAGS.includes(t)),
      out: !!i.out
    });
  }
  return { title: str(m.title, 100) || "Getränkekarte", cats, items };
}

function getCookie(req, name) {
  const part = (req.headers.cookie || "").split(";").map((s) => s.trim()).find((s) => s.startsWith(name + "="));
  return part ? part.slice(name.length + 1) : "";
}

function isAdmin(req) {
  const t = getCookie(req, "sid");
  const exp = sessions.get(t);
  if (exp && exp > Date.now()) return true;
  sessions.delete(t);
  return false;
}

function send(res, code, body, type, headers) {
  const raw = Buffer.isBuffer(body) ? body : Buffer.from(typeof body === "string" ? body : JSON.stringify(body));
  res.writeHead(code, Object.assign({
    "Content-Type": type || "application/json; charset=utf-8",
    "Content-Length": raw.length,
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": CSP
  }, headers || {}));
  res.end(raw);
}

function readJson(req, res, next) {
  if (!/^application\/json/.test(req.headers["content-type"] || "")) return send(res, 415, { error: "JSON erwartet" });
  const chunks = [];
  let size = 0;
  req.on("data", (c) => {
    size += c.length;
    if (size > 1e6) { send(res, 413, { error: "Daten zu groß" }); req.destroy(); } else chunks.push(c);
  });
  req.on("end", () => {
    if (res.writableEnded) return;
    let data;
    try { data = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch (e) { return send(res, 400, { error: "Ungültiges JSON" }); }
    next(data);
  });
}

const sha = (s) => crypto.createHash("sha256").update(s).digest();

function login(req, res) {
  readJson(req, res, (b) => {
    const now = Date.now();
    failedLogins = failedLogins.filter((t) => now - t < 60000);
    if (failedLogins.length >= 10) return send(res, 429, { error: "Zu viele Versuche. Bitte eine Minute warten." });
    const ok = b && typeof b.password === "string" && crypto.timingSafeEqual(sha(b.password), sha(PASSWORD));
    if (!ok) {
      failedLogins.push(now);
      return setTimeout(() => send(res, 401, { error: "Falsches Passwort" }), 800);
    }
    const token = crypto.randomBytes(32).toString("hex");
    sessions.set(token, now + SESSION_MS);
    const secure = req.headers["x-forwarded-proto"] === "https" ? "; Secure" : "";
    send(res, 200, { ok: true }, null, {
      "Set-Cookie": "sid=" + token + "; HttpOnly; SameSite=Strict; Path=/; Max-Age=" + SESSION_MS / 1000 + secure
    });
  });
}

http.createServer((req, res) => {
  const url = (req.url || "/").split("?")[0];
  const m = req.method;

  if (m === "GET" && (url === "/" || url === "/index.html")) {
    return fs.readFile(INDEX_FILE, (err, data) =>
      err ? send(res, 500, { error: "public/index.html fehlt" }) : send(res, 200, data, "text/html; charset=utf-8"));
  }
  if (url === "/api/menu" && m === "GET") return send(res, 200, loadMenu());
  if (url === "/api/menu" && m === "PUT") {
    if (!isAdmin(req)) return send(res, 401, { error: "Nicht angemeldet" });
    return readJson(req, res, (b) => {
      const menu = clean(b);
      if (!menu) return send(res, 400, { error: "Ungültige Daten" });
      try { saveMenu(menu); } catch (e) { console.error(e); return send(res, 500, { error: "Speichern fehlgeschlagen" }); }
      send(res, 200, { ok: true });
    });
  }
  if (url === "/api/me" && m === "GET") return send(res, 200, { admin: isAdmin(req) });
  if (url === "/api/login" && m === "POST") return login(req, res);
  if (url === "/api/logout" && m === "POST") {
    sessions.delete(getCookie(req, "sid"));
    return send(res, 200, { ok: true }, null, { "Set-Cookie": "sid=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0" });
  }
  send(res, 404, { error: "Nicht gefunden" });
}).listen(PORT, HOST, () => console.log("Getränkekarte läuft auf http://" + HOST + ":" + PORT));

setInterval(() => {
  const now = Date.now();
  for (const [t, exp] of sessions) if (exp < now) sessions.delete(t);
}, 3600000).unref();
