# LocalPod M2 实施与验证报告

> 日期：2026-11-10
> 工程：`/Users/xlf/Dev/code/localpod`
> 结论：**M2「播放核心」代码完成，进度恢复、倍速、后台音频、视频全屏与后台暂停策略在模拟器/自动化中通过；锁屏/控制中心、真实中断/路由、视频旋转/PiP/AirPlay、2 小时长播内存仍待真机验证，未计为已通过。**
> 计划基线：`PLAN.md` 5.4

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.0.1 (26A434) |
| Xcode | 27.1 (27A9275) |
| Swift | 6.4（Swift 6 语言模式） |
| iOS SDK | 27.1 |
| 模拟器 | iOS 27.1 · iPhone Duo（UDID `3055696C-BC73-4190-A3F7-EE0AC55F1EE6`） |
| 部署目标 | iOS 17.0，仅 iPhone |
| 签名 | 模拟器 ad-hoc；真机免费账号见 `docs/M0-DEVICE-CHECKLIST.md` |

> 本机只有 iOS 27.1 的 iPhone Duo 模拟器，没有 iOS 17 运行时，也没有可旋转的直板 iPhone 模拟器。iOS 17 真机与横屏行为仍在真机待办中。

## 2. M2 交付

| 交付 | 状态 | 说明 |
| --- | --- | --- |
| PlaybackController + 状态机 + 错误恢复 | 完成 | `idle / preparing / ready / playing / paused / buffering / interrupted / ended / failed`；加载/播放/暂停/seek/倍速/重试；失败可手动重试，播放键在失败后也会重建并续播；媒体服务重置后按原位置重建；所有 item 回调带 ID 校验，切歌 100 次无串台 |
| AudioSession / Now Playing / 远程命令 | 完成 | `.playback` + `.allowAirPlay`，音频 `.spokenAudio`、视频 `.moviePlayback`；锁屏信息含标题、合集、时长、已播时间、倍速、媒体类型、真实封面或渐变占位图；播放/暂停/切换/±15s/拖动命令；媒体服务重置监听 |
| 中断 / 路由 | 完成 | 打断开始暂停并记录原状态；结束后按 `shouldResume` 恢复；旧输出设备（拔耳机）暂停；真实系统事件未在模拟器自动化 |
| 进度持久化 / 恢复 / 完成阈值 | 完成 | 新增 SwiftData V3 `PlaybackState` 独立表；播放中约每秒保存，暂停/seek/切歌/后台/结束强制保存；恢复规则 `3 < position < duration-30`；完成规则 ≥95%，或时长 >60s 且剩余 ≤30s；播完不自动续播，手动重播从 0 开始 |
| 倍速 + timeDomain | 完成 | 播放器提供 0.5/1.0/1.5/2.0/3.0× 胶囊；策略层另有 0.8/1.2/1.8/2.5 预设；每个 `AVPlayerItem.audioTimePitchAlgorithm = .timeDomain`；仅在播放中改变 `player.rate` |
| 音频播放器 UI | 完成 | 封面、标题、状态、错误+重试、进度条、当前/剩余时间、±15s、播放暂停、倍速、视频画面入口；滑块拖动只在松手时 seek/保存，避免每帧写数据库 |
| 视频 AVPlayerViewController | 完成 | 全屏 cover、系统播放控件、横屏方向已在 Info.plist 声明、PiP 开启并接入 `AVPlayerViewControllerDelegate`、AirPlay 通过 AudioSession/系统路由、关闭返回 |
| 视频后台策略 | 完成 | 后台时音频继续；视频默认暂停并在回前台恢复；PiP 已激活时不暂停；后台暂停标记不会被普通暂停误触发恢复 |
| 测试与文档 | 完成 | 60 个核心测试、6 个 M2 UI 测试、M0/M1 回归；本报告、PLAN 勾选、README、截图 |

主要新增/修改文件：

