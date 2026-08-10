#!/usr/bin/env bash
# F-Droid prebuild helper: strip PlayStoreDeferredComponentManager (outer AND
# inner classes) from the cached Flutter engine jar(s).
#
# Why: these classes are dead code in this OSS build (no Play dynamic
# features / deferred components), but their com.google.android.play.core.*
# references trip F-Droid's non-free scanner ("check apk"). The inner classes
# ($1, $FeatureInstallStateUpdatedListener) implement/extend play.core types,
# so an exact-name strip is not enough — remove them all with a wildcard.
# R8 then never sees the play.core references and the dex ships clean.
#
# The recipe calls this as `bash tooling/strip_engine_playcore.sh [flutter_root]`
# — a short prebuild line that also satisfies fdroid rewritemeta's canonical
# formatting (a long inline find/zip line gets rewrapped and fails the check).
#
# [flutter_root]: the Flutter SDK checkout root. Defaults to `.flutter` (the
# classic srclib symlink layout). The templates/build-flutter.yml layout moves
# the repo (mv dance) which breaks a relative `.flutter` symlink — the recipe
# passes `$$flutter$$` (the absolute srclib path) there.
set -eu

flutter_root="${1:-.flutter}"

for jar in $(find "$flutter_root/bin/cache/artifacts/engine" -name "flutter.jar" 2>/dev/null); do
  zip -q -d "$jar" \
    'io/flutter/embedding/engine/deferredcomponents/PlayStoreDeferredComponentManager*.class' \
    || true
done
