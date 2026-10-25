// Ludo Zing admin console: boot, session, shell (sidebar + top bar + maintenance banner) and the hash router.
import { h, clear, tickTimes } from "./dom.js";
import { icon } from "./icons.js";
import { api, request, onApi, newSession } from "./api.js";
import { toast, errMessage, badge } from "./ui.js";
import statusPage from "./pages/status.js";
import playersPage from "./pages/players.js";
import playerPage from "./pages/player.js";
import roomsPage from "./pages/rooms.js";
import roomPage from "./pages/room.js";
import matchesPage from "./pages/matches.js";
import eventsPage from "./pages/events.js";
import configPage from "./pages/config.js";
import auditPage from "./pages/audit.js";
import accountsPage from "./pages/accounts.js";
import accountPage from "./pages/account.js";
import leaderboardsPage from "./pages/leaderboards.js";
import quickPage from "./pages/quick.js";
import notificationsPage from "./pages/notifications.js";
import usagePage from "./pages/usage.js";

const NAV = [
  { id: "status", label: "Status", icon: "status" },
  { id: "accounts", label: "Accounts", icon: "accounts" },
  { id: "players", label: "Players", icon: "players" },
  { id: "rooms", label: "Rooms", icon: "rooms" },
  { id: "matches", label: "Matches", icon: "matches" },
  { id: "quick", label: "Quick match", icon: "quick" },
  { id: "leaderboards", label: "Leaderboards", icon: "crown" },
  { id: "events", label: "Events", icon: "events" },
  { id: "notifications", label: "Notifications", icon: "send" },
  { id: "usage", label: "Usage", icon: "usage" },
  { id: "config", label: "Config", icon: "config" },
  { id: "audit", label: "Audit", icon: "audit" },
];

const ROUTES = [
  { re: /^\/status$/, nav: "status", page: statusPage },
  { re: /^\/accounts$/, nav: "accounts", page: accountsPage },
  { re: /^\/accounts\/([^/]+)$/, nav: "accounts", page: accountPage },
  { re: /^\/leaderboards$/, nav: "leaderboards", page: leaderboardsPage },
  { re: /^\/quick$/, nav: "quick", page: quickPage },
  { re: /^\/notifications$/, nav: "notifications", page: notificationsPage },
  { re: /^\/players$/, nav: "players", page: playersPage },
  { re: /^\/players\/([^/]+)$/, nav: "players", page: playerPage },
  { re: /^\/rooms$/, nav: "rooms", page: roomsPage },
  { re: /^\/rooms\/([^/]+)$/, nav: "rooms", page: roomPage },
  { re: /^\/matches$/, nav: "matches", page: matchesPage },
  { re: /^\/events$/, nav: "events", page: eventsPage },
  { re: /^\/usage$/, nav: "usage", page: usagePage },
  { re: /^\/config$/, nav: "config", page: configPage },
  { re: /^\/audit$/, nav: "audit", page: auditPage },
];

const app = document.getElementById("app");
let shell = null;
let cleanups = [];
let maintenance = false;

// ---------- environment ----------

function envInfo() {
  const host = location.host;
  const hn = location.hostname;
  const local = hn === "localhost" || hn === "127.0.0.1" || hn === "[::1]" || hn.endsWith(".local") || /^10\.|^192\.168\./.test(hn);
  return { host, local, label: local ? "Local" : hn.includes("preview") || hn.includes("staging") ? "Staging" : "Production" };
}

// ---------- theme (auto follows the OS; the choice is remembered per browser) ----------

const THEMES = ["auto", "light", "dark"];
function getTheme() {
  try { const v = localStorage.getItem("lz_admin_theme"); return THEMES.includes(v) ? v : "auto"; } catch { return "auto"; }
}
function applyTheme(v) {
  if (v === "auto") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.setAttribute("data-theme", v);
}
function themeButton() {
  const ICON = { auto: "contrast", light: "sun", dark: "moon" };
  const b = h("button", { type: "button", class: "icon-btn" });
  const paint = (v) => {
    clear(b).appendChild(icon(ICON[v], { size: 17 }));
    b.title = "Theme: " + v + " (click to change)";
    b.setAttribute("aria-label", "Theme: " + v);
  };
  b.addEventListener("click", () => {
    const v = THEMES[(THEMES.indexOf(getTheme()) + 1) % THEMES.length];
    try { localStorage.setItem("lz_admin_theme", v); } catch { /* private mode */ }
    applyTheme(v);
    paint(v);
  });
  paint(getTheme());
  return b;
}
applyTheme(getTheme());

// ---------- login ----------