- `LocalPodKit/Sources/LocalPodKit/Persistence/LocalPodSchema.swift`：Schema V3 + `PlaybackState` + V2→V3 迁移。
- `LocalPodKit/Sources/LocalPodKit/Playback/PlaybackController.swift`：控制器与状态机重写。
- `LocalPodKit/Sources/LocalPodKit/Playback/PlaybackPolicy.swift`：恢复/完成/倍速/打断策略。
- `LocalPodKit/Sources/LocalPodKit/Playback/PlaybackProgressStore.swift`：SwiftData 进度读写。
- `LocalPodKit/Sources/LocalPodKit/Playback/PlaybackItem.swift`：增加 `libraryItemID`、`artworkURL`。
- `LocalPodKit/Sources/LocalPodKit/Library/LibraryService.swift`：删除条目时级联删除进度行。
- `LocalPod/Spikes/Playback/PlaybackView.swift`：播放器 UI、倍速胶囊、可访问性标识。
- `LocalPod/Spikes/Playback/VideoPlayerScreen.swift`：PiP 委托与全屏视频。
- `LocalPod/App/RootView.swift`：进度存储挂载、前后台策略、M2 调试启动参数。
- `LocalPod/Features/Library/LibraryView.swift`：资料库播放传递条目 ID/封面。
- `project.yml` / `LocalPod/Info.plist`：`UIBackgroundModes` 增加 `picture-in-picture`。
- 测试：`PlaybackPolicyTests`、`PlaybackProgressStoreTests`、`PlaybackControllerTests`、`SchemaMigrationTests`、`LibraryServiceTests`、`LocalPodUITests/M2UITests.swift`。
- 资源：`demo-long-audio.m4a`（约 298 秒 TTS 中文语音，用于恢复/完成/后台测试）。

## 3. 验收标准对照

| # | PLAN 5.4 验收项 | 结果 | 证据 |
| --- | --- | --- | --- |
| 1 | 锁屏后音频继续；锁屏显示标题/封面/进度；控制中心播放/暂停/±15s/拖动生效 | **部分自动化，真机待验** | `testAudioAdvancesWhileAppIsInBackground`：按 Home 后台 3 秒后回前台，播放时间继续前进 ≥2 秒；`testNowPlayingMetadataAndRemoteCommands`：标题/合集/时长/速率写入 Now Playing、远程命令启用、±15s 间隔为 15；锁屏/控制中心实际 UI 与拖动未在模拟器确认 |
| 2 | 强退后重开，进度恢复误差 ≤ 2 秒；已播完不自动续播 | **通过（模拟器）** | `testResumeAfterRelaunchWithinTwoSeconds`：跳到 2:00 后强退，重开回到 2:00（±2s）；`testForceQuitWhilePlayingResumesWithinTwoSeconds`：播放中强退，恢复误差 ≤2s；`testFinishedItemDoesNotAutoResume`：播放结束重开为 0:00；核心测试另覆盖完成阈值 |
| 3 | 0.5/1.0/1.5/2.0/3.0x 可用，人声不变调 | **部分自动化，听感待真机** | `testSpeedPresetsPlayPauseAndSkip` 依次点击 0.5/1.0/1.5/2.0/3.0× 并校验标签；`testRatePresetsAndPitchCorrection` 校验限幅与 `audioTimePitchAlgorithm == .timeDomain`；实际人声不变调无法由自动化听辨 |
| 4 | 视频有画面；全屏/旋转/PiP/AirPlay 正常；后台默认暂停，回前台恢复 | **部分自动化，真机待验** | M0 `testH264AndHEVCVideoLaunch` 截图验证画面；`testVideoFullScreenPresentAndDismiss` 验证全屏 cover 展示与关闭；核心测试验证音频后台继续、视频后台暂停、回前台恢复、PiP 期间不暂停；旋转因本机只有 iPhone Duo 模拟器、`XCUIDevice` 旋转未改变窗口而未验证；PiP/AirPlay 需真机 |
| 5 | 拔耳机暂停；来电/闹钟打断后按 shouldResume 恢复 | **策略已测，系统事件待真机** | `PlaybackPolicyTests.testInterruptionResumeDecision`；控制器已监听 `interruptionNotification` / `routeChangeNotification`；模拟器无法可靠注入真实来电/闹钟/拔耳机事件 |
| 6 | 2 小时长音频播放内存稳定，无泄漏；切歌 100 次无崩溃 | **部分通过** | `testOneHundredItemSwitchesDoNotCrash`：100 次加载/切换通过；2 小时连续播放内存/泄漏需真机长跑，未在本会话执行 |

> 第 1、3、4、5、6 项未在 PLAN 中勾选为通过；自动化覆盖的部分已列出，其余列入第 6 节真机清单。

## 4. 自动化结果

### 4.1 LocalPodKit 单元/集成测试

