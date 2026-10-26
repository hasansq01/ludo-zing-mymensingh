// Public pages linked from Google Play and the game: the privacy policy (/privacy) and how to have an account deleted
// (/delete-account). Plain HTML, no scripts, no tracking; the text describes what src/ actually stores (see the D1
// migrations) and what the Android build's SDKs (AdMob, Play Billing, Firebase Messaging, Play Games) collect.

const CONTACT = "Hello@oclasp.com";
const UPDATED = "26 October 2026";

function page(title: string, body: string): Response {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} · Ludo Zing</title>
<style>
  :root { --bg: #fff8ef; --fg: #2b2118; --muted: #6b5b4b; --accent: #d9481f; --card: #ffffff; --line: #ecdcc8; }
  @media (prefers-color-scheme: dark) { :root { --bg: #1b1612; --fg: #f3e9dc; --muted: #b9a68f; --accent: #ff7a50; --card: #241d17; --line: #3a2f25; } }
  body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 760px; margin: 0 auto; padding: 32px 16px 64px; }
  h1 { font-size: 1.8rem; margin: 0 0 4px; } h2 { font-size: 1.2rem; margin-top: 2em; }
  .muted { color: var(--muted); } a { color: var(--accent); }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 16px 20px; margin: 16px 0; }
  li { margin: 4px 0; } code { font-size: .95em; }
</style>
</head>
<body><main>${body}</main></body>
</html>`;
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=3600", "X-Content-Type-Options": "nosniff" },
  });
}

export function privacyPage(): Response {
  return page(
    "Privacy policy",
    `<h1>Ludo Zing privacy policy</h1>
<p class="muted">Ludo Zing (also called Ludo Zing Mymensingh) is published by Oclasp. Last updated ${UPDATED}.</p>

<p>This policy explains what the Ludo Zing game collects, why, who it is shared with, and how to have it deleted.
Questions: <a href="mailto:${CONTACT}">${CONTACT}</a>.</p>

<h2>What we collect</h2>
<ul>
  <li><b>Game account.</b> When you first play online the game creates a guest account. We store a random device ID
  the game generates (not your phone's hardware ID), an account ID, your Player ID (LZM-…), the nickname, avatar and
  frame you choose, your coins, gems, free re-rolls, XP, level, game statistics, achievements, items you own, daily
  reward progress, and a record of each coin and gem change (what it was for and when).</li>
  <li><b>Online matches.</b> Room codes, who played, seat colours, results, places and coin-table entries and payouts.
  Emotes you send are passed to the other players in the room; they are not stored.</li>
  <li><b>Google sign-in (optional).</b> If you link Google Play Games, its player ID and display name.</li>
  <li><b>Purchases.</b> For gem packs bought on Google Play: the product, the Google Play order ID and purchase token,
  so we can check the purchase with Google and handle refunds. We never see your card or payment details; Google
  Play handles payment.</li>
  <li><b>Rewarded videos.</b> When you choose to watch a video for a reward, a one-time code and the reward granted.
  The ads themselves are served by Google AdMob (see below).</li>
  <li><b>Notifications.</b> If you allow notifications: your device's Firebase push token, your notification choices
  (game alerts, news and offers) and your time-zone offset, so reminders don't arrive at night.</li>
  <li><b>Abuse prevention.</b> To limit how many guest accounts one network creates, we keep a one-way scrambled form
  (HMAC) of your IP address for at most one day. Our hosting provider (Cloudflare) processes IP addresses to deliver
  the service.</li>
</ul>
<p>We do not collect your contacts, photos, precise location, microphone or camera. The game has no chat: players
communicate only with preset emotes.</p>

<h2>Why we use it</h2>
<ul>
  <li>To run the game: your profile, online matches, leaderboards, rewards, coin tables and purchases.</li>
  <li>To keep it fair and safe: one account per player, checking purchases and rewarded videos with Google,
  stopping cheating and abuse, and banning accounts that break the rules.</li>
  <li>To send notifications you allowed (your turn, a friend joined, reminders, offers).</li>
  <li>To understand how the game's economy is doing, using totals (for example coins created and spent per day).</li>
</ul>
<p>We do not sell your data.</p>

<h2>Third parties</h2>
<ul>
  <li><b>Google AdMob</b> shows rewarded videos only when you tap to watch one. AdMob collects device information
  and the advertising ID to show and measure ads; in the EEA and UK the game asks for consent first, and
  "Privacy choices" in Settings lets you change it. See
  <a href="https://policies.google.com/technologies/partner-sites">how Google uses information from apps</a>.</li>
  <li><b>Google Play</b> (billing, Play Games sign-in) and <b>Firebase Cloud Messaging</b> (notifications), under
  <a href="https://policies.google.com/privacy">Google's privacy policy</a>.</li>
  <li><b>Cloudflare</b> hosts our servers and database.</li>
</ul>

<h2>Leaderboards and other players</h2>
<p>Other players see your nickname, avatar, frame, level and, on leaderboards, your wins or XP.</p>

<h2>How long we keep it</h2>
<p>Your account is kept while you play. Server logs and room records are deleted after 30 days, weekly leaderboard
scores after 26 weeks. If you ask us to delete your account we erase it within 30 days (see below).</p>

<h2>Deleting your account</h2>
<p>See <a href="/delete-account">how to delete your Ludo Zing account</a>. Uninstalling the game removes the data
stored on your phone.</p>

<h2>Children</h2>
<p>Ludo Zing is meant for players aged 13 and over and is not directed to children under 13. If you believe a child
under 13 has given us data, contact us and we will delete it.</p>

<h2>Security</h2>
<p>All traffic between the game and our servers is encrypted (HTTPS / WSS). Access to the admin tools is limited and
logged.</p>

<h2>Changes</h2>
<p>If this policy changes we will update this page and the date above.</p>

<h2>Contact</h2>
<p>Oclasp · <a href="mailto:${CONTACT}">${CONTACT}</a></p>`,
  );
}

export function deleteAccountPage(): Response {
  return page(
    "Delete your account",
    `<h1>Delete your Ludo Zing account</h1>
<p class="muted">Ludo Zing (Ludo Zing Mymensingh) by Oclasp.</p>

<div class="card">
<p><b>How to ask:</b></p>
<ol>
  <li>Open Ludo Zing and tap your profile picture. Your <b>Player ID</b> is shown there (it starts with <code>LZM-</code>).</li>
  <li>Email <a href="mailto:${CONTACT}?subject=Delete%20my%20Ludo%20Zing%20account">${CONTACT}</a> with the subject
  "Delete my Ludo Zing account" and your Player ID.</li>
</ol>
<p>We may ask you to confirm from the game before deleting. We delete the account within 30 days and reply when it's done.</p>
</div>

<h2>What is deleted</h2>
<ul>
  <li>Your account: nickname, avatar, Player ID, coins, gems, free re-rolls, XP, statistics, achievements and items.</li>
  <li>The device IDs linked to it, your notification tokens and choices, leaderboard scores and pending rewards.</li>
  <li>Your Google Play Games link.</li>
  <li>Your nickname in past match records (replaced by "Deleted player").</li>
</ul>

<h2>What is kept</h2>
<ul>
  <li>Records of Google Play purchases (product, order ID, date) for as long as needed for refunds, tax and accounting
  (up to 7 years).</li>
  <li>The coin and gem history and match results, which no longer link to anything that identifies you.</li>
</ul>
<p>Coins, gems and items can't be restored after deletion, and purchases aren't refunded by deleting an account.</p>

<p>Privacy policy: <a href="/privacy">ludo-zing-rooms.flipfold.workers.dev/privacy</a></p>`,
  );
}
