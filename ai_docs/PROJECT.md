# Qorzhyn (formerly Sarqyt) — Project Overview

## What is Qorzhyn?

Qorzhyn is a **Too Good To Go (TGTG)-style marketplace** for surplus food in Kazakhstan.
The name was approved on 2026-09-09 (see `RELEASE_READINESS.md`); `Sarqyt` survives only
in `package:sarqyt/`, in `name:` in `pubspec.yaml` and in the ARB keys `appTitle` /
`appTitleBusiness`, until the separate package-rename spec — see `GLOSSARY.md`. Stores (restaurants, bakeries, cafes) list surprise bags or specific items at a discount, and customers buy and pick them up during a time window.

Currency: **KZT (Kazakhstani Tenge, symbol: ₸)**.

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Dart 3.9+), multi-platform (Android, iOS, Web) |
| State management | Riverpod 3 with codegen (`@riverpod`) |
| Models | Freezed + json_serializable for immutable domain models |
| Backend | Firebase (Firestore, Auth, Storage, Cloud Functions, Messaging, Crashlytics) |
| Payments | None — reserve-only, customer pays offline at the store's terminal |
| Maps | flutter_map + latlong2 + geolocator + geoflutterfire_plus (geo-queries) |
| Cloud Functions | TypeScript (Node.js), located in `functions/` |
| Hosting | Firebase Hosting (business web app at `build/web`) |

## Two Apps, One Codebase

The project has **two entry points** sharing the same codebase:

- **`main_client.dart`** — Customer-facing app (`MyAppClient`). Browse offers on map, purchase surprise bags, track orders.
- **`main_business.dart`** — Business-facing app (`MyAppBusiness`). Manage store, items, offers, view orders/reservations, dashboard.
- **`main_fakes_client.dart`** — Client app with fake data for development.

Each app has its own router (`client_router.dart` / `business_router.dart`).

There is **no default entry point**: `lib/main.dart` does not exist, so every build
and run command names its target explicitly. On Android the target is paired with a
product flavor (`client` / `business`), which is what gives the two apps their own
`applicationId` and lets them sit side by side on one device.

```sh
flutter run   -t lib/main_client.dart   --flavor client
flutter run   -t lib/main_business.dart --flavor business
flutter build apk --release -t lib/main_client.dart   --flavor client
flutter build apk --release -t lib/main_business.dart --flavor business
flutter build web --release -t lib/main_business.dart   # business console; web has no flavors
flutter run   -t lib/main_fakes_client.dart --flavor client   # client app on fake data
```

`scripts/build-client-apk.sh` and `scripts/build-business-apk.sh` wrap the two release
APK commands; `scripts/build-client-aab.sh` and `scripts/build-business-aab.sh` do the
same for `flutter build appbundle`.

A command without `-t` fails outright: `Target file "lib/main.dart" not found` — Gradle
is never reached, and nothing in the message mentions flavors.

On Android a command that names `-t` but omits `--flavor` runs `assembleDebug`, which
with `flavorDimensions` declared produces no variant. **This fails only on a clean
`build/`** (`Gradle build failed to produce an .apk file`). With a stale
`build/app/outputs/flutter-apk/app-debug.apk` left from before the flavor split, Flutter
prints `✓ Built …app-debug.apk` and exits successfully while pointing at that stale
artifact — no build happened, and its `applicationId` is still `com.example.sarqyt`.
Recovery is `flutter clean`; prevention is always passing `--flavor`. CI
(`.github/workflows/ci.yml`, job `analyze-and-test`) builds a debug APK of both flavors
with explicit `--flavor` on every PR. See the Error flows section of
`ai_specs/archive/050-android-app-flavors-spec.md`.

### Release signing

Each app's release is signed with **its own upload key** (spec 051): `signingConfigs`
`clientUpload` / `businessUpload` in `android/app/build.gradle.kts`, read from
`android/key.properties` (gitignored; keys prefixed `client.` / `business.`, template in
`android/key.properties.example`). Keystores and passwords live in the password manager,
never in the repository; `storeFile` is an absolute path outside the working tree.

- A flavor with any of its four entries missing is signed with the **debug key** and the
  build prints `WARNING: no upload key for flavor '<flavor>' in android/key.properties`
  — only when that flavor's release is being built. Local work without keys is unchanged.
- A `storeFile` that does not exist or a wrong password fails the build: the file says
  signing was intended, so it is not silently replaced by the debug key.
- `buildTypes.release` deliberately sets no `signingConfig` — a buildType's signing config
  overrides the flavor's. Guarded by `test/src/app/flavor_config_test.dart`.
- Debug builds always use the debug key, with or without `key.properties`.

**Only release-workflow artifacts go to Google Play.** `.github/workflows/release.yml`
(manual `workflow_dispatch` only; added to the repo by hand — agents cannot write
`.github/workflows/` — from the text in `ai_specs/051-release-signing-plan.md`, Phase 2) restores both keystores from secrets, builds both AABs
with `versionCode` = the workflow run number, and fails if an AAB is debug-signed or both
apps carry the same certificate; artifacts are `qorzhyn-client-aab` /
`qorzhyn-business-aab`. A locally built AAB is for checking the signature, not for
upload: swapped paths in `key.properties` would bind the wrong key to an app in Play.
Keys, secrets and the lost-key procedure: `EXTERNAL_SERVICES.md`, "Google Play Signing".

## Feature Modules

Located in `lib/src/features/`:

