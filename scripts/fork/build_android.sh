#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if [[ ! -f android/key.properties ]]; then
  echo "Release signing is required; see docs/fork/RELEASING.md." >&2
  exit 1
fi

flutter --version --machine | python3 -c '
import json, sys
sdk = json.load(sys.stdin)
if sdk.get("frameworkVersion") != "3.47.1" or sdk.get("frameworkRevision") != "6655482ec06e547f90abf8ae7590466f4415978d":
    sys.exit("Use the pinned Flutter 3.47.1 SDK; see the upstream setup-flutter-git action.")
'

flutter pub get --enforce-lockfile --no-example
flutter build apk --release \
  --dart-define=ENABLE_UPDATE_CHECK=true \
  --dart-define=UPDATE_REPOSITORY=Vexilyze/plezy \
  --dart-define=VEXILYZE_BUILD=true \
  --dart-define=ENABLE_SENTRY=false \
  --dart-define=ENABLE_DONATIONS=false \
  --dart-define="GIT_COMMIT=$(git rev-parse HEAD)"

python3 scripts/fork/package_android.py
