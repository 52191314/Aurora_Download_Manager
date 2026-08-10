# Aurora Downloader 1.1.0 (68) — Release Notes

Open-source (F-Droid / GitHub) edition.

## What's new in 1.1.0 (68)

- **Per-ABI release APKs (ABI split)**: release builds are now split per CPU
  architecture — `arm64-v8a` and `armeabi-v7a` — instead of one fat APK
  containing both. Each download is roughly half the size (~70 MB arm64 /
  ~80 MB 32-bit vs ~146 MB fat). The F-Droid recipe builds both splits and
  serves each device the right one; GitHub Releases carries both APKs.
- **Distinct versionCodes per ABI**: `versionCode * 10 + 1` for armeabi-v7a,
  `versionCode * 10 + 2` for arm64-v8a (Flac-R precedent, merged in
  fdroiddata). 1.1.0 ships as 681 (v7a) / 682 (arm64); the scheme keeps
  F-Droid clients upgrading to the highest installable code.
- **Reproducible-build enablement (F-Droid)**: the fdroiddata recipe now
  carries per-ABI `binary:` references to the Linux-built GitHub release
  assets plus `AllowedAPKSigningKeys`, so the F-Droid pipeline byte-compares
  its builds against the official ones.
- **Ported from the Play edition**: WinRAR-style duplicate download handling,
  batch download directly in the capture sheet (DuplicatePolicy), and 100%
  French localization — the OSS edition now tracks the Play build line
  (1.1.0+68).
- Build: 1.1.0+68, github channel. The fat APK path remains available for
  sideloading (versionCode 68, no ABI filter applied).

## Notes

- The video/torrent engine payload is unchanged (~30 MB mpv/FFmpeg + ~12 MB
  libtorrent per ABI) — the split reduces *download size per user*, not the
  native footprint.