命令：

```bash
cd LocalPodKit
swift test
```

结果：

```text
Executed 60 tests, with 0 failures (0 unexpected) in 8.031 seconds
5000-file import: 100.3 MB peak delta, 100.3 MB final delta
SwiftData benchmark (macOS, in-memory): insert 0.383s, count+page 0.002s
```

M2 新增覆盖：

- `PlaybackPolicyTests`（9）：必需倍速与限幅、95%/30 秒完成阈值、短音频不吃“剩余 30 秒”规则、恢复窗口、中断恢复决策。
- `PlaybackProgressStoreTests`（9）：新条目无进度、播放计数、保存/恢复往返、完成不恢复且重播归零、位置限幅、非法值、回退时长、删除、多条独立。
- `PlaybackControllerTests`（9）：真实 5 分钟 M4A 加载时长、播放/暂停/seek/skip、5 档倍速与 `timeDomain`、播放中持久化并在新控制器恢复 ≤2s、完成不自动续播、音频/视频后台策略、PiP 例外、Now Playing/远程命令、100 次切歌。
- `SchemaMigrationTests`（2）：V1→V3、V2→V3 lightweight migration，迁移后 `PlaybackState` 可写。
- `LibraryServiceTests`（9）：删除资料库条目时级联删除进度行。

### 4.2 UI 测试

```text
M0UITests: 5 tests, 0 failures, 65.0 seconds
M1UITests: 5 tests, 0 failures, 88.3 seconds
M2UITests: 6 tests, 0 failures, 110.7 seconds
```

M2 用例：

| 用例 | 验证内容 |
| --- | --- |
| `testSpeedPresetsPlayPauseAndSkip` | 长音频加载、播放、0.5/1.0/1.5/2.0/3.0× 逐档切换、时间前进、暂停 |
| `testResumeAfterRelaunchWithinTwoSeconds` | 跳到 2:00 → 强退 → 重开恢复到 2:00 ±2s |
| `testForceQuitWhilePlayingResumesWithinTwoSeconds` | 播放中强退 → 重开恢复位置误差 ≤2s |
| `testFinishedItemDoesNotAutoResume` | 播放到结束 → 重开停在 0:00，不自动续播 |
| `testAudioAdvancesWhileAppIsInBackground` | 音频播放中按 Home 3 秒，回前台后时间继续前进 |
| `testVideoFullScreenPresentAndDismiss` | H.264 全屏 cover 展示、关闭按钮可用并能退出 |

M0/M1 回归全部通过（导入 100 文件、音频/视频启动、收件箱、5k 基准、验收导入/取消/强杀/删除/5k 列表）。

### 4.3 截图

| 截图 | 内容 |
| --- | --- |
| ![M2 倍速与控制](screenshots/M2-speed-and-controls.png) | 播放器卡：封面、进度、±15s、暂停状态、5 档倍速胶囊与 1.0× |
| ![M2 重开恢复](screenshots/M2-resume-after-relaunch.png) | 强退重开后停在 2:00，状态“就绪”，不自动播放 |
| ![M2 播完归零](screenshots/M2-finished-restarts-at-zero.png) | 播完后重开为 0:00，不自动续播 |
| ![M2 后台音频](screenshots/M2-audio-after-background.png) | 音频后台 3 秒后回到前台，时间继续前进 |
| ![M2 视频全屏](screenshots/M2-video-fullscreen.png) | H.264 全屏播放与关闭按钮 |

## 5. 关键实现说明与修正

