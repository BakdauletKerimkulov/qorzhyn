#!/usr/bin/env bash
# Локальная release-сборка бизнес-приложения (Qorzhyn Business).
#
# См. scripts/build-client-apk.sh — то же самое для второго flavor'а, со своим
# upload-ключом business.
# Бизнес-консоль (web) собирается иначе:
#   flutter build web --release -t lib/main_business.dart
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter build apk --release -t lib/main_business.dart --flavor business "$@"
