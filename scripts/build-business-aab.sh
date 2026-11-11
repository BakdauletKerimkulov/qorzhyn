#!/usr/bin/env bash
# Release AAB бизнес-приложения (Qorzhyn Business) для Google Play.
#
# См. scripts/build-client-aab.sh — то же самое для второго flavor'а, со своим
# upload-ключом business.
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter build appbundle --release -t lib/main_business.dart --flavor business "$@"
