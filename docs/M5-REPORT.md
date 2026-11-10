# LocalPod M5 实施与验证报告

> 日期：2026-11-11
> 工程：`/Users/xlf/Dev/code/localpod`
> 结论：**M5「打磨与侧载交付」的代码与模拟器自动化完成。引导、空状态、无障碍标签、Dynamic Type、深色模式、简体中文/英文、示例内容、签名提醒、性能基线、安装/重签/备份文档均已落地；40 个 UI 测试与 128 个核心测试通过。连续 2 周自用、1 GB 导入、真实 VoiceOver 全流程、7 天到期重签演练、通知真实送达、真实设备备份恢复仍未在真机执行，未计为已通过。**
> 计划基线：`PLAN.md` 5.7
> 产品边界：仅音频；视频容器只导入/播放音轨；无画面、旋转、PiP；不接 StoreKit、无内购/订阅；仅 iPhone；无 App Group。

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.0.1 (26A434) |
| Xcode | 27.1 (27A9275) |
| Swift | 6.4（Swift 6 语言模式） |
| iOS SDK | 27.1 |
| 模拟器 | iOS 27.1 · iPhone Duo（UDID `3055696C-BC73-4190-A3F7-EE0AC55F1EE6`） |
| 部署目标 | iOS 17.0，仅 iPhone |
| 签名 | 模拟器 ad-hoc；真机免费账号步骤见 `docs/M0-SIGNING.md`、`docs/M5-INSTALL-RESIGN-BACKUP.md` |

## 2. M5 交付

| 交付 | 状态 | 说明 |
| --- | --- | --- |
| 引导 | 完成 | 首次启动 Sheet，说明递归文件夹导入、仅音频、免费/无内购、7 天侧载重签；`onboardingScreen`、完成/去导入/跳过按钮；`@AppStorage` 只显示一次，`--m5-show-onboarding`/`--m5-skip-onboarding` 控制测试 |
| 空状态与错误文案 | 完成 | 资料库、合集、导入历史、收件箱、播放、播放列表空状态；错误提示与重试入口；删除/维护/示例删除汇总 |
| 无障碍 | 完成（自动化范围） | 播放控制、进度滑杆、倍速、队列、睡眠定时等有标签/提示/值；Dynamic Type Accessibility XXXL 下关键控件可点击；完整 VoiceOver 走查待真机 |
| 深色模式 | 完成（自动化截图） | 使用系统语义色与深色 AccentColor；DEBUG `--m5-force-dark-appearance` 仅用于模拟器截图，Release 不生效 |
| 简体中文/英文 | 完成 | App 402 个键/语言，LocalPodKit 77 个键/语言；见 `docs/M5-LOCALIZATION.md`；用户内容不翻译 |
| 示例内容 | 完成 | 3 段自生成系统语音（11.39s/9.08s/9.18s，共 171,682 字节），走同一导入流水线，来源 `示例`/`Sample`、合集 `示例内容`；可删除并重加，跨启动去重 |
| 签名到期提醒 | 完成（送达待真机） | 诊断页剩余天数/横幅；本地通知在到期前 2 天 10:00；固定标识替换旧请求；设置开关持久化；通知授权与真实送达未在真机验证 |
| 性能 | 完成（模拟器基线） | 启动 2.473s（含每次清空数据）、5,000 行滚动减速 2.433s，无硬阈值；见 `docs/M5-PERFORMANCE.md` |
| 安装/重签/备份文档 | 完成 | `docs/M5-INSTALL-RESIGN-BACKUP.md`：容器保留/丢失条件、备份语义、重导重链、真机演练清单 |
| 测试与文档 | 完成 | 核心 128 个、UI 40 个；本报告、PLAN 勾选、README、截图 |

主要新增/修改文件：