function renderLogin({ disabled = false, notice = "" } = {}) {
  teardown();
  shell = null;
  document.title = "Sign in · Ludo Zing Admin";
  const env = envInfo();
  const msg = h("div", { class: "login-msg", role: "alert", hidden: true });
  const pw = h("input", {
    type: "password", id: "pw", name: "password", autocomplete: "current-password", required: true, class: "input",
    placeholder: "Admin password", "aria-describedby": "login-help",
  });
  const eye = h("button", { type: "button", class: "icon-btn input-adorn", "aria-label": "Show password", "aria-pressed": "false" }, icon("eye", { size: 16 }));
  eye.addEventListener("click", () => {
    const show = pw.type === "password";
    pw.type = show ? "text" : "password";
    eye.setAttribute("aria-pressed", String(show));
    eye.setAttribute("aria-label", show ? "Hide password" : "Show password");
    clear(eye).appendChild(icon(show ? "eyeoff" : "eye", { size: 16 }));
    pw.focus();
  });
  const submit = h("button", { type: "submit", class: "btn btn-primary btn-block" }, "Sign in");
  const showMsg = (kind, nodes) => {
    msg.className = "login-msg login-msg-" + kind;
    clear(msg).append(icon(kind === "warn" ? "alert" : "error", { size: 16 }), h("div", null, nodes));
    msg.hidden = false;
  };
  const disabledNotice = () => showMsg("warn", [
    h("strong", null, "Admin disabled: "), "set ADMIN_PASSWORD with ",
    h("code", null, "tools/cf.sh secret put ADMIN_PASSWORD"), " (run in ", h("code", null, "server/"),
    "). For local dev put ", h("code", null, "ADMIN_PASSWORD=…"), " in ", h("code", null, "server/.dev.vars"), ".",
  ]);
  const form = h("form", { class: "login-form", novalidate: true },
    h("label", { for: "pw", class: "label" }, "Password"),
    h("div", { class: "input-wrap" }, pw, eye),
    h("p", { id: "login-help", class: "help" }, "The ADMIN_PASSWORD secret of this Worker. Sessions last 12 hours."),
    msg, submit);
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!pw.value) { showMsg("err", "Enter the admin password."); pw.focus(); return; }
    submit.disabled = true;
    submit.classList.add("is-busy");
    msg.hidden = true;
    try {
      await request("POST", "/login", { body: { password: pw.value }, quietAuth: true });
      pw.value = "";
      newSession();
      startShell();
    } catch (err) {
      if (err.status === 401) showMsg("err", "Wrong password.");
      else if (err.status === 429) showMsg("warn", "Too many sign-in attempts from this address. Wait 10 minutes and try again.");
      else if (err.status === 503) disabledNotice();
      else showMsg("err", errMessage(err));
      pw.select();
    } finally {
      submit.disabled = false;
      submit.classList.remove("is-busy");
    }
  });

  clear(app).appendChild(h("div", { class: "login" },
    h("main", { class: "login-card" },
      h("div", { class: "login-brand" },
        h("img", { src: "/admin/favicon.svg", alt: "", width: 52, height: 52 }),
        h("div", null, h("div", { class: "wordmark" }, "Ludo Zing"), h("div", { class: "login-kicker" }, "Admin console"))),
      h("h1", { class: "login-title" }, "Sign in"),
      form),
    h("p", { class: "login-env" }, badge(env.label, env.local ? "ok" : "danger"), h("span", { class: "mono" }, env.host))));
  if (disabled) disabledNotice();
  else if (notice) showMsg("warn", notice);
  pw.focus();
}

// ---------- shell ----------

function buildShell() {
  const env = envInfo();
  const links = NAV.map((n) => h("li", null, h("a", { href: "#/" + n.id, class: "nav-link", dataset: { nav: n.id }, title: n.label },
    icon(n.icon, { size: 18 }), h("span", { class: "nav-label" }, n.label))));
  const logout = h("button", { type: "button", class: "btn btn-ghost btn-sm top-logout" }, icon("logout", { size: 15 }), h("span", { class: "hide-sm" }, "Sign out"));
  logout.addEventListener("click", async () => {
    try { await api.post("/logout"); } catch { /* the cookie is cleared anyway */ }
    location.hash = "#/status";
    renderLogin({ notice: "Signed out." });
  });
  const title = h("h1", { class: "top-title", id: "page-title", tabindex: "-1" }, "");
  const crumbs = h("nav", { class: "crumbs", "aria-label": "Breadcrumb" });
  const banner = h("div", { class: "banner banner-maint", role: "status", hidden: true },
    icon("wrench", { size: 16 }),
    h("span", null, h("strong", null, "Maintenance mode is on."), " New rooms are refused; rooms already open keep playing."),
    h("a", { href: "#/config", class: "banner-link" }, "Config"));
  const main = h("main", { id: "main", class: "main", tabindex: "-1" });
  const el = h("div", { class: "shell" },
    h("a", { href: "#/status", class: "skip", onClick: (e) => { e.preventDefault(); main.focus(); } }, "Skip to content"),
    h("aside", { class: "side", "aria-label": "Sections" },
      h("a", { href: "#/status", class: "brand", "aria-label": "Ludo Zing Admin, status" },
        h("img", { src: "/admin/favicon.svg", alt: "", width: 30, height: 30 }),
        h("span", { class: "brand-text" }, h("span", { class: "wordmark" }, "Ludo Zing"), h("span", { class: "brand-sub" }, "Admin"))),
      h("nav", { class: "nav", "aria-label": "Main" }, h("ul", null, links)),
      h("div", { class: "side-foot" }, h("span", { class: "nav-label" }, "Room server console"))),
    h("div", { class: "col" },
      h("header", { class: "top" },
        h("div", { class: "top-left" }, crumbs, title),
        h("div", { class: "top-right" },
          h("span", { class: "env env-" + (env.local ? "local" : "prod"), title: "Connected to " + env.host },
            h("span", { class: "env-dot", "aria-hidden": "true" }), h("span", { class: "env-label" }, env.label), h("span", { class: "env-host mono" }, env.host)),
          themeButton(),
          logout)),
      banner,
      main));
  return { el, main, title, crumbs, banner, links };
}

