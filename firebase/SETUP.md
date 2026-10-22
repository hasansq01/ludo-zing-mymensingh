# Sign-in setup (Google + Facebook) — what you need to do

The game code is ready. Sign-in stays switched off (buttons disabled, "not set up yet") until the steps below are done
and the config is pasted into `index.html`. Everything here runs on Firebase's free Spark plan — do not upgrade the plan.

## 1. Firebase project (free)
1. Go to https://console.firebase.google.com → **Add project** (e.g. `ludo-king-mymensingh`). Google Analytics is optional.
2. **Project settings → General → Your apps → Web (`</>`)** → register an app (no Firebase Hosting needed).
3. Copy the `firebaseConfig` object it shows.
4. In `index.html`, replace `const FIREBASE_CONFIG = null;` with it, for example:
   ```js
   const FIREBASE_CONFIG = { apiKey: 'AIza…', authDomain: 'ludo-king-mymensingh.firebaseapp.com', projectId: 'ludo-king-mymensingh', appId: '1:…:web:…' };
   ```
   These values identify the project and are meant to be public. They are not passwords.

## 2. Authentication
1. **Build → Authentication → Get started**.
2. **Sign-in method → Google → Enable**, pick a support email, **Save**.
3. **Settings → Authorized domains** → add `ludo-king-mymensingh.pages.dev` (`localhost` is already there).

## 3. Facebook
1. https://developers.facebook.com → **My Apps → Create app** → use case **Authenticate and request data from users with Facebook Login**.
2. Copy the **App ID** and **App Secret** (App settings → Basic).
3. In Firebase: **Authentication → Sign-in method → Facebook → Enable** → paste App ID and App Secret → copy the
   **OAuth redirect URI** it shows (`https://<project>.firebaseapp.com/__/auth/handler`) → **Save**.
4. In Facebook: **Facebook Login → Settings → Valid OAuth Redirect URIs** → paste that URI → Save.
5. Facebook **App settings → Basic**: add a **Privacy Policy URL** and app domain `ludo-king-mymensingh.pages.dev`,
   then switch the app to **Live** mode (until then only you and listed testers can sign in).
   The App Secret goes only into the Firebase console — never into the game files.

## 4. Cloud Firestore (stores each player's progress)
1. **Build → Firestore Database → Create database** → production mode → pick a region near your players.
2. **Rules** tab → paste the contents of `firebase/firestore.rules` → **Publish**.

## 5. Optional hardening
- Google Cloud console → **APIs & Services → Credentials** → the Browser API key → **Application restrictions:
  Websites** → add `https://ludo-king-mymensingh.pages.dev/*` and `http://localhost/*`.

## 6. Rebuild and deploy
`powershell -ExecutionPolicy Bypass -File tools\build.ps1`, then upload the zip to Cloudflare Pages as before.

## Notes
- Inside YouTube Playables, sign-in is hidden: Playables don't allow third-party sign-in or outside requests.
  Progress there uses YouTube's own cloud save.
- Players who never sign in never download the Firebase SDK.
- First sign-in on a device copies the guest's progress into the new account. If the account already has progress,
  that progress is restored, and the guest progress is kept on the device and comes back after **Sign out**.
- Popups are used for sign-in. If a browser blocks them, the game falls back to a full-page redirect. Safari and
  other browsers that block third-party storage can break the redirect fallback unless the game is served from the
  same domain as `authDomain` (for example with Firebase Hosting); the popup path is unaffected.
