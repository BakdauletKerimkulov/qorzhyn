# External Services — Qorzhyn-Specific Decisions

Non-obvious choices around external services, regions, and environment configuration. Universal Firebase patterns (emulators, auth, rules) are in `ai_toolkit/guidelines/firebase.md`.

---

## Maps: Stadia Maps, not Google Maps

**Decision:** Use [Stadia Maps](https://stadiamaps.com/) via `flutter_map`, not `google_maps_flutter`.

**Why:** Stadia Maps offers a generous free tier sufficient for early-stage usage in Kazakhstan. Google Maps charges per map load and geocoding request, which adds up quickly during development and beta testing. `flutter_map` also avoids platform-specific native map SDKs, simplifying web support.

**How it works:**
- Tile layer: `https://tiles.stadiamaps.com/tiles/alidade_smooth/{z}/{x}/{y}{r}.png`
- Geocoding: `https://api.stadiamaps.com/geocoding/v1/search`
- Static map previews: same tile URL pattern (used in `static_map_preview.dart`)
- API key passed via `Env.stadiaMapsApiKey` in `additionalOptions`

> **AI warning:** Do not suggest migrating to Google Maps or adding `google_maps_flutter`. The billing model is the reason for Stadia Maps.

---

## Payments: none — offline at pickup

**Decision:** The app processes no payments. `reserveOffer` reserves the item and creates the order; the customer pays at the store's own terminal on pickup. There is no payment provider integration of any kind, client-side or server-side.

**Why:** Online payment was removed as unfinished and risky (`ai_specs/archive/012-refactor-booking-flow-spec.md`). Reserve-only is the single supported booking path.

**Consequences:**
- No Cloud Function secrets exist at all — nothing in this project calls `defineSecret`
- `orders` carries no payment status field; `payments/{id}` remains an empty, write-denied collection reserved for a future integration
- Reintroducing online payment is a separate spec, not an incremental change

> **AI warning:** Do not add a payment SDK, a payments dependency, or a `payments`-related Cloud Function without an explicit new spec. Which provider suits Kazakhstan (Kaspi Pay, Halyk, other) is an open question with no decision recorded anywhere yet.

---

## Firebase API Keys: Public by Design

**Decision:** Firebase API keys in `firebase_options_client.dart` and `firebase_options_business.dart` (`AIza...`) are committed to the repo and shipped in every app binary. This is normal and intended. (There is one generated file per flavor; the shared `firebase_options.dart` was removed by spec 050.)

**Why:** A Firebase API key is a project identifier, not an access credential. It grants no data access — data protection comes from Firestore/Storage security rules. The key is trivially extractable from any APK/IPA, so "hiding" it in `.env` or rewriting git history provides zero security and breaks `flutterfire configure` regeneration.

**Actual protection layers:**
1. Key restrictions in Google Cloud Console → Credentials: application restrictions (iOS bundle ID / Android package + SHA-1 / web referrers) + API restrictions (Firebase APIs only)
2. App Check — verifies requests come from the real app
3. Security rules (`firestore.rules`, `storage.rules`) — the only real data protection

GitHub secret-scanning alerts on these keys are pattern-based false positives: restrict the key, then close the alert as "used in client app".

> **AI warning:** Do NOT suggest moving Firebase API keys to `.env`/envied, rotating them on a leak alert, or scrubbing them from git history. They are public by design. Should a real server-side secret ever appear, it belongs in Firebase Secret Manager via `defineSecret` — never in `process.env`, never in envied.

---

## Firebase Cloud Functions: Region Split

**Decision:** There is no `setGlobalOptions({ region: ... })`. Functions use two different regions.

| Function type | Region | How set |
|---------------|--------|---------|
| Firestore triggers (`onOrderCreated`, `onOrderStatusChanged`, `onItemStatusChanged`) | `asia-south1` | Explicitly per-function in trigger options |
| Callable/HTTPS functions (`reserveOffer`, `cancelOrder`, `updateOrderStatus`, etc.) | `us-central1` | Default (no region specified) |
| Scheduled functions (`dailySyncOffers`, `expireOrders`) | `us-central1` | Default (no region specified) |

**Why `asia-south1` for triggers:** Firestore triggers should be in the same region as the Firestore database for lower latency on document change events.

**Firestore location — question resolved (2026-08-04):** `firebase.json` lists `"location": "nam5"`, but that field is a provisioning hint, not state. `gcloud firestore databases describe --database='(default)'` returns **`asia-south1`**. So triggers are correctly co-located with the database; callables and the default Storage bucket (`US-CENTRAL1`) are the ones split away from it.

**This whole layout is being replaced.** Measured `time_total` from Kazakhstan: `europe-west1` 0.433s, `europe-central2` 0.451s, `us-central1` 0.582s, `asia-south1` **1.193s** — the database currently sits in the slowest measured region for its users. Migration of Firestore, Storage and all functions to a single `europe-west1` project is planned in `ai_specs/047-migrate-firebase-region-europe-west1-plan.md`, with the name-independent preparation split out into `ai_specs/archive/046-prepare-region-migration-plan.md`. Update this section when that lands.

**Why no `setGlobalOptions`:** Callable functions are already deployed at `us-central1` and clients call them at the default region (no `instanceFor(region:)` on the Flutter side). Adding `setGlobalOptions` would move callables to a different region and break existing client URLs.

> **AI warning:** Do NOT add `setGlobalOptions({ region: 'asia-south1' })` or suggest a global region. It would break all callable function invocations from the Flutter client.

---

## Firebase Hosting: Business App Only (by Convention)

**Decision:** Single hosting config in `firebase.json` pointing to `build/web`.

```json
"hosting": {
  "public": "build/web",
  "rewrites": [{ "source": "**", "destination": "/index.html" }]
}
```

**Why:** There is no multi-site setup, no `"target"` field. The config does not select an app at all — it deploys whatever was last built into `build/web` (and web has no flavors to choose between; the entry point does the choosing). Only the business console is built for web, and the target must be named explicitly: `flutter build web -t lib/main_business.dart`. There is no default target to fall back on, so a web build that omits `-t` fails rather than deploying the wrong app. Both hosting workflows (`firebase-hosting-merge.yml`, `firebase-hosting-pull-request.yml`) run `flutter build web -t lib/main_business.dart`. The client app is mobile-only for now — not even run in Chrome locally: `lib/firebase_options_client.dart` has no web options (spec 050, [L4]).

> **AI warning:** If adding a second hosting site (e.g., client web app), you need Firebase multi-site hosting with named targets — the current single-block config won't work for two apps.

---

## FCM Push Notifications: Token in Firestore

**Decision:** FCM device token stored as a field on the user document, not in a subcollection.

**How it works:**
- Token stored at `users/{uid}`, one field per app: `fcmTokenClient` (client app) / `fcmTokenBusiness` (business app), via `set(merge: true)` — split because a partner can be signed in to both apps on one device, and a single shared `fcmToken` field would let the last app to register overwrite the other's token (spec 034, E10)
- Legacy field `fcmToken` is still written alongside the new field on every save, and read as a fallback wherever a token is resolved (`getCustomerToken`, `getStoreTeamTokens` in `functions/src/features/notifications/helpers/recipients.ts`) — keeps pre-split app builds receiving notifications. Remove the legacy write/fallback once both apps have rolled out past the split (no fixed date set)
- Refreshed automatically via `onTokenRefresh` listener
- iOS: requests APNs token before FCM token (required)
- Message listeners (`onMessage`, `onMessageOpenedApp`, `getInitialMessage`) are registered once per app session in `PushNotificationBootstrap` (`application/push_notification_bootstrap.dart`, `keepAlive`) — not inside `initialize()`, which re-runs on every `authStateChanges` emission. A tapped/opened message maps to a deep link via `mapPushToDeepLink` and is applied once the router is ready (`DeepLinkApplier`, up to a 30s retry window)
- Background handler registered via `FirebaseMessaging.onBackgroundMessage`

**Why merge-set on user doc:** Simpler than a subcollection for single-device-per-user. If multi-device support is needed later, this should move to `users/{uid}/devices/{tokenId}`.

---

## Environment Variables: envied with Obfuscation

**Decision:** Client-side secrets managed via `envied` package with XOR obfuscation.

**File:** `lib/env.dart` (source) / `lib/env.g.dart` (generated)

| Variable | Field | Purpose |
|----------|-------|---------|
| `STADIA_MAPS_API_KEY` | `Env.stadiaMapsApiKey` | Map tile requests |

Verified 2026-08-04: this is the **only** field declared in `lib/env.dart`. Earlier revisions of this table listed two more variables that do not exist in the source; CI (`.github/workflows/ci.yml`) writes only `STADIA_MAPS_API_KEY` into `.env` before codegen. A leftover entry in a local `.env` is harmless — envied only reads fields declared on the class.

**How it works:**
- `@Envied()` annotation on `Env` class
- `@EnviedField(obfuscate: true)` on each field — generates XOR-encoded byte arrays in `.g.dart`
- Values sourced from `.env` file (not committed to git)
- Regenerate with `dart run build_runner build --delete-conflicting-outputs` after changing `.env`

> **AI warning:** Do not add secrets to `lib/env.dart` without `obfuscate: true`. Do not commit `.env` to git. Server-side secrets go in Firebase Secret Manager via `defineSecret`, not in envied.

---

## Google Play Signing: Upload Keys Only

**Decision:** Play App Signing is enabled. Google holds the **app signing key** and re-signs every build; the project owns only **upload keys** — one per app (spec 051, [L1] [L2]).

**Why:** With Play App Signing a lost or leaked upload key is recoverable through Play support; a lost app signing key would mean a new app listing. Two keys instead of one keep a leak of one app's key from letting anyone publish as the other.

**How it works:**
- `kz.qorzhyn.app` → upload key `clientUpload`; `kz.qorzhyn.business` → `businessUpload`. Both `keytool -genkeypair`, RSA 2048, alias `upload`, PKCS12 (so `keyPassword` = `storePassword`).
- Keystores and passwords live in the **password manager**. Locally: `android/key.properties` (gitignored, template `android/key.properties.example`) with absolute `storeFile` paths outside the repository. Build mechanics: `PROJECT.md`, "Release signing".
- CI: `.github/workflows/release.yml`, manual run only. Agents cannot write `.github/workflows/`, so a human adds it from the text in `ai_specs/051-release-signing-plan.md`, Phase 2; **while it is not in the repository there is no path to Play at all** — do not upload anything until it exists and has run green. It reads these repository secrets:

| Secret | Value |
|---|---|
| `CLIENT_UPLOAD_KEYSTORE_BASE64` / `BUSINESS_UPLOAD_KEYSTORE_BASE64` | keystore as one-line base64 (`base64 -i <keystore>.jks \| tr -d '\n'`) |
| `CLIENT_UPLOAD_STORE_PASSWORD` / `BUSINESS_UPLOAD_STORE_PASSWORD` | keystore password |
| `CLIENT_UPLOAD_KEY_ALIAS` / `BUSINESS_UPLOAD_KEY_ALIAS` | `upload` |
| `CLIENT_UPLOAD_KEY_PASSWORD` / `BUSINESS_UPLOAD_KEY_PASSWORD` | same as the keystore password (PKCS12) |
| `STADIA_MAPS_API_KEY` | shared with `ci.yml` — the real key, see "Environment Variables" |

Passwords go through `java.util.Properties`: keep them ASCII and without leading spaces.

**Before the first upload of each app:** the workflow only proves the two AABs are not debug-signed and not signed by the same key — it cannot tell a client keystore put into the `BUSINESS_*` secrets. Compare the SHA-256 that its "Verify AAB signatures" step prints for each app with `keytool -list -v -keystore <that app's keystore>`. The first upload binds the upload key to the app for good.

**Lost or leaked upload key:** generate a new one (same parameters), export its certificate (`keytool -export -rfc -keystore <new>.jks -alias upload -file upload_certificate.pem`), and request an upload key reset in Play Console → the app → Setup → App signing. Once Google confirms the reset, replace the keystore in the password manager, the four secrets of that app and the local `android/key.properties`. Possible only because Play App Signing is enabled. Rotation itself is out of scope of spec 051 — this is the procedure, not automation.

**Consequence:** the certificate installed apps are signed with is Google's app signing key, not the upload key. Anything that pins an Android certificate fingerprint (Google Cloud API key restrictions "Android package + SHA-1", Firebase app SHA settings) needs the app signing key's fingerprint from Play Console → App signing.

> **AI warning:** Never commit a keystore or `android/key.properties`. Do not suggest one upload key for both apps. Do not add any `release.yml` trigger besides `workflow_dispatch` (no push, tag or schedule). Do not suggest uploading a locally built AAB to Play — only `release.yml` artifacts, the one path that checks the signature. There is no app signing key in this project to store, back up, or put in CI.

---

## See Also

- `ai_toolkit/guidelines/firebase.md` — universal Firebase patterns (emulators, rules, auth, crashlytics)
- `ai_docs/CLOUD_FUNCTIONS_GOTCHAS.md` — function-specific decisions (schedules, retry logic, order paths)
