# LocalPod

本地播客式播放器（iPhone / iOS 17+）。核心区别：从文件 App 选择一个**文件夹**，递归导入其中所有音频/视频，之后像播客一样管理、播放。

当前处于 **P1 阶段（前两项已交付）**：M0–M5 全部完成；P1 的 **Wi-Fi 局域网网页上传**（电脑浏览器拖文件夹上传、PIN、二维码）与**智能播放列表**（继续播放/未播完/最近添加/已播完/按合集筛选）已可用。仅播放音频，不渲染视频画面。

## 已实现（P1：Wi-Fi 上传 + 智能播放列表）

- **Wi-Fi 上传**：设置页或导入页开启后，同一 Wi-Fi 的电脑浏览器打开显示的地址（或扫二维码）、输入 6 位 PIN，即可拖入/选择整个文件夹上传；保留子目录结构，完成后自动走统一导入流水线（SHA-256 去重、来源标记「Wi-Fi」）。
- **安全边界**：仅接受局域网/回环连接；每请求校验 PIN（恒定时间比较），8 次错误/60 秒限流；严格路径清洗（拒绝 `..`/绝对路径/隐藏组件/控制字符，深度 16、单文件 8 GiB、单会话 32 GiB、2 万文件）；无目录列表、无文件读取；仅前台运行，进后台即停；不使用 HTTPS（PIN + 私网策略为边界，页面提示勿在公共 Wi-Fi 使用）。
- **可靠导入**：批次完成即导入；导入运行中自动排队；App 重启后自动恢复已完成的批次（隐藏完成标记）；上传文件流式写入隐藏临时名后原子落盘。
- **智能播放列表**：继续播放、未播完、最近添加（30 天）、已播完，外加按合集筛选浏览；每次从资料库与播放进度现算、不持久化，永不产生指向已删内容的僵尸列表；支持播放全部/随机播放。
- **本地化**：全部新文案中英双语；`NSLocalNetworkUsageDescription` 中英 `InfoPlist.strings`。
- 真机待验证项（真实浏览器上传、本地网络权限弹窗、二维码扫描等）见 [docs/P1-REPORT.md](docs/P1-REPORT.md)。

## 已实现（M5 本地化）

- **简体中文 + 英文**：App 界面与 LocalPodKit 生成的显示名/错误文案均随系统语言切换；源语言为 `zh-Hans`，英文资源在 `en.lproj`。
- **文案覆盖**：引导、标签栏、资料库、导入、收件箱、播放/队列、播放列表、睡眠定时、设置、诊断、签名提醒、空状态、错误、无障碍标签/提示/值。
- **用户内容不翻译**：文件名、媒体标题、文件夹/合集名、播放列表名、路径保持原样；内置示例合集 `示例内容` 与示例文件名也作为已持久化用户数据保留中文。
- **测试固定语言**：所有既有 UI 测试通过 `launchPinned()` 固定 `-AppleLanguages (zh-Hans)`；新增 `M5LocalizationUITests` 固定英文并验证 App 与 LocalPodKit 文案。
- 机制、键数量、未翻译例外与新增语言步骤见 [docs/M5-LOCALIZATION.md](docs/M5-LOCALIZATION.md)。

## 已实现（M4）

- **打开方式 / AirDrop**：文档类型覆盖音频、视频容器与文件夹；外部打开先原子暂存再导入，来源标记“外部打开”。
- **Finder 收件箱**：`Documents/Import` 在启动、回前台及前台运行期间自动扫描；文件需连续观察稳定后才导入，复制中的文件不会半截入库。
- **统一导入流水线**：所有渠道共享扫描、SHA-256 去重、进度、错误分类与报告；一次运行生成聚合 JSON 报告。
- **失败重试 / 隔离**：失败项保留并提供“重试失败”；顶层不支持文件移入隐藏 `.Skipped`，不会反复重扫或导入。
- **签名边界**：无 App Group/entitlements，免费账号签名不受影响。

## 已实现（M3，保留）

- **播放队列**：播放替换队列、下一首播放插入当前项之后、加入队列追加到末尾；自动下一集可关；随机顺序持久化；单曲/列表循环；队列与当前项重启后恢复为暂停状态。
- **播放列表**：新建/重命名/删除、加入/移除条目、拖拽及上移/下移排序、播放全部/随机播放；排序与内容持久化。
- **睡眠定时**：1/5/15/30/45/60/90 分钟或“本集结束”；到点前 10 秒音量淡出后暂停；本集结束模式抑制自动下一集。
- **继续播放**：资料库显示未播完条目，已播完条目不再出现在“继续播放”；播完阈值沿用 M2。
- **设置**：默认倍速、快进/快退间隔、是否记住播放位置、是否自动下一集；立即生效并跨重启保留。

