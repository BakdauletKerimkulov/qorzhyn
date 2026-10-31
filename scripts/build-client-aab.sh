#!/usr/bin/env bash
# Release AAB клиентского приложения (Qorzhyn) для Google Play.
#
# Подпись — upload-ключом client из android/key.properties; без него — debug-
# ключом с предупреждением (спека 051). Локальный AAB — для проверки подписи:
# в Play загружаются только артефакты release-workflow.
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter build appbundle --release -t lib/main_client.dart --flavor client "$@"