- **进度表与资料库解耦**：`PlaybackState` 放在独立的 V3 表，以 `itemID` 唯一标识；每秒进度写入不会让 `MediaItem` 查询/资料库列表失效。V2 实体在 V3 中复用，V1→V3 与 V2→V3 均有真实 lightweight migration 测试。
- **恢复误差**：每 0.5s 时间回调中按墙钟节流约 1 秒写一次；暂停、seek、切歌、进后台、播放结束/失败再强制写一次。UI 测试覆盖“暂停后跳转强退”和“播放中强退”两种路径。
- **完成阈值**：`position >= 95%`，或 `duration > 60s && duration-position <= 30s`。短音频（如 20 秒 demo）不受“剩余 30 秒”影响，避免一加载就被判完成。
- **状态机与切歌竞态**：KVO/通知回调都携带 `itemID` 并与当前 item 比对，旧 item 的延迟回调不会改新 item 的状态；100 次快速切换测试通过。
- **视频后台策略**：`scenePhase` 变化时由控制器统一处理；视频且非 PiP 时暂停并记录“前台需恢复”，音频不暂停；PiP 激活时跳过暂停。普通用户暂停会清除恢复标记，避免后台遥控暂停后回前台又自动播放。
- **Now Playing**：只在状态变化时更新（不是每 0.5s），系统按 elapsed + rate 自行推进锁屏进度；封面优先读取导入时生成的 JPEG，缺失时使用渐变占位图。远程命令覆盖播放/暂停/切换/±15s/拖动。
- **PiP**：`allowsPictureInPicturePlayback = true`、`canStartPictureInPictureAutomaticallyFromInline = true`、委托回调维护 `isPictureInPictureActive`，并声明 `audio` + `picture-in-picture` 后台模式；委托使用 `MainActor.assumeIsolated` + `@unchecked Sendable` 适配 AVKit 的非隔离回调（AVKit 实际在主线程调用）。
- **删除级联**：`LibraryService.delete` 在删除媒体记录前按 `itemID` 删除进度行，避免孤立进度。
- **测试素材**：新增 298 秒中文 TTS M4A，满足恢复窗口（>33 秒）与完成阈值（>60 秒）测试需要；旧 20 秒 demo 继续用于快速加载/切换。
- **模拟器限制**：iPhone Duo 模拟器在 `XCUIDevice.orientation = .landscapeLeft` 后窗口仍为 466×678，旋转未被验证；Info.plist 已声明 Portrait/LandscapeLeft/LandscapeRight，真机需确认。

## 6. 待真机验证（未计为通过）

- [ ] 锁屏：音频继续、标题/合集/真实封面/进度显示正确。
- [ ] 控制中心：播放/暂停/±15s/拖动进度条均生效，锁屏进度随时间前进。
- [ ] 来电、闹钟、Siri 打断：按 `shouldResume` 恢复；不支持恢复的场景保持暂停。
- [ ] 拔耳机/蓝牙断开：立即暂停，不自动外放。
- [ ] 视频：横屏/竖屏旋转、全屏控件、PiP 进入/恢复界面、后台 PiP 继续、AirPlay 路由。
- [ ] 0.5/1.0/1.5/2.0/3.0× 的人声听感（不变调、无明显金属声）。
- [ ] 2 小时长音频连续播放内存稳定、无泄漏；最老支持 iPhone 上的发热/耗电。
- [ ] 真机 100 次切歌与多次前后台切换。
- [ ] 导入的真实内嵌封面在锁屏/控制中心正确显示。
- [ ] 媒体服务重置（系统级事件）后的恢复；iOS 17 真机行为。
- [ ] M0/M1 真机项继续见 `docs/M0-DEVICE-CHECKLIST.md` 与 M1 报告。

## 7. 已知限制

- 内置 demo 音频没有 `libraryItemID`，不写进度；资料库条目与调试长音频才持久化进度。
- 拖动滑块过程中只更新时间显示，松手才 seek 并保存；强杀发生在拖动中可能丢失当前拖动位置（最多约 1 秒正常播放进度）。
- 后台视频暂停策略依赖 `scenePhase`；PiP 在 SwiftUI `fullScreenCover` 中的实际表现需真机确认（委托与恢复回调已接通）。
- 完成阈值按计划使用“剩余 30 秒”而非仅 95%，因此 5 分钟音频最后 30 秒会被视为已完成并重开归零。
- 仍无队列、播放列表、睡眠定时（M3）；无 CarPlay、无 Share Extension、无 StoreKit（既定决策）。
- 2 小时长播内存/泄漏没有可自动化的短测试替代，未计为通过。

## 8. 复现命令

```bash
cd /Users/xlf/Dev/code/localpod

# 核心测试
cd LocalPodKit && swift test && cd ..

# 生成工程（修改 project.yml 或新增文件后）
xcodegen generate

# 全部 UI 测试（替换为本机 UDID）
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>'

# 只跑 M2
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:LocalPodUITests/M2UITests
```

> 本机多次连续运行 UI 测试时曾再次出现 `xcodebuild` 在启动测试前挂起（模拟器 testmanager 状态问题）；`simctl shutdown` + `boot` 后恢复正常，结果与上表一致。
