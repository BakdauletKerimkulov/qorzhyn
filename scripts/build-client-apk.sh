#!/usr/bin/env bash
# Локальная release-сборка клиентского APK (Qorzhyn).
#
# Обёртка существует ровно для того, чтобы не держать -t и --flavor в голове:
# дефолтного target'а в проекте нет, а без --flavor Gradle не найдёт
# assembleRelease. Подпись — upload-ключом client из android/key.properties;
# без него — debug-ключом с предупреждением (спека 051). APK — для локального
# QA; в Google Play загружаются только AAB-артефакты release-workflow.
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter build apk --release -t lib/main_client.dart --flavor client "$@"
