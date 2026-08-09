# F-Droid submission — Aurora Download Manager

How this repo gets into F-Droid, and the exact metadata used. The submission
itself is a merge request to `fdroid/fdroiddata` on GitLab (fork it, add
`metadata/com.personal.aurora_downloader.yml`, open the MR).

## Submission queue / request-for-packaging

Optional first step: open an issue at https://gitlab.com/fdroid/rfp/issues
for the automated fdroid-bot scan. The real submission is the MR below (the
RFP template itself says to open a merge request instead).

## Prerequisites (all already in this repo)

- Public repo with real source: https://github.com/52191314/Aurora_Download_Manager
- GPL-3.0 LICENSE + SPDX declaration in pubspec.yaml
- Fastlane metadata: `fastlane/metadata/android/en-US/` (short/full description,
  changelogs/54.txt, images/icon.png)
- NOTICE file documenting the vendored/prebuilt native components
- Version tag on the release commit: `v1.0.1` (points at 59ae558c)

## Metadata file — `metadata/com.personal.aurora_downloader.yml`

Paste this into the file in the fdroiddata fork:

```yaml
Categories:
  - Internet
License: GPL-3.0-only
AuthorName: Mengsean Cheang
AuthorEmail: xianspired@gmail.com
SourceCode: https://github.com/52191314/Aurora_Download_Manager
IssueTracker: https://github.com/52191314/Aurora_Download_Manager/issues
Donate: https://ahjie521.store/donation
AutoName: Aurora Download Manager

RepoType: git
Repo: https://github.com/52191314/Aurora_Download_Manager.git

Builds:
  - versionName: 1.0.1
    versionCode: 54
    commit: 90a0aea4664ed458b8edc0e0c8af42467f4d7a05
    srclibs:
      - flutter@stable
    output: build/app/outputs/flutter-apk/app-release.apk
    rm:
      - ios
    prebuild:
      - export PUB_CACHE=$(pwd)/.pub-cache
      - .flutter/bin/flutter config --no-analytics
      - .flutter/bin/flutter pub get
    scanignore:
      - .flutter/bin/cache
    scandelete:
      - .flutter
      - .pub-cache
    build:
      - .flutter/bin/flutter build apk --release

AutoUpdateMode: Version
UpdateCheckMode: Tags
UpdateCheckData: pubspec.yaml|version:\s.+\+(\d+)|.|version:\s(.+)\+
CurrentVersion: 1.0.1
CurrentVersionCode: 54
```

Notes for reviewers / known points:
- The build commit is the current OSS HEAD: it includes the in-app donation
  section (Settings → Support development → donation page opens the system
  browser via ACTION_VIEW), the backup restore of browser tabs live beside
  the current tab, and the website donation page. Everything the fastlane
  listing advertises is in this build.
- Flutter is provided via the `flutter@stable` srclib (no submodule); the app
  requires Dart `^3.8.1`, which stable Flutter satisfies. If a future stable
  Flutter's Gradle plugin demands Gradle > 8.12, bump
  `android/gradle/wrapper/gradle-wrapper.properties` to 8.14 (planned).
- libtorrent comes from the `libtorrent_flutter` pub package (v1.9.1). Its
  Gradle plugin downloads prebuilt `.so` files from the plugin's GitHub
  releases during the build; if that download fails it falls back to a
  CMake-from-source build of libtorrent + boost (slow but self-contained).
  The 16 KB-aligned copies in `tooling/torrent_16k/` are vendored for the
  Play AAB build only and are tracked with a NOTICE; F-Droid does not need
  them. NOTICE documents all vendored/prebuilt native components.
- ffmpeg-kit-min-gpl (GPL) and media_kit libs are resolved from Maven Central
  / the tracked forks; NOTICE documents their licenses.
- The release APK is debug-signed (no keystore in the repo) — F-Droid
  re-signs; `AllowedAPKSigningKeys` intentionally absent (not a reproducible
  build yet).
- Known follow-up: ABI split (arm64-v8a + armeabi-v7a blocks with
  `VercodeOperation`) to shrink the ~146 MB fat APK — not required for the
  first inclusion.

## MR description

```
New app: Aurora Download Manager (com.personal.aurora_downloader)

Open-source edition of a browser + multi-protocol download manager
(segmented HTTP, HLS/DASH, BitTorrent). GPL-3.0-only, zero proprietary
components, fully unlocked (no purchases).

- Fastlane metadata, NOTICE, and v1.0.1 tag are in the upstream repo.
- Flutter via flutter@stable srclib; Dart ^3.8.1.
- Build recipe follows templates/build-flutter.yml.
```

## Release flow (future versions)

1. Bump `version:` in pubspec.yaml (and the About page string).
2. Commit; tag `v<versionName>` (e.g. `v1.1.0`).
3. Push tag — F-Droid auto-update (AutoUpdateMode: Version + UpdateCheckMode:
   Tags) picks it up; no metadata change needed unless the build recipe
   changes.