## 播放核心（M2，保留）

- **播放状态机**：`idle / preparing / ready / playing / paused / buffering / interrupted / ended / failed`；失败可重试，解码错误/媒体服务重置可恢复。
- **后台音频**：AudioSession `.playback` + AirPlay，`.spokenAudio` 模式；锁屏/控制中心 Now Playing（标题、合集、时长、进度、倍速、真实封面或占位图）与播放/暂停/±15s/拖动命令。
- **仅音频**：视频文件可导入并播放其音轨，但不显示画面；已移除全屏视频、旋转、PiP 与视频后台暂停逻辑。
- **进度持久化**：独立 SwiftData `PlaybackState` 表（V3 引入，随 V4 保留），每秒落盘并在暂停/拖动/切歌/后台时强制保存；重开恢复误差 ≤ 2 秒；播完（≥95%，或 >60s 且剩余 ≤30s）标记完成、不自动续播，手动重播从 0 开始。
- **倍速**：0.5/1.0/1.5/2.0/3.0×（另有 0.8/1.2/1.8/2.5 策略预设），`audioTimePitchAlgorithm = .timeDomain` 保持人声音调。
- **播放 UI**：封面/状态/进度条/剩余时间/上一首/下一首/±间隔/播放暂停/倍速胶囊/错误重试；拖动只在松手时 seek 与保存。
- **中断/路由**：来电/闹钟打断按 `shouldResume` 恢复；拔耳机/旧输出设备暂停；媒体服务重置后按原位置重建。

### M1 能力（保留）

- **文件夹递归导入**：文件 App 选择文件夹；扫描过滤、深度/数量上限、自然排序；iCloud 未下载文件交给下载器处理。
- **可靠导入流水线**：staging → 1 MB 分块复制 + SHA-256 → AVFoundation probe → 原子移动到 `Application Support/Media`；支持取消、失败分类、JSON 报告。
- **去重与重链**：相同内容跳过；缺失条目重新导入同内容时恢复原记录。
- **元数据**：时长、音频/视频类型、标题、封面（视频文件取帧生成 JPEG，音频取内嵌封面或占位图）。
- **资料库**：条目/合集视图、搜索、筛选、排序、条目详情、播放、删除；显示条目数、合集数、总大小、总时长。
- **持久化**：SwiftData Schema V4（V1/V2/V3 可 lightweight migration 到 V4；新增队列/播放列表实体）；启动/回前台对账清理 staging、孤儿媒体/封面，标记/恢复缺失。
- **导入报告**：分类结果（导入/重复/不支持/失败）、耗时、复制大小、完整 JSON 报告与导入会话记录。
- **收件箱**：`Documents/Import` + 外部打开 + Finder 文件共享路径继续可用。

### M0 能力（保留）

- SwiftUI + SwiftData + Swift 6 工程骨架，仅 iPhone，无 Share Extension、无 App Group。
- AVPlayer 音频后台播放 / Now Playing / 远程命令。
- SwiftData 5k 基准；诊断页显示签名到期、数据量、路径与启动维护结果。

## 验证

