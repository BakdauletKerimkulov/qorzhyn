---
title: Подпись release-сборок upload-ключами
status: in-progress  # draft | refined | approved | in-progress | done
size: M
date: 2026-10-31
type: feature
---

# Plan: Подпись release-сборок upload-ключами

Source: `ai_specs/051-release-signing-spec.md`

## Overview
Release обоих flavor'ов уходит под свой upload-ключ: два `signingConfig` (`clientUpload` / `businessUpload`) из `android/key.properties`, ссылка из блока flavor'а, debug-подпись убрана из `buildTypes.release`; без ключей — fallback на debug с предупреждением. Phase 1 доказывает цепочку `key.properties → Gradle → подписанный AAB → keytool` на одноразовых keystore. Phase 2 — текст `release.yml` для человека и прогон его проверки подписи локально. Phase 3 — документация. Кода приложения план не трогает.

**Spec:** `ai_specs/051-release-signing-spec.md`

## Context
- **Structure:** feature-first Flutter; вся работа вне `lib/` — `android/`, `scripts/`, `.gitignore`, `.github/` (руками человека), `ai_docs/`; в `test/` — один существующий файл.
- **State management:** Riverpod codegen; не затрагивается.
- **Reference implementations:** `test/src/app/flavor_config_test.dart` — проверка конфигурации по тексту Gradle-скрипта (`_applicationIdsByFlavor`, guard-тест от «пустого» цикла); `scripts/build-client-apk.sh` — форма обёртки; `.github/workflows/ci.yml` джоба `analyze-and-test` — шаги JDK / Flutter / `.env` / `build_runner`; `ai_specs/archive/050-android-app-flavors-plan.md` Phase 3 — форма задачи «текст workflow для человека» (`<details>` + отметка, что применено человеком).
- **Test seams:** только существующий файловый tripwire `test/src/app/flavor_config_test.dart` (спека, Validation). Новых seam'ов и моков нет. Реальная подпись — только сборкой.
- **Testing convention:** `ai_toolkit/testing.md` § Test seams, § Conventions — `test/` зеркалит `lib/`, проверка падает с `reason`, объясняющим причину.
- **Lint + test command:** `./scripts/gate.sh`
- **Local tooling:** `keytool` в PATH (`/opt/homebrew/opt/openjdk@21/bin`); `apksigner` не в PATH — `~/Library/Android/sdk/build-tools/36.1.0/apksigner`; `bundletool` не установлен (нужен только QA-4, это проверка человека в CI-артефакте).
- **Assumptions / Gaps:**
  - R7 требует текст `release.yml` «в плане под соответствующей задачей», контракт плана запрещает код. Решение: этот план кода не содержит; `/work` в Phase 2 дописывает полный текст в `<details>` под задачей `release.yml` — как в Phase 3 плана 050.
  - `.github/workflows/` закрыт для агента правами и `guard-edits.sh` [L4]. Phase 2 не закрывается агентом: внесение файла, восемь секретов, ручной запуск (QA-4, QA-5) — человек. `/work` останавливается после подготовки текста.
  - Настоящие upload-ключи генерирует человек (User Flow 1) [L3]. Агент проверяет подпись только одноразовыми keystore в `$TMPDIR`, вне рабочего дерева; QA-1 на настоящих ключах — человек.
  - Пустой `release {}` в `buildTypes`: удалить блок или оставить пустым — локальный выбор `/work`. Тест R5 обязан работать в обоих случаях: отсутствие блока — не нарушение, а возвращённый в блок `signingConfig` — красный.
  - Ledger: все `current` L1–L8 имеют `[L#]` в спеке; `deferred` нет.

## Plan

### Phase 1 — Thin vertical slice: client и business подписываются своим ключом
**Goal:** `key.properties` → два `signingConfig` → два AAB с разными сертификатами; без файла — debug с предупреждением.

