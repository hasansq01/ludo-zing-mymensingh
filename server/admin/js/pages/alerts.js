// Alerts: what the 15-minute check warned about (a Cloudflare free-plan limit near, a server problem, the morning
// summary), newest first, each also pushed to the alert accounts' phones (ADMIN_API.md "Alerts"). The status card says
// when the check last ran, what it saw and who gets the pushes; Check now / Send test / Mark all read.
import { h, replace, timeEl, absTime, relTime } from "../dom.js";
import { api } from "../api.js";
import { dataTable } from "../table.js";
import { badge, card, kv, toast, toastErr, accountLink } from "../ui.js";
import { icon } from "../icons.js";
import { pageHead } from "./common.js";

const LEVEL = { danger: ["Danger", "danger", "alert"], warning: ["Warning", "warn", "alert"], info: ["Info", "info", "info"] };
const KIND = { usage: "Free limit", pace: "Pace", server: "Server", summary: "Summary", test: "Test" };

function levelBadge(l) {
  const [t, tone, ic] = LEVEL[l] || [l, "neutral", null];
  return badge(t, tone, ic);
}

function delivered(r) {
  if (!r.sent && !r.failed) return h("span", { class: "muted" }, "not pushed");
  return h("span", null, r.sent + (r.sent === 1 ? " device" : " devices"), r.failed ? h("span", { class: "muted" }, ` · ${r.failed} failed`) : null);
}

export default function alertsPage(root, _params, ctx) {
  ctx.title("Alerts");
  const statusBox = h("div");
  const checkBtn = h("button", { type: "button", class: "btn btn-sm" }, icon("refresh", { size: 14 }), "Check now");
  const testBtn = h("button", { type: "button", class: "btn btn-sm" }, icon("send", { size: 14 }), "Send test push");
  const readBtn = h("button", { type: "button", class: "btn btn-sm btn-primary" }, icon("check", { size: 14 }), "Mark all read");

  const table = dataTable({
    caption: "Alerts",
    load: async (p) => {
      const d = await api.get("/alerts", p);
      renderStatus(d.status);
      return d;
    },
    empty: ["No alerts yet", "Nothing has come close to a limit. The morning summary shows up here from 09:00 Bangladesh time."],
    columns: [
      { label: "Time", render: (r) => timeEl(r.at) },
      { label: "Level", render: (r) => levelBadge(r.level) },
      { label: "Alert", cls: "col-main", render: (r) => h("div", { class: "alert-cell" + (r.read_at ? "" : " is-unread") },
        h("div", { class: "alert-title" }, r.title), h("div", { class: "alert-body" }, r.body)) },
      { label: "Type", render: (r) => h("span", { class: "muted" }, KIND[r.kind] || r.kind) },
      { label: "Pushed to", render: delivered },
    ],
  });

  root.append(
    pageHead(null, "Pushed to your phone before the server runs into a Cloudflare free-plan limit, when the server has trouble, and every morning with yesterday's numbers. Checked every 15 minutes.", [checkBtn, testBtn, readBtn]),
    statusBox,
    h("section", { class: "card card-flush" }, table.el),
  );
  table.setParams({});

  function renderStatus(s) {
    if (!s) return;
    ctx.setAlerts?.(s);
    const last = s.last_check;
    const accs = s.accounts || [];
    const warns = [];
    if (!s.push_configured) warns.push("Push is off on the server (FCM_SERVICE_ACCOUNT): alerts are only listed here.");
    if (!accs.length) warns.push("No alert accounts (ALERT_ACCOUNTS in wrangler.jsonc): alerts are only listed here.");
    for (const a of accs) {
      if (a.missing) warns.push(`Alert account ${a.id} does not exist.`);
      else if (!a.devices) warns.push(`${a.name || a.id} has no phone with notifications on: open Ludo Zing on the phone and allow notifications.`);
    }
    if (last && last.usage !== "ok") warns.push(`The last check could not read Cloudflare's usage: ${last.usage}`);
    const overdue = last && Date.now() - last.at > 40 * 60_000;
    if (overdue) warns.push(`The check has not run since ${absTime(last.at)}: is the Worker over its daily limit, or the cron off?`);

    const rows = [
      ["Last check", last ? h("span", null, h("time", { datetime: new Date(last.at).toISOString() }, relTime(last.at)), h("span", { class: "muted" }, " · every " + s.every_min + " min")) : h("span", { class: "muted" }, "not yet (within 15 minutes of the deploy)")],
      ["Highest limit today", last?.top ? `${last.top.percent}% (${last.top.id.replace(/_/g, " ")})` : "–"],
      ["Warns at", s.steps.map((x) => x + "%").join(" · ") + " of each free allowance, and early when today's pace runs out before the reset"],
      ["Pushes go to", accs.length ? h("span", null, accs.map((a, i) => h("span", null, i ? ", " : "", a.missing ? h("span", { class: "mono" }, a.id) : accountLink(a.id), a.missing ? "" : ` (${a.name || "no name"}, ${a.devices} ${a.devices === 1 ? "device" : "devices"})`))) : h("span", { class: "muted" }, "nobody")],
    ];
    replace(statusBox, card("Status", h("div", null,
      kv(rows),
      warns.map((w) => h("div", { class: "callout callout-warn", role: "status" }, icon("alert", { size: 16 }), h("div", null, w))))));
  }

  async function busy(btn, fn) {
    btn.disabled = true;
    btn.classList.add("is-busy");
    try { await fn(); } catch (err) { toastErr(err, btn.textContent); } finally {
      btn.disabled = false;
      btn.classList.remove("is-busy");
    }
  }

  checkBtn.addEventListener("click", () => busy(checkBtn, async () => {
    const r = await api.post("/alerts/check");
    toast(r.raised.length ? `${r.raised.length} new alert${r.raised.length === 1 ? "" : "s"}` : "Checked: nothing new", r.raised.length ? "info" : "ok");
    table.setParams({});
  }));
  testBtn.addEventListener("click", () => busy(testBtn, async () => {
    const r = await api.post("/alerts/test");
    toast(r.sent ? `Test push sent to ${r.sent} ${r.sent === 1 ? "device" : "devices"}` : "Nothing sent: no phone to push to (see Status)", r.sent ? "ok" : "error");
    table.setParams({});
  }));
  readBtn.addEventListener("click", () => busy(readBtn, async () => {
    await api.post("/alerts/read");
    table.setParams({});
  }));
}
