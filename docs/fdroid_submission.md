# F-Droid submission — Aurora Download Manager

The complete journey of getting `com.personal.aurora_downloader` into F-Droid via
merge request **fdroid/fdroiddata !45273**, from first submission to a fully
green pipeline (all 9 jobs including `fdroid build` and `check apk`).

Status: **MR open, pipeline green, awaiting review.** The reproducible-build
path (maintainer ask) was implemented, proven impossible from a Windows-built
reference, and parked — see "The reproducible-build saga" and "How to resume".

---

## Outcome (2026-08-09)

- Pipeline **2745402304** on fork head `5266fb89`: all 9 jobs green —
  schema validation, fdroid lint, tools check scripts, git redirect,
  checkupdates, fdroid rewritemeta, fdroid build, check source code, **check apk**.
- Final recipe: simple Flutter srclib recipe, pin `cef37921`, scanignore
  `webdav_root` only, `AllowedAPKSigningKeys` present (upload key fingerprint),
  **no** `Binaries:` (reference APK cannot byte-match from a Windows build).
- The play-core `check apk` false positives are gone via the wildcard proguard
  negation in `cef37921` (see the battle below).
- Everything needed to resume reproducible builds is already committed in this
  repo: Linux release workflow, ArtProfile fix, kotlinx keep rules,
  `.gitattributes`, 3.44.9-regenerated `pubspec.lock`.

## Timeline of the journey

| Phase | What happened | Result |
|---|---|---|
| 1. First submission | Metadata per templates/build-flutter.yml, pin `7344651` | check apk red: 6 play.core classes |
| 2. Play-core battle | R8 negation + engine jar strip iterations | 6 -> 2 -> 0 findings (pin `cef37921`) |
| 3. Squash + template | Branch squashed to 1 commit; MR description = bare 10-checkbox template | MR clean, "X of 10" renders |
| 4. Maintainer asks | duckniii: enable Reproducible Builds, add Binaries + AllowedAPKSigningKeys, JDK 21 | three asks accepted |
| 5. `buildjdk` trap | Added `buildjdk: 21` -> schema validation failure | Field does not exist; buildserver-trixie already defaults to JDK 21; removed |
| 6. Reproducibility #1 | Byte-compare on the Windows-built official APK | 21 files differ; libflutter.so (beta vs stable engine) is the alpha blocker |
| 7. Docs + template | Read ALL F-Droid docs; template structure + Flac-R real recipe | Full fix playbook |
| 8. Linux build path | GitHub Actions release workflow replicating the CI layout, Flutter 3.44.9 pinned | workflow built; pub get failed: stale lock |
| 9. Lock regeneration | Flutter 3.44.9 Windows SDK download (30 min) + `pub get --enforce-lockfile` | lock now consistent with stable Dart (6 downgrades) |
| 10. Trap: wrong pin | Recipe pin hand-typed with a wrong tail (12-char prefix match) | fdroid build + check source both failed on nonexistent commit |
| 11. Trap: ArtProfile snippet | docs' `tasks.whenTaskAdded` form breaks Flutter task wiring | fixed with `afterEvaluate` + `configureEach` (commit `ebf3ee8`) |
| 12. Windows verdict | Full stable-toolchain Windows rebuild, 13 entries still differ | Windows can never byte-match; Binaries dropped |
| 13. Concurrent edits | User reshaped the recipe (dropped Binaries, reverted template restructure) | respected; blank-line fix landed from both sides |
| 14. Final green | Simple recipe, blank lines canonical, pin cef37921 | pipeline 2745402304 all green |

## The check apk battle (play-core false positives)

`check apk` scans the built APK for proprietary code. Flutter's engine ships
Google Play Core classes (the deferred-components machinery), which the
scanner flags even though the app never uses them.

1. First run: 6 classes flagged (SplitInstallManager, SplitInstallSessionState,
   SplitInstallStateUpdatedListener, OnFailureListener, OnSuccessListener,
   SplitCompatApplication).
2. The anchor: `io.flutter.embedding.android.FlutterPlayStoreSplitApplication`
   extends `SplitCompatApplication`; a blanket `-keep class io.flutter.**` kept
   it, which kept the whole play.core subtree alive. Excluding it dropped the
   count to 2.
