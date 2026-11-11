---
title: Подпись release-сборок upload-ключами
parent: 051-release-signing-spec.md
date: 2026-10-22
---

## L1
Status: current
Question: Включаем ли Play App Signing?
Answer: Да.
Decision: Google хранит ключ подписи приложения и переподписывает сборки; проект владеет только upload-ключами.
Constraints:
- Ключа подписи приложения нет ни в репозитории, ни в CI, ни в документации как чего-то, что проект хранит.

## L2
Status: current
Question: Один upload-ключ на оба приложения или по одному на каждое?
Answer: Разные ключи.
Decision: Два keystore — для `kz.qorzhyn.app` и `kz.qorzhyn.business`; два `signingConfig` в Gradle; раздельные наборы секретов в CI.
Constraints:
- Ни один `signingConfig` и ни один секрет не используется обоими flavor'ами.

## L3
Status: current
Question: Где хранятся keystore и пароли?
Answer: В менеджере паролей.
Decision: Keystore и пароли лежат вне репозитория; в git попадает только шаблон без секретов.
Constraints:
- `android/key.properties`, `*.jks`, `*.keystore` игнорируются git'ом.

## L4
Status: current
Question: Где собирается подписанная сборка для Play?
Answer: В CI.
Decision: Новый release-workflow собирает AAB обоих flavor'ов. Файл в `.github/workflows/` вносит человек: каталог закрыт для агента правами и хуком `guard-edits.sh`; агент передаёт готовый текст.
Constraints:
- Агент не пишет в `.github/workflows/`.

## L5
Status: current
Question: Как Gradle получает ключи? (из исходного запроса)
Answer: Пароли из `android/key.properties` (в git не попадает), `signingConfig` на flavor, из `buildTypes.release` debug-подпись убрать.
Decision: `signingConfig` задаётся в блоке каждого flavor'а; `buildTypes.release` свой `signingConfig` не задаёт.
Constraints:
- `buildTypes.release` не ссылается на debug-подпись: подпись buildType перебивает подпись flavor'а.

## L6
Status: current
Question: Что делает release-сборка, если `android/key.properties` нет?
Answer: Подписывается debug-ключом с предупреждением.
Decision: При отсутствии файла или ключей конкретного flavor'а release этого flavor'а подписывается debug-ключом, Gradle печатает предупреждение. Защита от загрузки такой сборки — проверка сертификата в release-workflow.
Constraints:
- Отсутствие ключей не роняет сборку.

## L7
Status: current
Question: Когда запускается release-workflow?
Answer: Вручную.
Decision: Единственный триггер — `workflow_dispatch`.
Constraints:
- Нет запуска по push, по тегу, по расписанию.

## L8
Status: current
Question: Откуда берётся `versionCode`?
Answer: Номер запуска CI.
Decision: Release-workflow передаёт `--build-number=${{ github.run_number }}`; `versionName` остаётся из `pubspec.yaml`.
