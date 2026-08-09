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
# The recipe calls this as `bash tooling/strip_engine_playcore.sh` — a short
# prebuild line that also satisfies fdroid rewritemeta's canonical formatting
# (a long inline find/zip line gets rewrapped and fails the check).
set -eu

for jar in $(find .flutter/bin/cache/artifacts/engine -name "flutter.jar" 2>/dev/null); do
  zip -q -d "$jar" \
    'io/flutter/embedding/engine/deferredcomponents/PlayStoreDeferredComponentManager*.class' \
    || true
done