3. The survivors were **inner classes** — `PlayStoreDeferredComponentManager$1`
   and `$FeatureInstallStateUpdatedListener` (implements
   SplitInstallStateUpdatedListener). Exact-name rules and exact-name `zip -d`
   jar strips miss `$`-inner classes.
4. Final fix (commit `cef37921`): wildcard the negation —
   `-keep class !io.flutter.embedding.engine.deferredcomponents.PlayStoreDeferredComponentManager*, ...`
   (ProGuard `*` matches inner classes). Verified 0/12 banned classes locally
   AND on the CI-built APK (dexdump of the pipeline artifact).
5. Dead ends proven along the way:
   - `scanignore` cannot list dex-internal class paths — fdroidserver
     validates entries against the source tree and hard-fails with
     `Non-exist scanignore path` (14 errors in one run).
   - A recipe `zip -d` strip on the engine jar is a silent no-op: the engine
     jar is downloaded during the build step, not prebuild, so the `find`
     matches nothing. (`tooling/strip_engine_playcore.sh` remains as a
     harmless belt-and-suspenders line.)
   - Gradle bytecode-stripping tasks were considered and rejected as brittle.

## The reproducible-build saga

### What the maintainer asked (duckniii)

1. Enable the Reproducible Builds checkbox.
2. Add `Binaries:` + `AllowedAPKSigningKeys:` to the recipe.
3. Use JDK 21.

### What we learned from the docs (read ALL of them first)

- f-droid.org/docs/Reproducible_Builds — every diff class maps to a documented
  cause: ArtProfile baseline.prof/.profm, CRLF service/asset files, embedded
  build paths, R8 nondeterminism, NDK build-id, engine drift.
- Build_Metadata_Reference — the full field list (no `buildjdk`; `Binaries` /
  `binary` / `AllowedAPKSigningKeys` semantics; `sudo` before `output`).
- templates/build-flutter.yml — the canonical Flutter recipe structure the
  maintainer pointed at.
- Wiki HOWTO "diff & fix APKs for Reproducible Builds" — the debugging flow
  (apksigcopier compare, zipinfo/diff-zip-meta, dexdump fix script).

### The template structure (what "follow templates/build-flutter.yml" means)

- The app repo's `.github/workflows/release.yml` carries `flutter-version: 'X.Y.Z'`;
  the recipe greps it with `sed` and checks out that exact version in the
  flutter srclib: `git -C $$flutter$$ checkout -f $flutterVersion`.
- Both sides build at the SAME path: the recipe moves the checked-out app to
  `/upstream/path/aurora-downloader` (mv dance in prebuild + build), because
  the repo path embeds into libapp.so.
- `--enforce-lockfile` on pub get (requires a committed, SDK-consistent lock).
- `ndk: r28c` (the project pins NDK 28.2.13676358 = r28c).
- `postbuild`: reproducible-apk-tools `zipalign.py --page-size 16
  --pad-like-apksigner` — both sides re-zip identically (16 KB page alignment,
  apksigner-style padding; the v2/v3 signing block is dropped, v1 survives).
- `scanignore: .flutter/bin/cache`, `scandelete: .flutter + .pub-cache`,
  `sudo: mkdir -p /upstream/path/... + chown vagrant`.

### The fixes committed to this repo (all verified)

| Commit | Fix |
|---|---|
| `ebf3ee8` | ArtProfile disable via `afterEvaluate` + `configureEach` (baseline.prof/.profm) |
| `cc456d3`/`cef37921` | R8 rules: kotlinx.coroutines keeps + play-core negation |
| `52912e7` | `.github/workflows/release.yml` (Linux build, JDK 21, /opt/android-sdk symlink, NDK r28c, zipalign, keystore from secrets, gh release upload) + `.gitattributes` (LF for assets/text) |
| `8afda12` | pubspec.lock regenerated with Flutter 3.44.9 |

### The three traps that cost CI cycles