- [x] `.gitignore` — `android/key.properties`, `*.jks`, `*.keystore` в секции «Platform secrets»; `android/key.properties.example` — восемь ключей `client.*` / `business.*` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) с заглушками, комментарии: путь абсолютный и вне репозитория, для PKCS12 `keyPassword` = `storePassword` (R4) [L3] _(корневой `.gitignore` дублирует `android/.gitignore` по `key.properties`/`*.jks`/`*.keystore` внутри `android/`, но покрывает keystore в любом другом месте дерева; пустые значения считаются отсутствующими — скопированный как есть `.example` даёт fallback, а не падение)_
- [x] TDD: `test/src/app/flavor_config_test.dart` — (a) блок `release` внутри `buildTypes` не содержит `signingConfig` (нет блока — проходит); (b) блок каждого flavor'а содержит присваивание `signingConfig`; (c) у `client` и `business` правые части различаются; (d) guard по образцу существующего: разбор `signingConfig` находит ровно оба flavor'а. Регулярки — в пределах блока, как `[^}]` в `_applicationIdsByFlavor`. Сейчас красные (a), (b). Проверить мутациями из R5: строка `signingConfigs.getByName("debug")` в `release` → красный; одинаковый `signingConfig` у двух flavor'ов → красный (R5) [L2] [L5] → then implement _(RED: (a) нашёл `signingConfig = signingConfigs.getByName("debug")` в `release`, (b) — пустой набор flavor'ов. (d) совмещён с (b): `unorderedEquals(['client','business'])` перед сравнением. Мутации проверены: debug-подпись в `release`, одинаковый `signingConfig`, удалённое присваивание у `business` — каждая даёт ровно один красный тест)_
- [x] `android/app/build.gradle.kts` — вне блоков flavor'ов: чтение `android/key.properties` (rootProject-относительно), `signingConfigs` `clientUpload` / `businessUpload` из ключей с префиксом; выбор на flavor: все четыре ключа есть → upload-конфиг, иначе `debug`; предупреждение через `gradle.taskGraph.whenReady` только при release-задаче этого flavor'а в графе, канал `logger.quiet`/`logger.error`, текст называет flavor и `android/key.properties`. Существование `storeFile` не проверять — битый путь/пароль обязан ронять сборку (Errors & recovery). В `create("client")` / `create("business")` — одно присваивание `signingConfig`, без логики. Из `buildTypes.release` убрать `signingConfig` и TODO-комментарий про debug-ключи (R1, R2, R3) [L2] [L5] [L6] _(upload-конфиг регистрируется только при полном наборе ключей — неполный не создаётся вовсе, риск «неиспользуемый неполный конфиг валит сборку» снят. Предупреждение сначала искало задачи по суффиксу `<Flavor>Release` и при сборке client печаталось и про business: Flutter Gradle plugin затягивает в граф `compileFlutterBuildBusinessRelease` и др. другого flavor'а. Признак заменён на `validateSigning<Flavor>Release` — есть и в APK-, и в AAB-графе, только у собираемого flavor'а)_
- [x] `scripts/build-client-aab.sh`, `scripts/build-business-aab.sh` — `flutter build appbundle --release -t … --flavor …` + `"$@"`, форма и шапка-комментарий как у `scripts/build-client-apk.sh`; `chmod +x` (R6) [L4]
- [x] Локальная проверка цепочки на одноразовых keystore — два `keytool -genkeypair` (RSA 2048, alias `upload`) в `$TMPDIR`, временный `android/key.properties` с абсолютными путями: обе AAB-обёртки → `keytool -printcert -jarfile` по `build/app/outputs/bundle/{client,business}Release/app-{client,business}-release.aab` = SHA-256 из `keytool -list -v` своего keystore, отпечатки различаются (QA-1). Затем: удалить только `business.*` → business-release под debug с предупреждением `business`, client по-прежнему upload; несуществующий `client.storeFile` → сборка падает. После — `android/key.properties` и keystore удалить, `git status` чист от них _(одноразовые PKCS12 RSA 2048 в scratchpad сессии. QA-1: AAB client → `CN=Qorzhyn client throwaway`, SHA-256 `6D:A7:…:E6:0B` = keystore client; business → `59:F3:…:B6:E6` = keystore business; различаются. Без `business.*`: client — upload, без предупреждения; business — `CN=Android Debug` + предупреждение `business`. Несуществующий `client.storeFile` → падение `validateSigningClientRelease`: «Keystore file … not found for signing config 'clientUpload'». Файл и keystore удалены, `git status` их не показывает)_
- [x] Verify: `./scripts/gate.sh`; без `android/key.properties` и без `-v` `scripts/build-client-apk.sh` успешен, в выводе предупреждение с `client` и `android/key.properties`, `apksigner verify --print-certs` → `CN=Android Debug` (QA-2); `flutter build apk --debug --flavor client -t lib/main_client.dart` — без предупреждения, `CN=Android Debug` (QA-3); `git check-ignore android/key.properties some.jks` утвердительно _(гейт зелёный с первого прогона. QA-2: exit 0, ровно одно предупреждение — про `client`, `apksigner` → `CN=Android Debug`. QA-3: debug-APK без предупреждения, `CN=Android Debug`. `check-ignore` отвечает на оба пути)_

