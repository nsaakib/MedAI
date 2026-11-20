#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
medai_backup="$(mktemp -d)"
cp -R lib test pubspec.yaml analysis_options.yaml "$medai_backup/"
restore_sources() {
  for medai_item in lib test pubspec.yaml analysis_options.yaml; do
    rm -rf "$medai_item"
    cp -R "$medai_backup/$medai_item" .
  done
  rm -rf "$medai_backup"
}
trap restore_sources EXIT
flutter create --project-name med_ai --platforms=android,ios,web .
restore_sources
trap - EXIT
flutter pub get
printf '%s\n' 'Ready. Run flutter analyze, flutter test, then flutter run -d chrome.'
