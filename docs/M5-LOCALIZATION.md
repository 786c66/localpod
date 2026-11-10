# M5 Localization (Simplified Chinese + English)

## Outcome

LocalPod now ships two UI languages:

- **zh-Hans** — Simplified Chinese, the development/source language. Existing
  behavior and all pre-M5 UI tests are unchanged.
- **en** — English UI, including app screens and LocalPodKit-sourced display
  names and user-facing error messages.

The language follows iOS Settings (Settings → General → Language & Region, or
the per-app language picker on iOS 18+). There is no in-app language switch.

`CFBundleDisplayName` remains `LocalPod`. Document type names (`Audio`, `Movie`,
`Folder`) were already English and are not localized.

## Mechanism

### App target (`LocalPod`)

- `LocalPod/Resources/en.lproj/Localizable.strings`
- `LocalPod/Resources/zh-Hans.lproj/Localizable.strings`
- Source language: `zh-Hans` (`options.developmentLanguage` and
  `CFBundleDevelopmentRegion` in `project.yml`).
- `CFBundleLocalizations` lists `en` and `zh-Hans`; XcodeGen derives
  `knownRegions` from the `.lproj` folders (verified in the generated
  `project.pbxproj`).

SwiftUI literals (`Text`, `Label`, `Button`, `Section`, `navigationTitle`,
`alert`, `accessibilityLabel/Hint/Value`, etc.) use the Chinese source text as
the lookup key. The English table maps each exact compiler-generated key to
English. Interpolated keys keep the compiler's format specifiers (`%lld`, `%@`)
and use positional values in both tables, so a missing or reordered argument
cannot silently shift a value.

Strings assembled in Swift (errors, summaries, alert titles, notification
content, computed labels) use `LocalPod/Support/L10n.swift` with semantic keys
such as `error.import.stageFailed` or `settings.samples.deleted`. `L10n.format`
uses `String(format:locale:)`, so placeholders are explicit.

### LocalPodKit

- `LocalPodKit/Sources/LocalPodKit/Resources/en.lproj/Localizable.strings`
- `LocalPodKit/Sources/LocalPodKit/Resources/zh-Hans.lproj/Localizable.strings`
- `Package.swift` declares `defaultLocalization: "zh-Hans"` and processes the
  resources into `LocalPodKit_LocalPodKit.bundle`.
- `LocalPodLocalization.string/format` resolves against `Bundle.module`.
  Display-name and status properties keep their existing zero-argument API and
  add a locale-explicit overload:

  ```swift
  MediaSource.sample.displayName                     // process language
  MediaSource.sample.displayName(locale: Locale(identifier: "en")) // "Sample"
  ImportPhase.scanning.displayName(locale: ...)
  PlaybackPhase.playing.statusText(locale: ...)
  QueueRepeatMode.off.displayName(locale: ...)
  SleepTimer.Mode.minutes(5).displayName(locale: ...)
  ```

  The explicit-locale path resolves the matching `.lproj` bundle directly,
  because Foundation's `String(localized:locale:)` may still use the process
  preferred localization for table lookup. This keeps `swift test` independent
  of the host Mac's language.
- `ImportEngine.Options.locale` lets tests request deterministic issue
  messages; `nil` (the app default) follows the process language.

### Key counts

| Table | Keys |
| --- | --- |
| App extracted SwiftUI/format keys | 290 |
| App semantic keys (`L10n`) | 112 |
| **App total per language** | **402** |
| **LocalPodKit total per language** | **77** |

The app files are generated from compiler-emitted `.stringsdata` with
`xcstringstool sync`; `Tools/generate_localization.py` owns the translation
mapping and writes both `.strings` files. To refresh after changing UI text:

```bash
# 1. Build the Debug app (SWIFT_EMIT_LOC_STRINGS is already enabled).
xcodebuild build -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -derivedDataPath /tmp/lp-dd

# 2. Merge compiler keys into a scratch catalog.
mkdir -p /tmp/lp-sync && printf '{"sourceLanguage":"zh-Hans","strings":{},"version":"1.0"}' \
  > /tmp/lp-sync/Localizable.xcstrings
xcrun xcstringstool sync /tmp/lp-sync/Localizable.xcstrings \
  --stringsdata $(find /tmp/lp-dd/Build/Intermediates.noindex/LocalPod.build \
  -name '*.stringsdata' | tr '\n' ' ')

# 3. Translate new keys in Tools/generate_localization.py, then regenerate.
python3 -I Tools/generate_localization.py /tmp/lp-sync/Localizable.xcstrings
xcodegen generate
```

## Coverage

Localized:

- Onboarding (hero, features, buttons, hints)
- Tab bar: Library / Import / Playback / Inbox / Diagnostics
- Library stats, search, filters, sorts, empty states, item detail, delete
  alert, queue/playlist feedback, collection screens, durations
- Import: sample add, folder picker, demo/acceptance buttons, progress, cancel,
  errors, categorized result, report sheet
- Inbox: counts, stability, quarantine, retry, empty state, Finder/Open-In
  instructions, paths
- Playback: empty state, status phase, transport labels/hints, slider, speed,
  sleep timer, queue actions, repeat-mode values
- Playlists: empty state, create/rename alerts, counts, delete, reorder actions
- Settings: playback, signing reminder, storage maintenance, sample delete,
  import history, about
- Diagnostics: signing banner/status, maintenance summary, app/device/data,
  paths, copy-diagnostics text