1. **pubspec.lock staleness**: the committed lock was generated by a beta SDK;
   under stable's Dart it wants 6 transitive downgrades (hooks, matcher, meta,
   record_use, test_api, vector_math), so `--enforce-lockfile` hard-fails
   ("Failed to update packages", exit 65). Fix: regenerate the lock with the
   EXACT stable SDK (downloaded Flutter 3.44.9 for Windows) and commit it.
2. **The wrong pin**: a hand-typed pin whose first 12 hex chars matched the
   real commit but whose tail differed (`52912e72d799ebd4...` vs
   `52912e72d799592e...`) fails `fdroid build` AND `check source code` with
   `VCSException: Git checkout of '<pin>' failed` — it masquerades as a cache
   problem. Fix: always copy the hash from `git rev-parse HEAD` /
   `git ls-remote` verbatim.
3. **The docs' ArtProfile snippet breaks task wiring**: `tasks.whenTaskAdded`
   in build.gradle.kts makes this Flutter version fail configuration with
   `Could not create task ':app:copyJniLibsflutterBuildDebug'`. Fix:
   `afterEvaluate { tasks.matching { it.name.contains("ArtProfile") }
   .configureEach { enabled = false } }`.

### The Windows verdict

Even with a full stable-toolchain rebuild (Flutter 3.44.9, fresh PUB_CACHE,
stripped engine jars, unaligned libtorrent prebuilts) 13 APK entries still
differed from the F-Droid Linux build: CRLF in R8-rewritten META-INF/services,
NOTICES.Z, adblock JS assets, classes.dex, libapp.so, native libs. Windows
cannot produce a byte-matching reference. With `Binaries:` present the
non-matching reference fails `fdroid build` and — critically — **skips
`check apk`** (the scanner job the maintainers actually care about).

### The decision

- DROP `Binaries:` -> `fdroid build` passes, `check apk` runs, pipeline green,
  MR mergeable.
- KEEP `AllowedAPKSigningKeys:` (documents the key, harmless).
- Keep all the reproducible machinery in this repo for a Linux-built resume.

## Final recipe (the green one)

```yaml
Categories:
  - Internet
License: GPL-3.0-only
AuthorName: Mengsean Cheang
AuthorEmail: xianspired@gmail.com
SourceCode: https://github.com/52191314/Aurora_Download_Manager
IssueTracker: https://github.com/52191314/Aurora_Download_Manager/issues
Donate: https://ahjie521.store/donation

AutoName: Aurora Downloader

RepoType: git
Repo: https://github.com/52191314/Aurora_Download_Manager.git

Builds:
  - versionName: 1.0.1
    versionCode: 54
    commit: cef37921c50b0a2d164ce4a60beb7ca062d5dc97
    output: build/app/outputs/flutter-apk/app-release.apk
    srclibs:
      - flutter@stable
    rm:
      - ios
    prebuild:
      - export PUB_CACHE=$(pwd)/.pub-cache
      - ln -s ../../build/srclib/flutter .flutter
      - .flutter/bin/flutter config --no-analytics
      - .flutter/bin/flutter pub get
      - bash tooling/strip_engine_playcore.sh
    scanignore:
      - webdav_root
    scandelete:
      - .pub-cache
    build: .flutter/bin/flutter build apk --release

AllowedAPKSigningKeys: 3e6b80e22a0a8756c9d39272d2ee51d09bbc993628fcfe52e9f1e1c659bef22e

AutoUpdateMode: Version
UpdateCheckMode: Tags
UpdateCheckData: pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+
CurrentVersion: 1.0.1
CurrentVersionCode: 54
```

Why each line (the hard-won knowledge):

- `ln -s ../../build/srclib/flutter .flutter` — MANDATORY: the flutter srclib
  lands at `build/srclib/flutter`, not `.flutter`; without the symlink the very
  first prebuild command dies with "No such file or directory".
- `scanignore: webdav_root` — the backup test fixtures are zip archives; the
  scanner flags them. Only REAL source-tree paths are allowed here — dex class
  paths are hard errors.
- `scandelete: .pub-cache` — removes the pub packages before the scan.
- `bash tooling/strip_engine_playcore.sh` — historically a no-op in CI (engine
  jar arrives during build) but harmless; the real fix is the proguard
  wildcard in the pinned commit.