- `LocalPod/Features/Onboarding/OnboardingView.swift`：首次引导与可访问性标识。
- `LocalPod/App/RootView.swift`：引导解析、前后台轮询、M5 调试启动参数、深色截图 seam。
- `LocalPod/Features/Settings/SettingsView.swift`：签名提醒开关、示例删除、维护摘要。
- `LocalPod/Features/Library/LibraryView.swift`、`LocalPod/Spikes/Playback/PlaybackView.swift`、`LocalPod/Spikes/Import/ImportView.swift`、`LocalPod/Spikes/Inbox/InboxView.swift`、`LocalPod/Features/Playlists/PlaylistViews.swift`：空状态、无障碍、本地化。
- `LocalPod/App/SigningReminder.swift`、`LocalPodKit/.../SigningReminderSchedule.swift`：本地通知调度与纯日期计算。
- `LocalPod/Spikes/Diagnostics/DiagnosticsView.swift`、`SigningInfo.swift`：签名横幅与 DEBUG 假到期 seam。
- `LocalPod/Resources/SampleContent/`：3 段示例音频；`ImportCoordinator.importSampleContent`、`LibraryService.deleteSamples`。
- `LocalPod/Resources/{en,zh-Hans}.lproj/Localizable.strings`、`LocalPod/Support/L10n.swift`、`LocalPodKit/.../Resources/{en,zh-Hans}.lproj/Localizable.strings`、`LocalPodKit/.../Support/Localization.swift`：本地化资源与辅助。
- 测试：`M5UITests`（7）、`M5DeliveryUITests`（3）、`M5SigningUITests`（2）、`M5PerformanceTests`（2）、`M5LocalizationUITests`（3）、`LocalizationTests`（7）、`SigningReminderScheduleTests`（6）。
- 文档：`docs/M5-LOCALIZATION.md`、`docs/M5-PERFORMANCE.md`、`docs/M5-INSTALL-RESIGN-BACKUP.md`、本报告。

## 3. 验收标准对照

| # | PLAN 5.7 验收项 | 结果 | 证据 |
| --- | --- | --- | --- |
| 1 | 连续 2 周日常使用，无 P0/P1 阻断问题 | **未执行，保持未通过** | 需要真机连续使用；本环境只做模拟器自动化 |
| 2 | 1 GB 文件夹导入达到基线；4K 视频容器仅音轨导入/播放正常 | **未执行，保持未通过** | 模拟器性能只覆盖启动/5,000 行列表；1 GB 与 4K 音轨需真机与真实文件 |
| 3 | VoiceOver 能完成“导入 → 播放 → 加队列 → 睡眠定时”；Dynamic Type 不截断 | **部分通过，整体保持未通过** | 自动化验证标签/提示/值与 XXXL 关键控件可点击（`M5UITests`）；未做真实 VoiceOver 手势全流程 |
| 4 | 在自己设备上完成一次“安装 → 7 天过期 → 重签”演练，数据仍在 | **未执行，保持未通过** | 文档与诊断横幅/开关自动化已就绪；真机过期与重签未执行 |
| 5 | 安装/重签/备份步骤写成文档，下一次不用重新查 | **通过** | `docs/M5-INSTALL-RESIGN-BACKUP.md`，含证据表与未验证项 |

> 报告只把模拟器可自动化的部分计为通过。真实通知送达、真机语言切换、RTL、VoiceOver 全流程、1 GB/4K、2 周使用与重签演练均未计为已通过。

## 4. 自动化结果

### 4.1 LocalPodKit 单元/集成测试

命令：

```bash
cd LocalPodKit
swift test
```

结果（2026-11-11 02:45）：

```text
Executed 128 tests, with 0 failures (0 unexpected) in 9.388 seconds
```

M5 新增覆盖：

- `SigningReminderScheduleTests`（6）：到期前 2 天 10:00、过去/禁用/无到期/错过触发点、固定标识替换。
- `LocalizationTests`（7）：`MediaSource`/`MediaKind`/`ImportPhase`/`ImportIssueKind`/`QueueRepeatMode`/`PlaybackPhase`/`SleepTimer.Mode` 的中英文显式 Locale，以及包内错误格式键。
- `ImportEngineTests` 新增英文 issue 文案用例；既有中文断言通过显式 `zh-Hans` Locale 保持确定性。
- 既有 M0–M4 核心测试全部保留通过。

### 4.2 UI 测试

全量命令：

```bash
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=3055696C-BC73-4190-A3F7-EE0AC55F1EE6' \
  -only-testing:LocalPodUITests
```

结果（同一次运行，iOS 27.1 模拟器，Debug）：

```text
M0UITests: 4 tests, 0 failures, 47.6 seconds
M1UITests: 5 tests, 0 failures, 91.8 seconds
M2UITests: 5 tests, 0 failures, 102.2 seconds
M3UITests: 6 tests, 0 failures, 394.9 seconds
M4UITests: 3 tests, 0 failures, 81.9 seconds
M5DeliveryUITests: 3 tests, 0 failures, 108.5 seconds
M5LocalizationUITests: 3 tests, 0 failures, 54.4 seconds
M5PerformanceTests: 2 tests, 0 failures, 44.3 seconds
M5SigningUITests: 2 tests, 0 failures, 32.5 seconds
M5UITests: 7 tests, 0 failures, 84.0 seconds
合计 40 tests, 0 failures, 1042.2 seconds
```

M5 关键用例：