- Signing reminder local notification title/body
- LocalPodKit: `MediaSource`, `MediaKind`, `ImportPhase`, `ImportIssueKind`,
  `QueueRepeatMode`, `PlaybackPhase`, `SleepTimer.Mode`, playlist default name,
  single-file collection fallback, and all package-generated user-facing error
  messages (storage, probing, iCloud download, scanning, copying, import issues,
  maintenance, playback, audio session).

Not translated by design:

- **User content**: file names, media titles, folder/collection names,
  playlist names, user input, and paths.
- **Built-in sample data**: the collection name `示例内容` and sample file names
  (`01 欢迎使用.m4a`, etc.) are persisted user data created by an earlier
  version. They stay Chinese even in English mode; only the source label
  (`MediaSource.sample`) becomes `Sample`.
- **Internal identifiers and report values**: `RunKind.rawValue`,
  `MediaSource.rawValue`, JSON report `kind` values, `UserDefaults` keys,
  bundle IDs, Team/App ID, file-system paths.
- **Comments, logs, assertions, and `fatalError` messages**.
- **Debug-only fixtures**: `M3DebugSeed` titles/folder names, the 5,000-row
  stress seed in `RootView`, and the fake provisioning-profile name
  `UI 测试描述文件` in `SigningInfo`.
- **App name** `LocalPod` and document type names `Audio`/`Movie`/`Folder`
  (already English).

No user-visible Chinese literals remain in English-mode release paths other
than the sample user data listed above. The debug fixtures above are reachable
only through Debug launch arguments or a debug signing seam.

## Tests

UI tests are pinned explicitly, because the simulator's system language is
English:

- All pre-existing suites (`M0`–`M5`, delivery, signing, performance) call
  `launchPinned()`, which appends `-AppleLanguages (zh-Hans)` and
  `-AppleLocale zh_CN` at every `XCUIApplication` launch, including inline
  relaunches.
- Two import timing tests were made robust: `testImport100Files` waits for
  the completed summary and still asserts `导入 100`, because the progress row
  is transient and can be off screen once the run finishes; progress and
  cancellation UI remain covered by the M1 slow-copy tests.
  `testCancelDuringSlowImport` scrolls to the cancel button, and the
  Debug-only `--m1-slow-copy` delay is 150 ms so cancellation stays
  observable on fast simulators. Both still run under pinned zh-Hans.
- `LocalPodUITests/M5LocalizationUITests.swift` launches with
  `-AppleLanguages (en)` / `-AppleLocale en_US` and checks:
  1. English onboarding + all five English tab labels.
  2. English Settings, transport/accessibility labels, LocalPodKit repeat-mode
     value, and playback phase.
  3. English sample import summary, `Sample` source name from LocalPodKit, and
     preservation of the Chinese `示例内容` collection name as user data.

Commands and results (iOS 27.1 simulator, iPhone Duo):

```bash
cd LocalPodKit && swift test
# 128 tests, 0 failures (9.388 s)

xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=3055696C-BC73-4190-A3F7-EE0AC55F1EE6' \
  -only-testing:LocalPodUITests
# 40 tests, 0 failures (1042.2 s; 37 pre-existing + 3 localization)
```

Localization-specific results:

- `M5LocalizationUITests`: 3 tests, 0 failures (54.4 s).
- `M5UITests` + `M5DeliveryUITests` + `M5SigningUITests` under pinned
  zh-Hans: 12 tests, 0 failures (~225 s).
- Full `LocalPodUITests` run: 40 tests, 0 failures (1042.2 s), including
  `M5PerformanceTests` (2 tests, simulator measurements only).

Debug simulator and device-architecture compilation both succeeded:

```bash
xcodebuild -project LocalPod.xcodeproj -scheme LocalPod -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# ** BUILD SUCCEEDED **
xcodebuild -project LocalPod.xcodeproj -scheme LocalPod -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
# ** BUILD SUCCEEDED **
```

The built `Debug-iphonesimulator` and `Debug-iphoneos` apps contain
`en.lproj`, `zh-Hans.lproj`, and `LocalPodKit_LocalPodKit.bundle` with both
tables; `plutil` shows English values such as `Welcome to LocalPod`,
`Playback Progress`, and `source.sample = Sample`. This proves compilation and
resource packaging only; real-device language switching was not run and is not
claimed as passed.

## Adding a language

1. Add `LocalPod/Resources/<lang>.lproj/Localizable.strings` and
   `LocalPodKit/Sources/LocalPodKit/Resources/<lang>.lproj/Localizable.strings`
   with every key translated (format specifiers must match).
2. Add the language to `CFBundleLocalizations` in `project.yml`.
3. Run `xcodegen generate` and confirm `knownRegions` contains the language.
4. Add a locale-explicit unit test for LocalPodKit display names/messages.
5. Add or extend a UI test launched with `-AppleLanguages (<lang>)` and
   `-AppleLocale <region>`.

## Limitations / follow-ups

- No RTL language was tested; layouts may need mirroring work.
- No pluralization variants (`.stringsdict` / String Catalog plural rules);
  strings use neutral "N items" wording.
- No in-app language picker; iOS Settings controls the language. Per-app
  language selection is an OS feature.
- Dates and byte counts rely on system locale formatting; no custom date
  patterns were added.
- The built-in sample collection/file names remain Chinese as user data.
- Real-device language switching, RTL, and App Store localization metadata
  (screenshots/descriptions) were not verified.
