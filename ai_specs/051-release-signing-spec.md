---
title: Подпись release-сборок upload-ключами
status: refined      # draft | refined | approved | in-progress | done
size: M
date: 2026-10-22
type: feature
ledger: 051-release-signing-ledger.md
---

# Spec: Подпись release-сборок upload-ключами

Source request: Подпись release-сборок upload-ключами (блокер 2 в ai_docs/RELEASE_READINESS.md). Решения человека: Play App Signing включаем; раздельные upload-ключи для client (kz.qorzhyn.app) и business (kz.qorzhyn.business); ключи и пароли хранятся в менеджере паролей, вне репозитория; подписанная сборка AAB обоих flavor'ов делается в CI (новый release-workflow, правит человек — .github/workflows закрыт для агента). Gradle читает пароли из android/key.properties (gitignored), signingConfig на flavor, из buildTypes.release убрать debug-подпись. Открытый вопрос: поведение release-сборки без key.properties — fallback на debug-подпись с предупреждением или падение.

## Goal
Сейчас release-сборка обоих приложений подписана debug-ключом (`android/app/build.gradle.kts:61`), и Google Play её не примет — блокер 2 в `ai_docs/RELEASE_READINESS.md`. После спеки клиентское приложение и бизнес-приложение подписываются каждое своим upload-ключом, а CI по ручному запуску собирает два подписанных AAB, готовых к первой загрузке в Play с включённым Play App Signing. Локальная разработка без ключей работает как раньше.

## User Flow
**Happy path:**
1. Человек генерирует два upload-ключа (`keytool -genkeypair`, RSA 2048, alias `upload`) — по одному на приложение — и сохраняет keystore и пароли в менеджере паролей. [L2] [L3]
2. Копирует `android/key.properties.example` в `android/key.properties`, вписывает пути к keystore (вне репозитория) и пароли.
3. `scripts/build-client-aab.sh` и `scripts/build-business-aab.sh` собирают AAB, подписанные соответствующим upload-ключом.
4. Человек заводит восемь секретов подписи GitHub — по четыре на приложение (`STADIA_MAPS_API_KEY` уже заведён для `ci.yml`) — и вносит в репозиторий `.github/workflows/release.yml` по тексту из плана. [L4]
5. Запускает release-workflow кнопкой Run workflow. Тот собирает оба AAB с `versionCode` = номеру запуска, проверяет подпись и выкладывает AAB артефактами. [L7] [L8]
6. Первая загрузка AAB в Play Console включает Play App Signing и закрепляет upload-ключ за приложением — вне спеки. [L1] В Play загружаются только артефакты release-workflow: только там проверено, что AAB подписан не debug-ключом и что ключи двух приложений различаются. Локальные AAB из шага 3 — для проверки подписи, не для загрузки: перепутанные в `key.properties` пути закрепили бы за приложением чужой ключ, и исправить это можно только сбросом через поддержку Play.

**Errors & recovery:**
- `android/key.properties` нет или в нём нет ключей одного flavor'а → release этого flavor'а подписывается debug-ключом, в выводе сборки предупреждение с именем flavor'а и файла; сборка не падает. Исправление — заполнить файл. [L6]
- Путь `storeFile` указывает на несуществующий файл или пароль неверный → сборка падает с ошибкой Gradle/keytool. Это не fallback: файл есть, значит намерение подписать — есть, и тихая подмена ключа здесь вредна.
- В CI не задан хотя бы один из девяти секретов (восемь подписи + `STADIA_MAPS_API_KEY`) → workflow падает на первом шаге с перечислением недостающих имён, до сборки.
- AAB в CI оказался подписан debug-ключом или ключи двух приложений совпали → workflow падает на шаге проверки подписи, артефакты не выкладываются.
- Upload-ключ потерян → сброс через поддержку Play (возможен только потому, что включён Play App Signing [L1]); процедура описана в `ai_docs/EXTERNAL_SERVICES.md`.