| 用例 | 验证内容 |
| --- | --- |
| `M5UITests.testOnboardingShowsOnceAndContinuePersists` | 首次引导出现，继续后重启不再出现 |
| `M5UITests.testShowOnboardingLaunchArgumentForcesSheet` | 强制引导与跳过 |
| `M5UITests.testEmptyInboxAndImportStates` | 收件箱/导入空状态 |
| `M5UITests.testPlaybackEmptyStateAction` | 播放空状态与“去资料库”跳转 |
| `M5UITests.testPlaybackControlAccessibilityLabels` | 播放/队列控件中文标签、值 |
| `M5UITests.testAccessibilityXXXLControlsRemainHittable` | Accessibility XXXL 下关键控件可点击 |
| `M5UITests.testDarkModeScreenshot` | 深色模式渲染截图 |
| `M5DeliveryUITests.*`（3） | 示例导入 3 条、来源/合集、删除/重加、跨启动去重 |
| `M5SigningUITests.*`（2） | 假到期横幅、提醒开关持久化 |
| `M5LocalizationUITests.*`（3） | 英文引导/标签栏、设置/播放无障碍、示例来源 `Sample` |
| `M5PerformanceTests.*`（2） | 启动与 5,000 行滚动基线（不设阈值） |

### 4.3 截图

| 截图 | 内容 |
| --- | --- |
| `screenshots/M5-onboarding.png` | 首次引导 |
| `screenshots/M5-empty-inbox.png` | 空收件箱 |
| `screenshots/M5-accessibility-xxxl.png` | Accessibility XXXL 播放页 |
| `screenshots/M5-dark-mode.png` | 深色模式播放页 |
| `screenshots/M5-sample-import-summary.png` | 示例导入完成汇总 |
| `screenshots/M5-sample-library.png` | 示例进入资料库 |
| `screenshots/M5-sample-detail.png` | 示例来源/合集详情 |
| `screenshots/M5-sample-deleted.png` | 设置中删除示例结果 |
| `screenshots/M5-sample-readded.png` | 重新添加示例 |
| `screenshots/M5-sample-dedup-relaunch.png` | 跨启动重复导入去重 |
| `screenshots/M5-signing-expiry-banner.png` | 诊断页签名到期横幅（DEBUG 假数据） |
| `screenshots/M5-signing-toggle-enabled.png` | 签名提醒默认开启 |
| `screenshots/M5-signing-toggle-disabled.png` | 关闭提醒 |
| `screenshots/M5-signing-toggle-persisted-off.png` | 重启后关闭状态保留 |
| `screenshots/M5-localization-english-tabs.png` | 英文引导/标签栏 |
| `screenshots/M5-localization-english-settings.png` | 英文设置 |
| `screenshots/M5-localization-english-playback.png` | 英文播放/无障碍标签 |
| `screenshots/M5-localization-english-sample-detail.png` | 英文 `Sample` 来源；中文示例合集名为用户数据 |

### 4.4 构建

- 模拟器 Debug：完整 UI 测试构建与执行成功。
- 模拟器 Release：**BUILD SUCCEEDED**；Release `.app` 含 `en.lproj`、`zh-Hans.lproj` 与 `LocalPodKit_LocalPodKit.bundle`，且二进制中不存在 `--m5-force-dark-appearance`/`--m5-fake-signing-expiry-days` 调试 seam 字符串。
- `generic/platform=iOS` Debug、`CODE_SIGNING_ALLOWED=NO`：**BUILD SUCCEEDED**（仅 AppIntents 元数据警告；无 App Group/entitlements）。
- Debug 模拟器 `.app` 与设备架构 `.app` 均包含 `en.lproj`、`zh-Hans.lproj` 与 `LocalPodKit_LocalPodKit.bundle`（`docs/M5-LOCALIZATION.md`）。

## 5. 关键实现说明

