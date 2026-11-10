# LocalPod M3 实施与验证报告

> 日期：2026-11-10
> 工程：`/Users/xlf/Dev/code/localpod`
> 结论：**M3「队列、播放列表、睡眠定时、设置」代码完成，队列/播放列表/睡眠定时/继续播放/设置均有自动化覆盖；锁屏状态下的睡眠定时、拖拽手感、控制中心下一首/上一首等真机项仍需确认，未计为已通过。**
> 计划基线：`PLAN.md` 5.5
> 产品边界：LocalPod **仅播放音频**；视频文件可导入并播放音轨，不显示画面、不旋转、无 PiP。

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

## 2. M3 交付

| 交付 | 状态 | 说明 |
| --- | --- | --- |
| 队列 + 持久化 | 完成 | `QueueManager` 以 `QueueEntry` 行持久化顺序，`QueueState` 保存当前项、随机开关、循环模式与随机顺序；重启恢复当前项但保持暂停 |
| 播放下一首 / 加入队列 | 完成 | 资料库条目详情与上下文菜单提供“下一首播放”“加入队列”；播放条目/合集替换队列；重复条目移动而非重复 |
| 自动下一集 | 完成 | `PlaybackController.onItemEnded` → `PlaybackSession`；受设置“播完自动下一集”、循环模式、睡眠定时“本集结束”共同约束 |
| 随机 / 循环 | 完成 | 随机顺序生成后持久化，可开关；循环关/全部/单曲三态，播放页一键循环；上一首只在“循环全部”时从队首回卷 |
| 播放列表 CRUD | 完成 | 新建/重命名/删除；加入/移除条目；条目与列表均持久化 |
| 拖拽 / 排序 / 播放全部 | 完成 | 编辑模式 `.onMove` + 左滑“上移/下移”；播放全部与随机播放；排序重启后保留 |
| 睡眠定时 | 完成 | 1/5/15/30/45/60/90 分钟与“本集结束”；截止时间驱动，最后 10 秒将 `AVPlayer.volume` 线性降到 0 后暂停；取消时恢复音量 |
| 已播完 / 继续播放 | 完成 | 沿用 M2 完成阈值；资料库“继续播放”只显示 `playCount > 0` 且未完成、未缺失的条目，最多 5 条 |
| 设置页 | 完成 | 默认倍速、快进/快退间隔、恢复播放位置、自动下一集；`UserDefaults` 前缀 `localpod.settings.`，立即生效并跨重启保留；含维护、导入历史、音频-only 说明 |
| 数据模型 | 完成 | SwiftData Schema V4：`QueueEntry`、`QueueState`、`Playlist`、`PlaylistEntry`；V1/V2/V3 → V4 lightweight migration 测试通过 |
| 测试与文档 | 完成 | 核心测试 94 个；M3 UI 6 个；M0/M1/M2 回归；本报告、PLAN 勾选、README、截图 |

主要新增/修改文件：

- `LocalPodKit/Sources/LocalPodKit/Persistence/LocalPodSchema.swift`：V4 实体与 V3→V4 迁移。
- `LocalPodKit/Sources/LocalPodKit/Playback/QueueManager.swift`：队列、随机、循环、持久化。
- `LocalPodKit/Sources/LocalPodKit/Playback/PlaybackSession.swift`：播放/队列/列表/设置/睡眠定时的会话编排。
- `LocalPodKit/Sources/LocalPodKit/Playback/SleepTimer.swift`：截止时间、淡出、本集结束一次性消费。
- `LocalPodKit/Sources/LocalPodKit/Playback/AppSettingsStore.swift`：UserDefaults 设置与限幅。
- `LocalPodKit/Sources/LocalPodKit/Library/PlaylistService.swift`：列表 CRUD 与条目排序。
- `LocalPodKit/Sources/LocalPodKit/Support/ArrayMove.swift`：核心层排序辅助（不依赖 SwiftUI）。
- `LocalPod/Spikes/Playback/PlaybackView.swift`：队列区、随机/循环、睡眠定时菜单、上一首/下一首、设置入口。
- `LocalPod/Features/Library/LibraryView.swift`：继续播放、播放下一首/加入队列/加入列表、删除联动队列。
- `LocalPod/Features/Playlists/PlaylistViews.swift`：列表与详情页。
- `LocalPod/Features/Settings/SettingsView.swift`：设置页。
- `LocalPod/App/M3DebugSeed.swift`：固定 ID 的 A/B/C 与 298 秒长音频测试种子。
- `LocalPod/App/RootView.swift`：会话注入、M3 启动参数、设置 sheet。
- 测试：`QueueManagerTests`、`PlaylistServiceTests`、`AppSettingsStoreTests`、`SleepTimerTests`、`PlaybackSessionTests`、`SchemaMigrationTests`、`M3UITests`。
- 音频-only 清理：删除 `VideoPlayerScreen.swift`、PiP/横屏/视频后台暂停与对应 UI 测试。