- `LocalPodKit`：**174 个单元/集成测试，0 失败**（含 P1 新增 Wi-Fi 32 个、智能播放列表 14 个）；5000 文件导入峰值内存增量 100.3 MB（阈值 200 MB）。
- UI 测试：**M0 4 个 + M1 5 个 + M2 5 个 + M3 6 个 + M4 3 个 + M5 7 个 + 交付 3 个 + 签名 2 个 + 性能 2 个 + 本地化 3 个 + P1 4 个，共 44 个，0 失败**（iOS 27.1 模拟器）。
- P1 完整结果、安全模型与待真机项见 [docs/P1-REPORT.md](docs/P1-REPORT.md)。
- M5 完整结果、截图与待真机项见 [docs/M5-REPORT.md](docs/M5-REPORT.md)；本地化机制见 [docs/M5-LOCALIZATION.md](docs/M5-LOCALIZATION.md)；性能基线见 [docs/M5-PERFORMANCE.md](docs/M5-PERFORMANCE.md)；安装/重签/备份见 [docs/M5-INSTALL-RESIGN-BACKUP.md](docs/M5-INSTALL-RESIGN-BACKUP.md)。M4 详细结果见 [docs/M4-REPORT.md](docs/M4-REPORT.md)；M3 见 [docs/M3-REPORT.md](docs/M3-REPORT.md)；M2 见 [docs/M2-REPORT.md](docs/M2-REPORT.md)。
- M1 结果见 [docs/M1-REPORT.md](docs/M1-REPORT.md)；M0 报告与免费账号签名步骤见 [docs/M0-REPORT.md](docs/M0-REPORT.md)、[docs/M0-SIGNING.md](docs/M0-SIGNING.md)。
- **未计为通过**：锁屏/控制中心、来电打断、拔耳机、AirPlay 音频、睡眠定时后台到点、拖拽手感、2 小时长播内存、真实文件夹选择器、真实 iCloud 下载/断网重试、最老真机性能、真机语言切换、RTL 布局与 App Store 本地化元数据；清单见 [docs/M0-DEVICE-CHECKLIST.md](docs/M0-DEVICE-CHECKLIST.md) 与 M1/M2/M3/M4 报告。

## 打开工程

```bash
cd /Users/xlf/Dev/code/localpod
open LocalPod.xcodeproj
```

- 选模拟器即可直接运行（无需签名）。
- 真机需要先在 Xcode 里登录免费 Apple ID，并在 Signing & Capabilities 选择你的 Personal Team；步骤见签名文档。
- 修改 `project.yml` 后重新生成工程：

```bash
xcodegen generate
```

（本机已通过 Homebrew 安装 XcodeGen 2.46.0。）

## 命令行验证

```bash
# LocalPodKit 单元测试（macOS 14+）
cd LocalPodKit
swift test

# 构建模拟器 App
cd ..
xcodebuild -project LocalPod.xcodeproj -scheme LocalPod \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# 构建真机 App（不签名，只验证编译）
xcodebuild -project LocalPod.xcodeproj -scheme LocalPod \
  -configuration Debug -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build

# UI 测试（先确认模拟器名称/UDID）
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>'
```

## 目录

```text
localpod/
  PLAN.md                       # v0.3 项目计划
  project.yml                   # XcodeGen 工程定义（源）
  LocalPod.xcodeproj            # 生成的 Xcode 工程
  LocalPod/                     # App 与 spike UI
    App/                        # App、RootView、ImportCoordinator、M3 调试种子
    Features/Library/           # 资料库 UI（条目/合集/详情/删除/继续播放）
    Features/Playlists/         # 播放列表列表、详情、排序
    Features/Settings/          # 设置页
    Spikes/Import/              # 导入向导/进度/报告
    Spikes/Playback/            # 播放页：队列、睡眠定时、播放控件
    Spikes/Inbox/               # 收件箱
    Spikes/Benchmark/           # SwiftData 5k
    Spikes/Diagnostics/         # 签名/路径/数据/维护诊断
    Resources/                  # 内置测试音频（20s/5min）与视频容器（仅导入/音轨测试）
      en.lproj/                 # 英文本地化
      zh-Hans.lproj/            # 简体中文本地化（源语言）
    Support/                    # L10n 语义键辅助
  LocalPodKit/                  # 可复用核心
    Sources/LocalPodKit/
      Persistence/              # SwiftData V1–V4 + migration
      Playback/                 # 控制器/队列/会话/睡眠定时/设置/策略/进度
      Import/                   # 扫描/复制/下载/probe/引擎/报告
      Library/                  # 资料库提交/删除/对账、播放列表服务
      Media/                    # AVFoundation 元数据与缩略图
      Support/                  # 本地化辅助
      Resources/                # en.lproj / zh-Hans.lproj
    Tests/LocalPodKitTests/
  LocalPodUITests/              # M0–M5 + P1 UI 测试（含 M5LocalizationUITests）
  Tools/
    generate_localization.py    # 从编译器提取键生成两份 App .strings
  docs/
    M0-REPORT.md
    M0-SIGNING.md
    M0-DEVICE-CHECKLIST.md
    M1-REPORT.md
    M2-REPORT.md
    M3-REPORT.md
    M4-REPORT.md
    M5-REPORT.md
    M5-LOCALIZATION.md
    M5-PERFORMANCE.md
    M5-INSTALL-RESIGN-BACKUP.md
    P1-REPORT.md
    screenshots/
```