- **引导**：`@AppStorage("localpod.onboarding.completed")`；首次启动 Sheet，继续/跳过/去导入均标记完成，滑动关闭也标记完成；`--m0-reset-data` 会标记完成，避免打断既有 UI 测试。
- **无障碍**：播放控制使用显式 label/hint/value；进度滑杆有值；倍速/队列/睡眠定时可操作；大字号下使用 `ViewThatFits`/横向滚动/换行；XXXL 测试验证可点击，不等同于完整 VoiceOver 走查。
- **深色模式**：使用语义色与 `AccentColor` 深色变体；模拟器 trait 传播问题用 DEBUG-only `--m5-force-dark-appearance` 截图，Release 不强制颜色方案。
- **示例内容**：内置 3 段自生成 TTS，复制进沙盒并走正常导入/去重/进度/报告；来源 `.sample` 显示“示例”/“Sample”；合集 `示例内容` 与文件名作为用户数据保留中文；删除级联清理进度、队列、播放列表引用和媒体/封面。
- **签名提醒**：`SigningReminderSchedule` 纯日期计算（到期日减 2 天、10:00 本地、固定标识 `localpod.signing.expiry`）；`SigningReminder` 只使用本地 `UNCalendarNotificationTrigger`，无 Push entitlement/App Group；启动只读取授权状态，不弹权限框；开关从关到开才请求授权，关闭取消待发送请求。诊断横幅始终兜底。
- **本地化**：SwiftUI 字面量以中文源文为键，英文表由编译器提取键 + 语义键组成；纯 Swift 字符串走 `L10n`/`LocalPodLocalization`；LocalPodKit 使用 `Bundle.module`，显式 Locale 重载保证测试不依赖宿主语言；所有既有 UI 测试通过 `launchPinned()` 固定 zh-Hans，新增英文套件固定 en。
- **性能**：启动指标包含 `--m0-reset-data` 的清库成本，属于偏悲观基线；滚动使用系统滚动减速 signpost，只用于同环境回归对比，不设设备阈值。
- **分发边界**：无 App Group、无 entitlements、无 StoreKit；媒体目录 `isExcludedFromBackup`，备份/重装语义见安装文档。

## 6. 待真机/长跑验证（未计为通过）

- [ ] 连续 2 周日常使用，记录 P0/P1 问题、崩溃、耗电、后台播放、锁屏/控制中心、来电/闹钟、拔耳机/蓝牙、AirPlay。
- [ ] 真机选择 ≥1 GB 音频文件夹，记录扫描/复制/探测耗时、峰值内存、失败与去重；建议基线 < 2 分钟，按设备实测调整。
- [ ] 真机导入 4K mp4/mov，确认仅音轨导入/播放正常；不验证画面/旋转。
- [ ] 真实 VoiceOver 完成“导入 → 播放 → 加队列 → 睡眠定时”，并在最老 iOS 17 机型检查 Dynamic Type/深色模式。
- [ ] 免费 Apple ID 安装 → 等待描述文件过期 → 同一 Bundle ID 重签；确认资料库/媒体/进度/队列/播放列表保留。
- [ ] 本地通知在到期前 2 天 10:00 真实送达；拒绝通知、专注模式/摘要开启时的诊断横幅兜底。
- [ ] Finder 加密备份/恢复、Quick Start 换机：数据库/设置是否恢复、媒体缺失与重导重链。
- [ ] SideStore/AltStore 刷新路径（可能先卸载再安装）；不要假定容器一定保留。
- [ ] 真实设备语言切换（中文/英文）、RTL 布局、App Store 本地化元数据（本项目不上架，仅未来）。
- [ ] 2 小时连续后台播放的电量/发热/内存与进度保存。

## 7. 已知限制

- 签名提醒默认开启，但首次启动不会弹通知权限框；若用户从未把开关关闭再开启，本地通知不会获得授权。诊断页横幅仍有效；安装文档已写明此操作。真实送达未验证。
- 本地通知是尽力提醒，不替代日历兜底；专注模式/通知摘要可能延迟或隐藏。
- 内置示例合集名与文件名为持久化用户数据，英文模式下仍显示中文；只翻译来源标签。
- 英文无复数变体（例如 “1 items”），未使用 `.stringsdict`；日期/字节数依赖系统 Locale。
- 未测试 RTL；无 App 内语言切换（跟随 iOS 设置）。
- 性能只记录模拟器基线；启动数字包含清库，不能外推到真机。
- 未做 2 周自用、1 GB 导入、4K 真机音轨、真实 VoiceOver 全流程、7 天重签演练、真实备份恢复；这些仍未通过。
- 仅音频：视频文件可导入并播放音轨，不显示画面、不做旋转/PiP/全屏。
- 不做 Share Extension、App Group、Wi-Fi 上传（P1）。

## 8. 复现命令

```bash
cd /Users/xlf/Dev/code/localpod

# 核心测试
cd LocalPodKit && swift test && cd ..

# 生成工程（修改 project.yml 或新增文件后）
xcodegen generate

# 全量 UI 回归（40 条）
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:LocalPodUITests

# 本地化专项
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:LocalPodUITests/M5LocalizationUITests

# 设备架构编译（不签名）
xcodebuild -project LocalPod.xcodeproj -scheme LocalPod -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

> 调试启动参数：`--m5-show-onboarding`、`--m5-skip-onboarding`、`--m5-reset-onboarding`、`--m5-force-dark-appearance`、`--m5-fake-signing-expiry-days N`（均仅 Debug/测试用途，Release 不生效）。