## 3. 验收标准对照

| # | PLAN 5.5 验收项 | 结果 | 证据 |
| --- | --- | --- | --- |
| 1 | 队列重启后保留；播放下一首/加入队列语义正确；当前项删除后自动前进 | **通过（模拟器）** | `QueueManagerTests`（替换/插入/追加、重启恢复、删除当前前进、重复移动）、`PlaybackSessionTests.testDeletingCurrentItemAdvancesThenStopsWhenEmpty`；`M3UITests.testQueueSemanticsCurrentDeletionAndRelaunch` 验证 A→B→C 队列顺序、删除 A 后当前项前进到 B、强退重开恢复 B 且暂停 |
| 2 | 播放列表拖拽排序保存；随机/循环行为正确 | **通过（模拟器）** | `PlaylistServiceTests`（CRUD、去重、移动持久化、级联清理）、`QueueManagerTests` 随机/循环；`M3UITests.testPlaylistCreateReorderPersistAndPlayAll` 新建列表、加入 A/C、上移 C、重启后顺序保留、播放全部以 C 开始 |
| 3 | 睡眠定时 1 分钟测试到点淡出暂停；本集结束模式不自动下一集 | **通过（模拟器）** | `SleepTimerTests` 固定时钟验证 60 秒截止、最后 10 秒音量 1→0、取消恢复；`PlaybackSessionTests.testEndOfEpisodeSleepModeSuppressesAutoAdvance`、`testSleepTimerFirePausesPlaybackAndRestoresVolume`；`M3UITests` 两个睡眠用例使用真实 298 秒/20 秒音频 |
| 4 | 已播完阈值正确；“继续播放”不出现已播完条目 | **通过（模拟器）** | M2 完成阈值测试沿用；`PlaybackSessionTests`/`PlaybackProgressStoreTests`；`M3UITests.testContinueListeningExcludesFinishedItems` 验证 B（已完成）不出现、C（未完成）出现 |
| 5 | 设置项重启后保留 | **通过（模拟器）** | `AppSettingsStoreTests` 默认值/持久化/限幅/清空；`M3UITests.testSettingsPersistAcrossRestart` 修改 1.5×、不记住、不自动，强退重开仍选中 |

## 4. 自动化结果

### 4.1 LocalPodKit 单元/集成测试

命令：

```bash
cd LocalPodKit
swift test
```

结果：

```text
Executed 94 tests, with 0 failures in 9.397 seconds
```

M3 新增覆盖：

- `QueueManagerTests`（10）：播放全部替换队列、下一首插入、追加；顺序/循环全部/单曲前进；上一首回卷；重启恢复；随机排列且不立即重复；删除当前/最后一项；删除非当前项；重复加入移动；拖拽排序跨实例持久化；清空。
- `PlaylistServiceTests`（6）：新建/重命名/排序；加入去重与移除后位置归一；移动跨实例持久化；移除条目/删除列表；删除资料库条目清理所有列表项；资料库删除级联队列/列表/进度。
- `AppSettingsStoreTests`（4）：默认值；新实例读取持久化值；越界限幅；重置与清空。
- `SleepTimerTests`（4）：固定时钟 1 分钟淡出后触发；淡出中取消恢复音量且不触发；本集结束只消费一次；剩余时间文本格式。
- `PlaybackSessionTests`（9）：播放全部并自动前进；关闭自动下一集；本集结束抑制前进；删除当前前进/空队列停止；下一首/加入队列语义；重启恢复暂停；当前项缺失跳过；定时触发暂停并恢复音量；单曲循环重载当前项。
- `SchemaMigrationTests`：新增 V3→V4 迁移，迁移前写入 V3 数据、迁移后读写四个新实体。

