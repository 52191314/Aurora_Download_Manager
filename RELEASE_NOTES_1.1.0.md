# Aurora Downloader OSS 1.0.2 Release Notes

**Build Version**: 1.0.2+55  
**Release Date**: August 10, 2026  
**Build Channel**: GitHub Open-Source Edition (`AURORA_BUILD_CHANNEL=github`)

## Build 55 - Duplicate Download Dialog System & 100% French Localization

### WinRAR-Style Duplicate Download Handling
- **Redesigned Options**: Replaced the old dialog options with a clear WinRAR-inspired action set: **Skip** (do nothing), **Replace** (cancel and remove existing task before adding fresh), and **Create New** (add as a separate download alongside).
- **"Apply to all duplicates" Checkbox**: Batch downloads (listing page crawl, caught-media multi-select, series grab) show a checkbox to apply the chosen duplicate action to all subsequent duplicates in the batch.
- **Direct Batch Enqueuing**: Multi-select downloads from the caught-media bottom sheet (`SniffedMediaSheet`) stream directly to the download queue using a shared `DuplicatePolicy`, eliminating the per-item `AddQueueDialog` popup loop.

### Complete French (Français) Localization
- **100% Full French Translation**: Audited and translated all 194 remaining untranslated French keys into natural, native French across all screens, subpages, settings sections, option descriptions, onboarding tour steps, tools menus, and dialogs.
- **11-Language Parity**: French localization now achieves full parity with English, Simplified Chinese, Japanese, German, Spanish, Portuguese, Russian, Hindi, Arabic, and Indonesian.