function setMaintenance(on) {
  maintenance = Boolean(on);
  if (shell) shell.banner.hidden = !maintenance;
}

async function startShell() {
  shell = buildShell();
  clear(app).appendChild(shell.el);
  setMaintenance(maintenance);
  api.get("/config").then((c) => setMaintenance(c?.maintenance)).catch(() => {});
  if (!location.hash || location.hash === "#" || location.hash === "#/") history.replaceState(null, "", "#/status");
  route();
}

// ---------- router ----------

function teardown() {
  for (const fn of cleanups) { try { fn(); } catch { /* ignore */ } }
  cleanups = [];
}

function parseHash() {
  const raw = location.hash.replace(/^#/, "") || "/status";
  const [path, q = ""] = raw.split("?");
  return { path: path.replace(/\/+$/, "") || "/status", query: new URLSearchParams(q) };
}

function route() {
  if (!shell) return;
  teardown();
  const { path, query } = parseHash();
  let match = null;
  let params = [];
  for (const r of ROUTES) {
    const m = path.match(r.re);
    if (m) { match = r; params = m.slice(1).map((p) => { try { return decodeURIComponent(p); } catch { return p; } }); break; }
  }
  for (const a of shell.links) {
    const on = match && a.firstChild.dataset.nav === match.nav;
    a.firstChild.classList.toggle("is-active", Boolean(on));
    if (on) a.firstChild.setAttribute("aria-current", "page"); else a.firstChild.removeAttribute("aria-current");
  }
  const main = clear(shell.main);
  main.scrollTop = 0;
  window.scrollTo(0, 0);
  if (!match) {
    setTitle("Not found");
    main.appendChild(h("div", { class: "empty" }, h("p", { class: "empty-title" }, "No such page"), h("a", { href: "#/status", class: "btn" }, "Go to Status")));
    return;
  }
  const ctx = {
    query,
    title: setTitle,
    setMaintenance,
    onCleanup: (fn) => cleanups.push(fn),
    /** Rewrite the hash query (filters) without re-rendering the page. */
    setQuery(obj) {
      const u = new URLSearchParams();
      for (const [k, v] of Object.entries(obj)) if (v !== "" && v !== null && v !== undefined && v !== false) u.set(k, v === true ? "1" : String(v));
      const qs = u.toString();
      history.replaceState(null, "", "#" + path + (qs ? "?" + qs : ""));
    },
  };
  try {
    const destroy = match.page(main, params, ctx);
    if (typeof destroy === "function") cleanups.push(destroy);
  } catch (err) {
    console.error(err);
    main.appendChild(h("div", { class: "empty empty-err" }, h("p", { class: "empty-title" }, "This page crashed"), h("p", { class: "empty-hint" }, String(err.message || err))));
  }
  shell.title.focus({ preventScroll: true });
}

function setTitle(text, crumbs = []) {
  if (!shell) return;
  shell.title.textContent = text;
  clear(shell.crumbs);
  crumbs.forEach(([label, href]) => {
    shell.crumbs.append(h("a", { href, class: "crumb" }, label), h("span", { class: "crumb-sep", "aria-hidden": "true" }, "/"));
  });
  shell.crumbs.hidden = !crumbs.length;
  document.title = text + " · Ludo Zing Admin";
}

// ---------- boot ----------

onApi("unauth", () => {
  if (!shell) return;
  toast("Your session expired. Sign in again.", "info");
  renderLogin({ notice: "Session expired. Sign in again." });
});
onApi("disabled", () => { if (shell) renderLogin({ disabled: true }); });

window.addEventListener("hashchange", route);
setInterval(() => tickTimes(document), 15000);

(async function boot() {
  try {
    await request("GET", "/me", { quietAuth: true });
    startShell();
  } catch (err) {
    if (err.status === 503) renderLogin({ disabled: true });
    else if (err.status === 401) renderLogin();
    else renderLogin({ notice: "Could not reach the admin API (" + errMessage(err) + ")." });
  }
})();