## Requirements
- [ ] R1: `android/app/build.gradle.kts` объявляет два `signingConfig` — `clientUpload` и `businessUpload`, — читая `storeFile`, `storePassword`, `keyAlias`, `keyPassword` из `android/key.properties` по ключам с префиксом `client.` и `business.` соответственно. Каждый flavor ссылается на свой `signingConfig` в собственном блоке `create(...)`. Ограничение [L2] «ни один `signingConfig` и ни один секрет не используется обоими flavor'ами» относится к upload-подписи: к `clientUpload` / `businessUpload` и к секретам `*_UPLOAD_*`. Общий debug-`signingConfig` в fallback R3 [L6] и общий для обоих приложений `STADIA_MAPS_API_KEY` (R7) допускаются осознанно. Verifiable by: с заполненным `android/key.properties` `keytool -printcert -jarfile` по AAB каждого flavor'а показывает SHA-256 сертификата, совпадающий с `keytool -list -v` по его keystore, и отпечатки двух приложений различаются; тест R5. [L2] [L5]
- [ ] R2: `buildTypes.release` не задаёт `signingConfig`; debug-подпись в `release` не упоминается. Причина: `signingConfig` у buildType перебивает `signingConfig` у flavor'а, и ключи из R1 не применились бы. Debug-сборки по-прежнему подписываются debug-ключом. Verifiable by: тест R5; `apksigner verify --print-certs` по debug-APK показывает `CN=Android Debug`. [L5]
- [ ] R3: если `android/key.properties` отсутствует или в нём нет хотя бы одного из четырёх ключей flavor'а, release этого flavor'а подписывается debug-ключом, а Gradle печатает предупреждение, называющее flavor и файл `android/key.properties`. Предупреждение печатается только когда в графе задач есть release-задача этого flavor'а (`gradle.taskGraph.whenReady`): debug-сборки и `flutter run` без ключей его не выводят. Канал — `logger.quiet` (или `logger.error`), не `logger.warn`: без `-v` Flutter запускает Gradle с `-q` (`flutter_tools/lib/src/android/gradle.dart`, ветка `else { options.add('-q'); }`), и уровень WARN подавляется. Сборка не падает. Verifiable by: `scripts/build-client-apk.sh` без `android/key.properties` и без `-v` завершается успешно, в выводе есть предупреждение, `apksigner verify --print-certs` по APK показывает `CN=Android Debug` (для APK — `apksigner`, не `keytool`: при `minSdk` 24 APK подписывается только схемами v2/v3 без JAR-подписи, и `keytool -printcert -jarfile` по нему ничего не печатает; AAB подписывается JAR-подписью, и для него `keytool` подходит); джоба `analyze-and-test` в CI остаётся зелёной без новых секретов. [L6]
- [ ] R4: `.gitignore` игнорирует `android/key.properties`, `*.jks`, `*.keystore`. В репозиторий добавлен `android/key.properties.example` — восемь ключей с пустыми или заглушечными значениями и комментарием, что для PKCS12-keystore (формат `keytool` по умолчанию) `keyPassword` совпадает со `storePassword`. Verifiable by: `git check-ignore android/key.properties` и `git check-ignore some.jks` отвечают утвердительно; `git ls-files android/key.properties.example` находит файл. [L3]
- [ ] R5: тест `test/src/app/flavor_config_test.dart` получает проверки по тексту `android/app/build.gradle.kts`: блок `release` в `buildTypes` не содержит `signingConfig`; блок каждого flavor'а содержит `signingConfig`, и у `client` и `business` они разные. Существующий разбор `applicationId` по flavor'ам продолжает работать. Verifiable by: тест зелёный; возврат строки `signingConfig = signingConfigs.getByName("debug")` в `release` делает его красным; одинаковый `signingConfig` у двух flavor'ов делает его красным. [L2] [L5]
- [ ] R6: `scripts/build-client-aab.sh` и `scripts/build-business-aab.sh` собирают `flutter build appbundle --release` с `-t` и `--flavor` своего приложения и пробрасывают дополнительные аргументы. Комментарии в `scripts/build-{client,business}-apk.sh` больше не утверждают, что подпись всегда debug-ключом. Verifiable by: запуск обёрток даёт `build/app/outputs/bundle/clientRelease/app-client-release.aab` и `build/app/outputs/bundle/businessRelease/app-business-release.aab`. [L4]
- [ ] R7: текст `.github/workflows/release.yml` подготовлен агентом в плане под соответствующей задачей и внесён человеком. Workflow:
  - запускается только через `workflow_dispatch` [L7];
  - первым шагом проверяет, что заданы все девять секретов — восемь секретов подписи `CLIENT_UPLOAD_KEYSTORE_BASE64`, `CLIENT_UPLOAD_STORE_PASSWORD`, `CLIENT_UPLOAD_KEY_ALIAS`, `CLIENT_UPLOAD_KEY_PASSWORD` и такие же с префиксом `BUSINESS_` [L2], плюс `STADIA_MAPS_API_KEY` (пустой ключ проходит сборку и ломает карты в рантайме — `ai_docs/solutions/tooling/ci-secrets-api-keys-web-builds.md`), — и падает с перечислением недостающих;
  - ставит JDK 17 (Temurin) и Flutter 3.35.7 так же, как джоба `analyze-and-test`;
  - пишет `.env` с настоящим `STADIA_MAPS_API_KEY` из секретов, не заглушкой, и запускает `build_runner`;
  - восстанавливает оба keystore из base64 в `$RUNNER_TEMP` и пишет `android/key.properties` с абсолютными путями к ним; ничего из этого не печатается в лог;
  - собирает оба AAB с `--build-number=${{ github.run_number }}`; `--build-name` не передаётся, `versionName` берётся из `pubspec.yaml` [L8];
  - проверяет каждый AAB через `keytool -printcert -jarfile`: падает, если сертификата нет, если это `CN=Android Debug`, или если SHA-256 у двух приложений совпадают [L2] [L6];
  - выкладывает два AAB артефактами `qorzhyn-client-aab` и `qorzhyn-business-aab`.
  Verifiable by: ручной запуск даёт два артефакта; запуск с удалённым одним секретом падает на первом шаге с его именем. [L4]