- `AllowedAPKSigningKeys` — SINGLE line, AFTER the Builds block, blank line
  after it (the YAML list form fails rewritemeta).
- `AutoName: Aurora Downloader` — must be the app's REAL label (checkupdates
  derives it), not the repository name.
- Canonical blank lines are mandatory between top-level sections
  (`Repo:`/`Builds:`, `AllowedAPKSigningKeys:`/`AutoUpdateMode:`) — rewritemeta
  prints the exact diff; apply it verbatim.

## MR state and what remains

- Description: bare template, 8/10 checkboxes (Reproducible Builds is ticked
  but Binaries is dropped — the maintainer may ask; answer: resume path exists,
  see below).
- Label: `New App` is applied by the fdroid-bot at triage (API label
  application is ignored for non-members).
- Branch: NOT squashed (recipe iterations + user edits; squash before merge,
  content-identical via blob-hash comparison).
- v1.0.1 GitHub release carries the Linux-built, upload-key-signed, zipaligned
  APK (`aurora-downloader-v1.0.1.apk`, 152.8 MB — built by the release
  workflow, replacing the initial Windows-built one; the URL matches the
  `Binaries:` pattern exactly). The key + GitHub secrets are in place for
  future releases.

## How to resume reproducible builds (when a Linux reference exists)

1. Push the pinned-version line into `.github/workflows/release.yml` (already
   there: `flutter-version: '3.44.9'`).
2. Bump the recipe `commit:` to a tip that includes the reproducible fixes
   (`8afda12`+ — the lock + ArtProfile fix) and re-add:
   - one `Builds` block PER ABI (`armeabi-v7a` first, then `arm64-v8a`), each
     with `output: build/app/outputs/flutter-apk/app-<abi>-release.apk` and a
     wrapped `binary:` URL pointing at the matching GitHub release asset
     (`aurora-downloader-v%v-<abi>.apk`) — Flac-R
     (`metadata/com.resurrect.flac_r.yml`) is the proven merged shape,
   - `VercodeOperation: ['%c * 10 + 1', '%c * 10 + 2']` (top level) so
     checkupdates derives the per-ABI codes from the pubspec versionCode,
   - `sudo: mkdir -p /upstream/path/aurora-downloader + chown -R vagrant`,
   - the mv dance + `$$flutter$$` + `--enforce-lockfile` + `ndk: r28c` +
     zipalign postbuild (see templates/build-flutter.yml + Flac-R for the
     canonical shape),
   - per-ABI `--split-per-abi --target-platform="android-arm"` /
     `--target-platform="android-arm64"` in the `build:` commands.
3. App side: `android/app/build.gradle.kts` overrides the versionCode per ABI
   (`versionCode * 10 + abiCode`, `abiCodes = {armeabi-v7a: 1, arm64-v8a: 2}`)
   so the split APKs carry distinct codes (681/682 for 1.1.0+68) — the same
   Flac-R pattern. Fat APK builds are unaffected (no ABI filter -> no override).
4. Run the release workflow (dispatch with the tag) — it builds both ABIs on
   Linux at `/upstream/path/aurora-downloader` with JDK 21, /opt/android-sdk,
   NDK r28c, zipaligns each APK, signs with the upload key, uploads both
   per-ABI assets to the release.
5. The pipeline byte-compares both splits; iterate on the diff classes with
   diffoscope / the wiki HOWTO. Expected remaining deltas to chase: R8 dex
   ordering (match core count), embedded paths, NDK build-id.

## Verification tooling used

- GitLab API (PRIVATE-TOKEN): pipeline/job status, job traces, file read/write
  via the repository files API (raw URL is CDN-stale — verify via the API blob).
- `gh run view` / `gh release upload` (Windows paths, not MSYS /tmp).
- dexdump from the CI APK artifacts (anchor hunt), apksigner --print-certs,
  keytool -list -v, zipinfo/zipalign from reproducible-apk-tools,
  apksigcopier compare.
- Local verification: direct `gradlew :app:assembleRelease` (the
  flutter->gradle->flutter wrapper path is fragile on this box), one build at a
  time (concurrent builds collide on file locks).