### 4.2 UI 测试

```text
M3UITests: 6 tests, 0 failures, 404.1 seconds
```

| 用例 | 验证内容 |
| --- | --- |
| `testQueueSemanticsCurrentDeletionAndRelaunch` | A 播放中，B“下一首”、C“加入队列”；队列顺序 A/B/C；删除 A 后当前项前进到 B（A 已自然播完，B 以暂停加载）；强退重开恢复 B 与队列且不自动播放 |
| `testPlaylistCreateReorderPersistAndPlayAll` | 新建“通勤”；加入 A/C；上移 C；强退重开后顺序保留；播放全部从 C 开始且队列 2 条 |
| `testSleepTimerOneMinuteFadesAndPauses` | 298 秒音频播放中启用 1 分钟定时，真实等待到点后暂停 |
| `testSleepTimerEndOfEpisodeDoesNotAutoAdvance` | 启动前启用“本集结束”，3.0× 播完 A 后停在 A，不前进到 B |
| `testContinueListeningExcludesFinishedItems` | 已完成 B 不出现，未完成 C 出现在“继续播放” |
| `testSettingsPersistAcrossRestart` | 修改 1.5×、不记住、不自动，强退重开后设置保留 |

回归（同一次全量运行）：

```text
M0UITests: 4 tests, 0 failures, 46.1 seconds
M1UITests: 5 tests, 0 failures, 89.5 seconds
M2UITests: 5 tests, 0 failures, 102.3 seconds
```

同一次全量运行共 20 条 UI 测试、0 失败、641.9 秒（2026-11-10 23:20）。

M0/M1/M2 回归覆盖导入、收件箱、5k 基准、验收导入/取消/强杀/删除、播放进度/倍速/后台音频/播完归零。H.264/HEVC 与视频全屏用例已按音频-only 决策删除。

### 4.3 截图

| 截图 | 内容 |
| --- | --- |
| `screenshots/M3-queue.png` | 播放页队列：当前项 A、下一首 B、队列 C，随机/循环/清空 |
| `screenshots/M3-playlist.png` | 播放列表详情：排序后的条目与播放全部/随机 |
| `screenshots/M3-sleep-timer.png` | 睡眠定时启用后的状态与取消 |
| `screenshots/M3-continue-listening.png` | 资料库“继续播放”只显示未完成条目 |
| `screenshots/M3-settings.png` | 设置页：倍速、间隔、恢复/自动下一集、音频-only 说明 |

### 4.4 构建

- 模拟器 Debug：UI 测试构建与执行成功。
- `generic/platform=iOS` Debug、`CODE_SIGNING_ALLOWED=NO`：**BUILD SUCCEEDED**（验证真机架构编译，不做签名安装）。

## 5. 关键实现说明