- [ ] R8: документация обновлена в этом же изменении:
  - `ai_docs/RELEASE_READINESS.md` — блокер 2 закрыт; в сводке «Конфиги релиза» upload keystore больше не значится открытым;
  - `ai_docs/PROJECT.md` — раздел о сборке описывает подпись, `android/key.properties`, AAB-обёртки и release-workflow; удалены устаревшие утверждения «a release APK is still signed with the debug key» и «CI does *not* yet build either flavor»;
  - `ai_docs/EXTERNAL_SERVICES.md` — раздел о подписи Google Play: Play App Signing включён, проект хранит только upload-ключи, два ключа на два приложения, где лежат ключи и пароли (менеджер паролей), имена секретов CI, процедура сброса upload-ключа; AI warning — не коммитить keystore и `key.properties`, не предлагать общий ключ для двух приложений, не добавлять в release-workflow триггеры кроме `workflow_dispatch`, не предлагать загружать в Play локально собранный AAB — только артефакты release-workflow.
  Verifiable by: ревью дифа; `grep -n "signed with the debug key" ai_docs/PROJECT.md` пуст. [L1] [L3] [L7]

## Technical Constraints
**Files to modify:**
- `android/app/build.gradle.kts` — чтение `android/key.properties`, два `signingConfig`, ссылка на них из flavor'ов, удаление debug-подписи из `buildTypes.release` (R1–R3).
- `.gitignore` — три записи (R4).
- `test/src/app/flavor_config_test.dart` — проверки R5.
- `scripts/build-client-apk.sh`, `scripts/build-business-apk.sh` — комментарии (R6).
- `ai_docs/RELEASE_READINESS.md`, `ai_docs/PROJECT.md`, `ai_docs/EXTERNAL_SERVICES.md` — R8.

**Files to create:**
- `android/key.properties.example` — шаблон без секретов (R4).
- `scripts/build-client-aab.sh`, `scripts/build-business-aab.sh` — обёртки (R6).
- `.github/workflows/release.yml` — создаёт человек по тексту из плана (R7).

