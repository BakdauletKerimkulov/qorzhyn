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

- [ ] `ai_specs/051-release-signing-plan.md` — под задачей ниже в `<details>` полный текст `.github/workflows/release.yml` по пунктам R7: только `workflow_dispatch` [L7]; первый шаг — девять секретов, падение с перечислением недостающих; JDK 17 Temurin + Flutter 3.35.7 + `flutter pub get` как `analyze-and-test`; `.env` с настоящим `STADIA_MAPS_API_KEY`; `build_runner`; keystore из base64 в `$RUNNER_TEMP` + `android/key.properties` с абсолютными путями без вывода в лог; два AAB через обёртки с `--build-number=${{ github.run_number }}`, без `--build-name` [L8]; проверка `keytool -printcert -jarfile` (нет сертификата / `CN=Android Debug` / равные SHA-256 → падение) [L2] [L6]; `upload-artifact` `qorzhyn-client-aab` / `qorzhyn-business-aab`. Секреты — через `env:` шага, не интерполяцией `${{ }}` в тело скрипта
- [ ] TDD: шаг проверки подписи из текста выше, вынесенный в локальный прогон по AAB — падает на debug-подписанном AAB (сборка без `key.properties`), падает при одном keystore на оба flavor'а, проходит на двух одноразовых keystore; шаг проверки секретов падает с именем пропущенной переменной → then закрепить текст
- [ ] `.github/workflows/release.yml` — **ручной шаг человека**: внести файл по тексту из `<details>`; не переименовывать после первой загрузки в Play (`run_number` считается на файл) (R7) [L4]
- [ ] GitHub → Settings → Secrets — **ручной шаг человека**: восемь секретов `CLIENT_UPLOAD_*` / `BUSINESS_UPLOAD_*` (keystore — `base64` без переносов строк); `STADIA_MAPS_API_KEY` уже есть
- [ ] Verify: `./scripts/gate.sh`; человек — ручной запуск даёт два артефакта, `versionCode` = номер запуска через `bundletool dump manifest` (QA-4); запуск без одного секрета падает на первом шаге с его именем (QA-5); `analyze-and-test` на PR зелёный без новых секретов (R3)

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