- **队列持久化**：`QueueEntry` 每条目一行，位置整数；`QueueState` 单行保存当前项、随机开关、循环模式、随机顺序（逗号分隔 UUID）与更新时间。所有变更立即保存，重启由 `attach` 读回；`PlaybackSession.attach` 只加载当前项、不自动播放。
- **队列唯一性**：条目 ID 在队列中唯一；再次“下一首/加入队列”会移动已有条目，避免当前项出现歧义。
- **自动前进**：控制器只发出 `onItemEnded`，由 `PlaybackSession` 决定是否前进；顺序为：先消费“本集结束”睡眠模式（消费后暂停且不前进），再检查 `autoPlayNext`，最后按循环/随机取下一项。单曲循环重载当前项。
- **随机顺序**：开启随机时生成包含全部条目的排列并持久化；新增条目追加到随机序列；关闭随机回到自然顺序。播放顺序与底层队列顺序分离，拖拽仍编辑自然队列。
- **睡眠定时**：`SleepTimer` 保存绝对截止时间而非递减计数，每 0.5 秒 tick；最后 10 秒通过 `onVolumeChange` 把播放器音量从 1 降到 0，到点暂停并恢复音量 1，避免下次播放无声。取消淡出会立即恢复音量。
- **结束抑制**：`consumeEndOfEpisode()` 是破坏性一次性操作，只有真正播完时才消费；手动停止/切歌不清除模式。
- **加入播放列表**：条目详情使用独立的选择 sheet（中等高度，可扩展为全屏），列表多时比弹出 Menu 更易操作；选中后立即写入并提示。
- **删除联动**：删除资料库条目时，`LibraryService` 同时删除进度、队列项与播放列表项；若删除的是当前项，`PlaybackSession.handleDeletedItem` 先选下一项再停止/继续。
- **设置**：`AppSettingsStore` 在 `didSet` 中写入 UserDefaults 并限幅；`PlaybackSession.applySettings` 把间隔与默认倍速同步给控制器；重置数据时会清空 `localpod.settings.` 前缀键。
- **测试确定性**：M3 UI 使用固定 UUID 的 A/B/C；睡眠测试使用 298 秒长音频（一分钟定时不会先播完）与启动前预置“本集结束”；菜单在播放中打开可能等待 app 静止十余秒，故不依赖菜单打开速度。队列用例通过 `--m3-no-auto-next` 关闭自动下一集：20 秒素材在超过两分钟的 UI 导航中会自然播完并前进，关闭后“删除当前项 → 自动前进到 B”的断言才稳定。
- **音频-only**：删除视频渲染、PiP、横屏与视频后台暂停；控制器只使用 `AVPlayer` 音频，`UIBackgroundModes` 仅 `audio`。

## 6. 待真机验证（未计为通过）

- [ ] 锁屏/控制中心：下一首/上一首命令、±间隔命令、进度拖动在真机生效。
- [ ] 睡眠定时在后台/锁屏状态下按时暂停；最后 10 秒淡出听感自然、无爆音。
- [ ] 播放列表拖拽手势在真机手感与排序落点正确；编辑模式外左滑“上移/下移”可用。
- [ ] 队列在真实强退（非调试启动参数）后恢复当前项且不自动播放；恢复后从保存进度继续。
- [ ] 删除正在播放的条目时，真机文件删除与队列前进无竞态、无崩溃。
- [ ] 设置跨 App 升级/重装（数据保留场景）仍生效；UserDefaults 与 SwiftData 一致性。
- [ ] AirPlay/蓝牙输出下睡眠定时音量淡出生效；拔耳机暂停仍正常。
- [ ] 长时间队列（数百条）滚动、拖拽与随机顺序性能。
- [ ] 最老 iOS 17 真机上的队列/列表页面布局与 VoiceOver。

## 7. 已知限制

- 睡眠定时不跨 App 重启恢复：重启后为关闭状态；仅队列、循环/随机、播放列表与设置持久化。
- 睡眠定时使用 App 内 0.5 秒 ticker；App 被系统挂起时不会执行暂停，依赖后台音频保活。锁屏长播到点行为需真机确认。
- “继续播放”最多显示 5 条，且只包含 `playCount > 0` 的条目；从未播放的条目不显示。
- 队列条目唯一：重复“加入队列”不会产生第二条，而是移动原条目。
- 播放列表没有封面、嵌套或智能规则；排序为手动位置。
- 随机顺序在队列条目变化时保留仍存在的项，新条目追加；不做“重新洗牌”按钮。
- 视频文件仅音轨；不显示画面、不旋转、无 PiP。
- 无 CarPlay、无 Share Extension、无 StoreKit（既定决策）。

## 8. 复现命令

```bash
cd /Users/xlf/Dev/code/localpod

# 核心测试
cd LocalPodKit && swift test && cd ..

# 生成工程（修改 project.yml 或新增文件后）
xcodegen generate

# M3 UI 测试
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:LocalPodUITests/M3UITests

# 全部 UI 回归
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>'
```

> 连续运行 UI 测试时可能遇到 `xcodebuild` 在测试结束后不退出（模拟器 testmanager 状态问题）；结果已生成，可用 `simctl shutdown` + `boot` 恢复。