**Pattern to follow:**
- `test/src/app/flavor_config_test.dart` — проверка конфигурации по тексту Gradle-скрипта; новые проверки строятся так же.
- `.github/workflows/ci.yml`, джоба `analyze-and-test` — шаги JDK, Flutter, `.env`, `build_runner`; release-workflow повторяет их, а не изобретает свои.
- `scripts/build-client-apk.sh` — форма обёртки.
- `.env` + `.env.example` (`ai_toolkit/RULES.md`, раздел Layers & structure) — образец для `android/key.properties` + `android/key.properties.example`.

**Avoid:**
- Не держать `signingConfig = ...` в `buildTypes.release` «на всякий случай»: он перебьёт подпись flavor'а, и обе сборки молча уйдут под одним ключом.
- Не разворачивать логику чтения ключей внутри блоков `create("client")` / `create("business")`: регулярка в `flavor_config_test.dart` ищет `applicationId` до первой `}` блока. В блоке flavor'а — одно присваивание `signingConfig`; чтение и fallback — вне блоков.
- Не класть keystore внутрь репозитория даже под `.gitignore` — `storeFile` указывает на путь вне рабочего дерева.
- Не использовать в release-workflow заглушку `.env`: она проходит сборку и ломает карты в рантайме (`ai_docs/solutions/tooling/ci-secrets-api-keys-web-builds.md`).
- Не переименовывать `release.yml` после первой загрузки в Play: `github.run_number` считается на файл workflow и после переименования начнётся с 1, а Play отклонит `versionCode` меньше уже загруженного.

## Out of Scope
- NOT аккаунт, листинг и первая загрузка в Play Console, включение Play App Signing в консоли — ручные действия человека после спеки [L1].
- NOT автоматическая выкладка в Play (fastlane, Play Developer API) — Play-аккаунта ещё нет, workflow заканчивается артефактами.
- NOT подпись iOS — iOS отложен, нет аккаунта разработчика Apple.
- NOT смена или ротация upload-ключей — процедура только описывается в `EXTERNAL_SERVICES.md`.
- NOT подключение Google Services Gradle plugin — решение [L6] спеки 050 не пересматривается.
- NOT удаление APK-обёрток — APK остаются для локального QA.
- NOT запуск release-workflow по тегу, push или расписанию [L7].

## Validation
**Test seams:** существующий конфигурационный tripwire по файловой системе — `test/src/app/flavor_config_test.dart`, читающий `android/app/build.gradle.kts` как текст. Новых моков и seam'ов нет: поведение приложения не меняется. Реальная подпись проверяется только сборкой — локально и в release-workflow.

**Automated tests:** R5 → `test/src/app/flavor_config_test.dart`. Регрессия: `flutter test --exclude-tags golden` и джоба `analyze-and-test` зелёные без `android/key.properties` и без новых секретов.

**Manual QA:**
1. Given заполненный `android/key.properties`, when выполнены обе AAB-обёртки, then SHA-256 из `keytool -printcert -jarfile` по каждому AAB совпадает с `keytool -list -v` по keystore своего приложения, и отпечатки двух AAB различаются.
2. Given `android/key.properties` отсутствует, when выполнен `scripts/build-client-apk.sh`, then сборка успешна, в выводе предупреждение с `client` и `android/key.properties`, `apksigner verify --print-certs` по APK показывает `CN=Android Debug`.
3. Given любое состояние ключей, when собран debug-APK (`flutter build apk --debug --flavor client -t lib/main_client.dart`), then `apksigner verify --print-certs` показывает `CN=Android Debug`.
4. Given все девять секретов заданы, when release-workflow запущен вручную, then выложены `qorzhyn-client-aab` и `qorzhyn-business-aab`, а `versionCode` в AAB равен номеру запуска (`bundletool dump manifest --bundle <aab> --xpath /manifest/@android:versionCode`).
5. Given удалён один из секретов подписи или `STADIA_MAPS_API_KEY`, when release-workflow запущен, then он падает на первом шаге, и в логе названо имя недостающего секрета.