## 调试启动参数（M0/M1/M2/M3/P1）

仅在 Debug 构建生效，用于模拟器/UI 测试：

| 参数 | 作用 |
| --- | --- |
| `--m0-reset-data` | 清空 SwiftData、Media、DemoInput、AcceptanceInput、ImportStaging、ImportReports、封面、收件箱 |
| `--m0-auto-demo-import` | 启动后导入 3 层 100 文件演示文件夹 |
| `--m1-auto-acceptance-import` | 启动后导入验收文件夹（97 音频 + 1 重复 + 2 不支持） |
| `--m1-slow-copy` | 复制时每 64 KB 延迟 30 ms，用于取消/强杀测试 |
| `--m1-auto-maintenance` | 启动后打开诊断页，展示启动对账结果 |
| `--m1-seed-library-5000` | 向资料库插入 5000 条压力测试记录 |
| `--m0-auto-play-audio` | 启动后播放内置 20s 音频 |
| `--m2-auto-play-long-audio` | 启动后播放内置 5 分钟音频，使用固定进度 ID |
| `--m2-no-autoplay` | 配合长音频：只加载不自动播放 |
| `--m2-seek-to <秒>` | 配合长音频：加载后跳转到指定秒数 |
| `--m3-seed-playable-library` | 插入 3 条可播放 M3 测试条目（A/B/C，B 已播完、C 播到一半） |
| `--m3-seed-queue` | 建立 3 条队列并定位到 A |
| `--m3-seed-single-queue` | 用 298 秒长音频建立单条队列，供一分钟睡眠定时测试 |
| `--m3-arm-end-of-episode` | 自动播放前先启用“本集结束”睡眠模式 |
| `--m3-no-auto-next` | 关闭“自动下一集”，使长时间队列 UI 测试不因 20 秒素材自动前进 |
| `--m3-auto-play-first` | 打开播放页并播放队列当前项 |
| `--m3-open-settings` | 启动后打开设置页 |
| `--m4-auto-open-in` | 从沙盒外临时副本走真实开放方式导入路径 |
| `--m4-foreground-write-inbox` | 分块写入收件箱约 5.6 秒，验证稳定性检测 |
| `--m4-seed-unsupported-inbox` | 向收件箱写入不支持文件，验证隔离 |
| `--p1-wifi-demo` | Wi-Fi 上传页演示状态（固定 PIN/URL，不发真实网络，模拟器 UI 测试用） |
| `--p1-wifi-staged-upload` | 预置一个已完成的 Wi-Fi 批次，验证启动恢复导入 |
| `--p1-seed-smart-playlists` | 把 M3 种子条目归入「智能合集 A/B」，验证智能列表按合集筛选 |
| `--m0-auto-benchmark` | 打开 SwiftData 基准页 |
| `--m0-auto-inbox` | 打开收件箱页 |
| `--m0-seed-inbox` | 把内置音频复制到 `Documents/Import`，模拟 Finder 投递 |

示例：

```bash
xcrun simctl terminate booted com.localpod.app 2>/dev/null || true
xcrun simctl launch booted com.localpod.app --m0-reset-data --m1-auto-acceptance-import
```

## 当前边界

- 只支持 AVFoundation 可解码的音频/视频；不支持 MKV/AVI/OGG，不引入 VLCKit。
- 不做 Share Extension（免费 Apple ID 无 App Groups），导入走文件夹、文件选择、收件箱、Wi-Fi 上传。
- 不做 CarPlay、StoreKit/IAP、订阅。
- 导入需保持 App 前台；Wi-Fi 上传同样仅前台可用，进入后台即停止；iCloud 下载进度为不确定进度，真实 iCloud 行为待真机验证。
- 只播放音频，不显示视频画面；不支持旋转、PiP、全屏视频。视频文件仍可导入并读取音轨。
- Wi-Fi 上传不用 HTTPS；真实浏览器上传、本地网络权限弹窗、二维码扫描、公共 Wi-Fi/VPN 等真机项尚未确认，不计为通过（清单见 docs/P1-REPORT.md）。
- 真实 AirDrop、文件 App「用 LocalPod 打开」、Finder 数据线拖入、iCloud 占位文件、超大文件夹打开方式与免费账号真机安装尚未确认，不计为通过。
- 锁屏/控制中心样式、来电打断、拔耳机、AirPlay 音频、睡眠定时后台到点、2 小时长播内存等真机项尚未确认，不计为通过。