| Feature | Purpose |
|---|---|
| `auth` | Firebase Auth, sign-in (email/password), profile editing, settings |
| `store` | Store domain model, store data layer |
| `items` | Item (product/surprise bag) CRUD — scheduled or one-time, with weekly schedule |
| `offers` | Published offers with quantity, pickup window, geo-location, badges, ratings |
| `orders` | Order lifecycle: confirmed -> preparing -> readyForPickup -> completed/cancelled/expired |
| `checkout` | Reservation flow — quantity selection and `reserveOffer`; no payment step |
| `map` | Map view with clustered markers for nearby offers |
| `review` | Customer reviews and ratings |
| `business_console` | Business dashboard, store verification (3-step), financials, settings |
| `onboarding` | New user onboarding flow |
| `notifications` | Push notifications via Firebase Messaging |

Each feature follows **feature-first** structure with layers: `domain/`, `data/`, `application/`, `presentation/`.

## Cloud Functions (TypeScript)

Located in `functions/src/features/`:

| Module | Key Functions |
|---|---|
| `payments` | `reserve-offer` (no separate payment-confirmation function exists) |
| `orders` | `cancel-order`, `expire-orders`, `update-order-status`, `on-order-status-changed` |
| `offers` | `daily-sync-offers` (generates offers from active items) |
| `merchant-onboarding` | Business verification and store creation |
| `notifications` | Push notifications for the order lifecycle: `on-order-created`/`on-order-status-changed` triggers (via `triggers/`) send FCM pushes through `helpers/send-push.ts`; `sendOrderReminders` (`onSchedule`, every 5 minutes) sends up to three pickup-window reminders plus a delayed review request. Texts live in `core/messages.ts`, scheduling logic in `core/reminders.ts` — both pure and unit-tested |
| `triggers` | Firestore triggers for side-effects |

## Firestore Collections

| Collection | Description |
|---|---|
| `stores/{storeId}` | Store profiles |
| `stores/{storeId}/items/{itemId}` | Items (products) belonging to a store |
| `offers/{offerId}` | Published offers (public read, admin-only write via Cloud Functions) |
| `orders/{orderId}` | Orders (created by Cloud Functions only). `completedAt: Timestamp?` set on transition to `completed`; `remindersSent: { beforeStart, midWindow, beforeEnd, reviewPrompt }` (all optional booleans, absence == `false`) tracks which notifications the scheduler already sent |
| `payments/{paymentId}` | Payment records (Cloud Functions only) |
| `users/{uid}` | User profiles |
| `users/{uid}/favorites/{storeId}` | Favorited stores |
| `reviews/{reviewId}` | Customer reviews |
| `storeDrafts/{draftId}` | Merchant onboarding drafts |
| `storeShips/{shipId}` | User-to-store binding (staff/owner) |
| `businesses/{businessId}` | Business entities |
| `business_membership/{id}` | User-to-business membership |
| `_processedEvents/{id}` | Idempotency dedup (internal) |

## User Roles

Managed via Firebase Auth custom claims:

- **Customer** (default) — browse offers, purchase, leave reviews
- **Partner** (`role: 'partner'`) — manage their store(s), view orders
- **Admin** (`role: 'admin'`) — full access

Partners can create stores if `canCreateStore` custom claim is `true`.

## Key Domain Models

- **Item** — a product template with price, schedule (weekly or one-time), dietary type, packaging option
- **Offer** — a published instance of an item with quantity, pickup window, geolocation, status (active/paused/expired)
- **Order** — a purchase record with status flow: `confirmed -> preparing -> readyForPickup -> completed | cancelled | expired`
- **Store** — business location with address, logo, rating, currency

## Order & Payment Flow

1. Customer selects offer and quantity
2. `reserve-offer` Cloud Function reserves quantity (decrement) and creates the `orders/{orderId}` document directly (status `confirmed`) — there is no payment step of any kind; the customer pays at the store on pickup
3. `triggers/onOrderCreated` assigns `orderNumber` and pushes the new order to the store team
4. Store owner/staff moves order through statuses: preparing -> readyForPickup -> completed, each transition notified via `on-order-status-changed`
5. `expire-orders` handles timeout for uncollected orders; `sendOrderReminders` sends pickup-window reminders and, 2h after `completedAt`, a review request if none was left

## Non-Obvious Decisions

Project-specific rationale that can't be inferred from reading the code alone — read before touching these areas:

- [`ai_docs/FIRESTORE_GOTCHAS.md`](FIRESTORE_GOTCHAS.md) — schema decisions, ID patterns, denormalization, known security-rule gaps
- [`ai_docs/CLOUD_FUNCTIONS_GOTCHAS.md`](CLOUD_FUNCTIONS_GOTCHAS.md) — schedules, region split, idempotency, retry logic
- [`ai_docs/ROUTING_DECISIONS.md`](ROUTING_DECISIONS.md) — two-app structure, redirect layers, scoped providers
- [`ai_docs/BUSINESS_RULES.md`](BUSINESS_RULES.md) — order state machine, permissions, enforcement gaps

## See Also

- [`ai_docs/GLOSSARY.md`](GLOSSARY.md) — canonical domain vocabulary
- [`ai_docs/EXTERNAL_SERVICES.md`](EXTERNAL_SERVICES.md) — third-party service choices and config quirks
- [`ai_docs/FIRESTORE_GOTCHAS.md`](FIRESTORE_GOTCHAS.md), [`ai_docs/CLOUD_FUNCTIONS_GOTCHAS.md`](CLOUD_FUNCTIONS_GOTCHAS.md), [`ai_docs/ROUTING_DECISIONS.md`](ROUTING_DECISIONS.md), [`ai_docs/BUSINESS_RULES.md`](BUSINESS_RULES.md) — see above
- [`ai_docs/solutions/`](solutions/) — accumulated bug-fix, refactor, and tooling lessons
- `ai_toolkit/RULES.md` — universal engineering rules (Flutter, Riverpod, GoRouter, Firebase) this project follows