### Phase 2 — Release-workflow в CI
**Goal:** готовый текст `release.yml` для человека, его проверка подписи прогнана локально на AAB из Phase 1.

- [x] `ai_specs/051-release-signing-plan.md` — под задачей ниже в `<details>` полный текст `.github/workflows/release.yml` по пунктам R7: только `workflow_dispatch` [L7]; первый шаг — девять секретов, падение с перечислением недостающих; JDK 17 Temurin + Flutter 3.35.7 + `flutter pub get` как `analyze-and-test`; `.env` с настоящим `STADIA_MAPS_API_KEY`; `build_runner`; keystore из base64 в `$RUNNER_TEMP` + `android/key.properties` с абсолютными путями без вывода в лог; два AAB через обёртки с `--build-number=${{ github.run_number }}`, без `--build-name` [L8]; проверка `keytool -printcert -jarfile` (нет сертификата / `CN=Android Debug` / равные SHA-256 → падение) [L2] [L6]; `upload-artifact` `qorzhyn-client-aab` / `qorzhyn-business-aab`. Секреты — через `env:` шага, не интерполяцией `${{ }}` в тело скрипта _(текст — в `<details>` ниже; совпадает байт в байт с файлом, на котором прогнаны проверки следующей задачи. Сверх R7: `permissions: contents: read`; пароли экранируются под `java.util.Properties` (`\` → `\\`); keystore и `key.properties` пишутся под `umask 077`)_
- [x] TDD: шаг проверки подписи из текста выше, вынесенный в локальный прогон по AAB — падает на debug-подписанном AAB (сборка без `key.properties`), падает при одном keystore на оба flavor'а, проходит на двух одноразовых keystore; шаг проверки секретов падает с именем пропущенной переменной → then закрепить текст _(шаги извлекались из YAML Ruby'ем и запускались с флагами GitHub — `bash --noprofile --norc -eo pipefail`, но локальным bash 3.2 (на `ubuntu-latest` — 5.x): поведение `escape()` на GitHub окончательно подтвердит только QA-4; сбой там даст падение на неверном пароле, не тихую подмену ключа. Секреты: полный набор → проходит; пустой `STADIA_MAPS_API_KEY` → `Missing repository secrets: STADIA_MAPS_API_KEY`; два пустых → названы оба. Подпись: debug-AAB → `client: signed with the DEBUG key`; нет AAB → `not found`; AAB без `META-INF` → `carries no signing certificate`; один keystore на оба (через шаг восстановления из base64) → `signed with the same key`; два keystore → проходит, SHA-256 client = его keystore. Пароли со `\ = : #` прошли через `Properties` — подпись успешна. Шаг восстановления в лог ничего не пишет. В собранном манифесте `versionCode=7` (подставленный `run_number`), `versionName=1.0.0` из `pubspec.yaml` [L8]. Первая версия проверки вызывала `fail` внутри `$(…)` — `::error::` терялся в переменной; исправлено до прогона)_
- [ ] `.github/workflows/release.yml` — **ручной шаг человека**: внести файл по тексту из `<details>`; не переименовывать после первой загрузки в Play (`run_number` считается на файл) (R7) [L4] _blocked: ручной шаг человека — `.github/workflows/` закрыт для агента [L4]; текст готов в `<details>` выше_
<details>
<summary><b>Готовый текст <code>.github/workflows/release.yml</code></b> (вносит человек: <code>.github/workflows/</code> закрыт для агента правами и хуком <code>guard-edits.sh</code> [L4])</summary>

```yaml
name: "Release"

# Signed AABs of both apps for Google Play (spec 051). Manual only ([L7]):
# no push, tag or schedule trigger. Do not rename this file after the first
# Play upload — github.run_number is the versionCode ([L8]) and restarts at 1
# for a renamed workflow, which Play rejects as a downgrade.
on:
    workflow_dispatch:

permissions:
    contents: read

jobs:
    build-aab:
        runs-on: ubuntu-latest
        steps:
            # Before anything else: a missing secret must fail in seconds and
            # by name, not as a debug-signed build twenty minutes later.
            - name: Check required secrets
              env:
                  CLIENT_UPLOAD_KEYSTORE_BASE64: ${{ secrets.CLIENT_UPLOAD_KEYSTORE_BASE64 }}
                  CLIENT_UPLOAD_STORE_PASSWORD: ${{ secrets.CLIENT_UPLOAD_STORE_PASSWORD }}
                  CLIENT_UPLOAD_KEY_ALIAS: ${{ secrets.CLIENT_UPLOAD_KEY_ALIAS }}
                  CLIENT_UPLOAD_KEY_PASSWORD: ${{ secrets.CLIENT_UPLOAD_KEY_PASSWORD }}
                  BUSINESS_UPLOAD_KEYSTORE_BASE64: ${{ secrets.BUSINESS_UPLOAD_KEYSTORE_BASE64 }}
                  BUSINESS_UPLOAD_STORE_PASSWORD: ${{ secrets.BUSINESS_UPLOAD_STORE_PASSWORD }}
                  BUSINESS_UPLOAD_KEY_ALIAS: ${{ secrets.BUSINESS_UPLOAD_KEY_ALIAS }}
                  BUSINESS_UPLOAD_KEY_PASSWORD: ${{ secrets.BUSINESS_UPLOAD_KEY_PASSWORD }}
                  STADIA_MAPS_API_KEY: ${{ secrets.STADIA_MAPS_API_KEY }}
              run: |
                  missing=()
                  for name in \
                      CLIENT_UPLOAD_KEYSTORE_BASE64 CLIENT_UPLOAD_STORE_PASSWORD \
                      CLIENT_UPLOAD_KEY_ALIAS CLIENT_UPLOAD_KEY_PASSWORD \
                      BUSINESS_UPLOAD_KEYSTORE_BASE64 BUSINESS_UPLOAD_STORE_PASSWORD \
                      BUSINESS_UPLOAD_KEY_ALIAS BUSINESS_UPLOAD_KEY_PASSWORD \
                      STADIA_MAPS_API_KEY; do
                      [[ -n "${!name:-}" ]] || missing+=("$name")
                  done
                  if (( ${#missing[@]} > 0 )); then
                      echo "::error::Missing repository secrets: ${missing[*]}"
                      exit 1
                  fi

            - uses: actions/checkout@v4

            - uses: actions/setup-java@v4
              with:
                  distribution: temurin
                  java-version: "17"

            - uses: subosito/flutter-action@v2
              with:
                  channel: stable
                  flutter-version: 3.35.7
                  cache: true

            - run: flutter pub get

            # The real key, never a placeholder: a placeholder compiles and
            # breaks maps at runtime (ai_docs/solutions/tooling/ci-secrets-api-keys-web-builds.md).
            - name: Create .env for envied codegen
              env:
                  STADIA_MAPS_API_KEY: ${{ secrets.STADIA_MAPS_API_KEY }}
              run: printf 'STADIA_MAPS_API_KEY=%s\n' "$STADIA_MAPS_API_KEY" > .env

            - run: dart run build_runner build --delete-conflicting-outputs

            # Keystores go to $RUNNER_TEMP, outside the checkout ([L3]).
            # Nothing here is echoed: values come in through env, not ${{ }}
            # in the script body. Backslashes are doubled because
            # java.util.Properties treats `\` as an escape.
            - name: Restore upload keystores
              env:
                  CLIENT_UPLOAD_KEYSTORE_BASE64: ${{ secrets.CLIENT_UPLOAD_KEYSTORE_BASE64 }}
                  CLIENT_UPLOAD_STORE_PASSWORD: ${{ secrets.CLIENT_UPLOAD_STORE_PASSWORD }}
                  CLIENT_UPLOAD_KEY_ALIAS: ${{ secrets.CLIENT_UPLOAD_KEY_ALIAS }}
                  CLIENT_UPLOAD_KEY_PASSWORD: ${{ secrets.CLIENT_UPLOAD_KEY_PASSWORD }}
                  BUSINESS_UPLOAD_KEYSTORE_BASE64: ${{ secrets.BUSINESS_UPLOAD_KEYSTORE_BASE64 }}
                  BUSINESS_UPLOAD_STORE_PASSWORD: ${{ secrets.BUSINESS_UPLOAD_STORE_PASSWORD }}
                  BUSINESS_UPLOAD_KEY_ALIAS: ${{ secrets.BUSINESS_UPLOAD_KEY_ALIAS }}
                  BUSINESS_UPLOAD_KEY_PASSWORD: ${{ secrets.BUSINESS_UPLOAD_KEY_PASSWORD }}
              run: |
                  umask 077
                  escape() { printf '%s' "${1//\\/\\\\}"; }
                  printf '%s' "$CLIENT_UPLOAD_KEYSTORE_BASE64" | base64 -d > "$RUNNER_TEMP/client-upload.jks"
                  printf '%s' "$BUSINESS_UPLOAD_KEYSTORE_BASE64" | base64 -d > "$RUNNER_TEMP/business-upload.jks"
                  {
                      printf 'client.storeFile=%s\n' "$(escape "$RUNNER_TEMP/client-upload.jks")"
                      printf 'client.storePassword=%s\n' "$(escape "$CLIENT_UPLOAD_STORE_PASSWORD")"
                      printf 'client.keyAlias=%s\n' "$(escape "$CLIENT_UPLOAD_KEY_ALIAS")"
                      printf 'client.keyPassword=%s\n' "$(escape "$CLIENT_UPLOAD_KEY_PASSWORD")"
                      printf 'business.storeFile=%s\n' "$(escape "$RUNNER_TEMP/business-upload.jks")"
                      printf 'business.storePassword=%s\n' "$(escape "$BUSINESS_UPLOAD_STORE_PASSWORD")"
                      printf 'business.keyAlias=%s\n' "$(escape "$BUSINESS_UPLOAD_KEY_ALIAS")"
                      printf 'business.keyPassword=%s\n' "$(escape "$BUSINESS_UPLOAD_KEY_PASSWORD")"
                  } > android/key.properties

            # versionCode = run number ([L8]); versionName stays from pubspec.yaml,
            # so no --build-name.
            - run: ./scripts/build-client-aab.sh --build-number=${{ github.run_number }}

            - run: ./scripts/build-business-aab.sh --build-number=${{ github.run_number }}

            # The only gate between these artifacts and Play ([L6]): a debug
            # fallback or one key used for both apps ([L2]) fails here, before
            # anything is uploaded.
            - name: Verify AAB signatures
              run: |
                  fail() { echo "::error::$1"; exit 1; }
                  # Sets $sha in this shell: a $(…) subshell would swallow
                  # fail's ::error:: line into the variable.
                  fingerprint() {
                      local aab="build/app/outputs/bundle/${1}Release/app-${1}-release.aab" certs owner
                      [[ -f "$aab" ]] || fail "$1: $aab not found"
                      certs="$(keytool -printcert -jarfile "$aab")" || fail "$1: keytool cannot read $aab"
                      owner="$(grep -m1 '^Owner:' <<<"$certs" || true)"
                      sha="$(grep -m1 'SHA256:' <<<"$certs" | awk '{print $2}' || true)"
                      [[ -n "$owner" && -n "$sha" ]] || fail "$1: $aab carries no signing certificate"
                      [[ "$owner" != *"CN=Android Debug"* ]] || fail "$1: signed with the DEBUG key — upload key missing from android/key.properties"
                      echo "$1: $owner, SHA-256 $sha"
                  }
                  fingerprint client; client_sha="$sha"
                  fingerprint business; business_sha="$sha"
                  [[ "$client_sha" != "$business_sha" ]] || fail "client and business are signed with the same key ($client_sha)"

            - uses: actions/upload-artifact@v4
              with:
                  name: qorzhyn-client-aab
                  path: build/app/outputs/bundle/clientRelease/app-client-release.aab
                  if-no-files-found: error

            - uses: actions/upload-artifact@v4
              with:
                  name: qorzhyn-business-aab
                  path: build/app/outputs/bundle/businessRelease/app-business-release.aab
                  if-no-files-found: error
```

Секреты (Settings → Secrets and variables → Actions → New repository secret), по четыре на приложение:

| Секрет | Значение |
|---|---|
| `CLIENT_UPLOAD_KEYSTORE_BASE64` / `BUSINESS_UPLOAD_KEYSTORE_BASE64` | `base64 -i <keystore>.jks \| tr -d '\n' \| pbcopy` — одной строкой |
| `CLIENT_UPLOAD_STORE_PASSWORD` / `BUSINESS_UPLOAD_STORE_PASSWORD` | пароль keystore |
| `CLIENT_UPLOAD_KEY_ALIAS` / `BUSINESS_UPLOAD_KEY_ALIAS` | `upload` |
| `CLIENT_UPLOAD_KEY_PASSWORD` / `BUSINESS_UPLOAD_KEY_PASSWORD` | для PKCS12 — тот же, что пароль keystore |

`STADIA_MAPS_API_KEY` уже заведён для `ci.yml`.
</details>

- [ ] GitHub → Settings → Secrets — **ручной шаг человека**: восемь секретов `CLIENT_UPLOAD_*` / `BUSINESS_UPLOAD_*` (keystore — `base64` без переносов строк); `STADIA_MAPS_API_KEY` уже есть _blocked: ручной шаг человека — секреты заводятся в настройках репозитория; таблица значений — в `<details>` выше_
- [ ] Verify: `./scripts/gate.sh`; человек — ручной запуск даёт два артефакта, `versionCode` = номер запуска через `bundletool dump manifest` (QA-4); запуск без одного секрета падает на первом шаге с его именем (QA-5); `analyze-and-test` на PR зелёный без новых секретов (R3) _blocked: агентская часть пройдена (`./scripts/gate.sh` зелёный); QA-4, QA-5 и зелёный `analyze-and-test` на PR — после внесения `release.yml` и секретов человеком_

### Phase 3 — Документация и комментарии
**Goal:** ни один файл не утверждает, что release подписан debug-ключом; подпись и её процедуры описаны.

- [ ] `scripts/build-client-apk.sh`, `scripts/build-business-apk.sh` — шапка: подпись upload-ключом из `android/key.properties`, без файла — debug с предупреждением; ссылка на блокер 2 убрана (R6)
- [ ] `ai_docs/RELEASE_READINESS.md` — блокер 2 закрыт (вычеркнуть со ссылкой на спеку 051), строка «Конфиги релиза» без «остался upload keystore», дата обновления в шапке (R8)
- [ ] `ai_docs/PROJECT.md` — раздел сборки: подпись, `android/key.properties` + `.example`, AAB-обёртки, release-workflow и «в Play — только его артефакты»; удалить «a release APK is still signed with the debug key» и устаревшее «CI does *not* yet build either flavor» (R8)
- [ ] `ai_docs/EXTERNAL_SERVICES.md` — раздел «Google Play signing» в формате соседних: Play App Signing включён, проект хранит только upload-ключи (ключа подписи приложения нет нигде [L1]), два ключа на два приложения, менеджер паролей, имена девяти секретов, процедура сброса upload-ключа; AI warning — четыре запрета из R8; ссылка в «See Also» при необходимости (R8) [L1] [L3] [L7]
- [ ] `ai_docs/GLOSSARY.md` — сверить «Upload key» с итоговыми именами (`clientUpload` / `businessUpload`, `android/key.properties`); правка только при расхождении
- [ ] Verify: `./scripts/gate.sh`; `grep -n "signed with the debug key" ai_docs/PROJECT.md` пуст; `grep -rn "debug-ключ\|debug key" scripts/ ai_docs/` — только описание fallback'а и debug-сборок

## Data layer changes
_None._

## External integrations
- GitHub Actions — новый `release.yml` (только `workflow_dispatch`), восемь новых секретов; вносит человек.
- Google Play — только подготовка AAB; Play Console, Play App Signing, первая загрузка — вне спеки [L1].

## Risks
- Неполный `signingConfig` (`clientUpload` без `storeFile`) может валить конфигурацию даже неиспользуемым → в Phase 1 прогнать сборку без `key.properties` до любых других проверок; при падении — не регистрировать upload-конфиг при неполных ключах (имя-выбор на flavor остаётся).
- `signingConfig` у `debug` buildType перебивает flavor'ный — на этом держится R2 «debug остаётся debug» → закреплено QA-3 в Verify Phase 1.
- Предупреждение через `logger.warn` невидимо под `-q` Flutter'а → `logger.quiet`, проверка именно без `-v` (QA-2).
- Регулярка `[^}]` в `flavor_config_test.dart` ломается от фигурных скобок в блоке flavor'а → логика выбора вне блоков, в блоке одно присваивание.
- Относительный `storeFile` резолвится от `android/app/`, а не от корня → `.example` и workflow пишут абсолютные пути.
- Секрет попадает в лог через `set -x`/`echo` или `${{ secrets.* }}` в теле скрипта → секреты через `env:`, без трассировки; проверить лог первого запуска.
- Локальный AAB с перепутанными путями закрепил бы за приложением чужой ключ → в Play только артефакты workflow; записано в `PROJECT.md` и AI warning `EXTERNAL_SERVICES.md`.

## Out of scope
- NOT аккаунт, листинг и первая загрузка в Play Console, включение Play App Signing в консоли — ручные действия человека после спеки [L1].
- NOT автоматическая выкладка в Play (fastlane, Play Developer API) — Play-аккаунта ещё нет, workflow заканчивается артефактами.
- NOT подпись iOS — iOS отложен, нет аккаунта разработчика Apple.
- NOT смена или ротация upload-ключей — процедура только описывается в `EXTERNAL_SERVICES.md`.
- NOT подключение Google Services Gradle plugin — решение [L6] спеки 050 не пересматривается.
- NOT удаление APK-обёрток — APK остаются для локального QA.
- NOT запуск release-workflow по тегу, push или расписанию [L7].
