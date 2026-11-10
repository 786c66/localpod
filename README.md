# LocalPod

本地播客式播放器（iPhone / iOS 17+）。核心区别：从文件 App 选择一个**文件夹**，递归导入其中所有音频/视频，之后像播客一样管理、播放。

当前处于 **M2「播放核心」**阶段：文件夹递归导入、去重、资料库与播放核心已可用；队列、播放列表、睡眠定时按 M3 推进。

## 已实现（M2）

- **播放状态机**：`idle / preparing / ready / playing / paused / buffering / interrupted / ended / failed`；失败可重试，解码错误/媒体服务重置可恢复。
- **后台音频**：AudioSession `.playback` + AirPlay，`.spokenAudio` / `.moviePlayback` 模式；锁屏/控制中心 Now Playing（标题、合集、时长、进度、倍速、真实封面或占位图）与播放/暂停/±15s/拖动命令。
- **进度持久化**：独立 SwiftData V3 `PlaybackState` 表，每秒落盘并在暂停/拖动/切歌/后台时强制保存；重开恢复误差 ≤ 2 秒；播完（≥95%，或 >60s 且剩余 ≤30s）标记完成、不自动续播，手动重播从 0 开始。
- **倍速**：0.5/1.0/1.5/2.0/3.0×（另有 0.8/1.2/1.8/2.5 策略预设），`audioTimePitchAlgorithm = .timeDomain` 保持人声音调。
- **播放 UI**：封面/状态/进度条/剩余时间/±15s/播放暂停/倍速胶囊/错误重试；拖动只在松手时 seek 与保存。
- **视频**：AVPlayerViewController 全屏、播放控件、PiP 委托、AirPlay 路由、关闭返回；后台默认暂停，回前台恢复，PiP 期间不暂停。
- **中断/路由**：来电/闹钟打断按 `shouldResume` 恢复；拔耳机/旧输出设备暂停；媒体服务重置后按原位置重建。

### M1 能力（保留）

- **文件夹递归导入**：文件 App 选择文件夹；扫描过滤、深度/数量上限、自然排序；iCloud 未下载文件交给下载器处理。
- **可靠导入流水线**：staging → 1 MB 分块复制 + SHA-256 → AVFoundation probe → 原子移动到 `Application Support/Media`；支持取消、失败分类、JSON 报告。
- **去重与重链**：相同内容跳过；缺失条目重新导入同内容时恢复原记录。
- **元数据**：时长、音频/视频类型、标题、视频 JPEG 缩略图、音频内嵌封面或占位图。
- **资料库**：条目/合集视图、搜索、筛选、排序、条目详情、播放、删除；显示条目数、合集数、总大小、总时长。
- **持久化**：SwiftData Schema V3（V1/V2 可 lightweight migration 到 V3）；启动/回前台对账清理 staging、孤儿媒体/封面，标记/恢复缺失。
- **导入报告**：分类结果（导入/重复/不支持/失败）、耗时、复制大小、完整 JSON 报告与导入会话记录。
- **收件箱**：`Documents/Import` + 外部打开 + Finder 文件共享路径继续可用。

### M0 能力（保留）

- SwiftUI + SwiftData + Swift 6 工程骨架，仅 iPhone，无 Share Extension、无 App Group。
- AVPlayer 音频后台播放 / Now Playing / 远程命令；H.264/HEVC 视频全屏。
- SwiftData 5k 基准；诊断页显示签名到期、数据量、路径与启动维护结果。

## 验证

- `LocalPodKit`：**60 个单元/集成测试，0 失败**；5000 文件导入峰值内存增量 100.3 MB（阈值 200 MB）。
- UI 测试：**M0 5 个 + M1 5 个 + M2 6 个，0 失败**（iOS 27.1 模拟器）。
- M2 详细结果、截图与待真机项见 [docs/M2-REPORT.md](docs/M2-REPORT.md)。
- M1 结果见 [docs/M1-REPORT.md](docs/M1-REPORT.md)；M0 报告与免费账号签名步骤见 [docs/M0-REPORT.md](docs/M0-REPORT.md)、[docs/M0-SIGNING.md](docs/M0-SIGNING.md)。
- **未计为通过**：锁屏/控制中心、来电打断、拔耳机、视频旋转/PiP/AirPlay、2 小时长播内存、真实文件夹选择器、真实 iCloud 下载/断网重试、最老真机性能；清单见 [docs/M0-DEVICE-CHECKLIST.md](docs/M0-DEVICE-CHECKLIST.md) 与 M1/M2 报告。

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
    App/                        # App、RootView、ImportCoordinator
    Features/Library/           # M1 资料库 UI（条目/合集/详情/删除）
    Spikes/Import/              # 导入向导/进度/报告
    Spikes/Playback/            # M2 播放器 UI、全屏视频/PiP
    Spikes/Inbox/               # 收件箱
    Spikes/Benchmark/           # SwiftData 5k
    Spikes/Diagnostics/         # 签名/路径/数据/维护诊断
    Resources/                  # 内置测试音频（20s/5min）与 H.264/HEVC 视频
  LocalPodKit/                  # 可复用核心
    Sources/LocalPodKit/
      Persistence/              # SwiftData V1/V2/V3 + migration
      Playback/                 # 控制器/策略/进度存储
      Import/                   # 扫描/复制/下载/probe/引擎/报告
      Library/                  # 资料库提交/删除/对账
      Media/                    # AVFoundation 元数据与缩略图
    Tests/LocalPodKitTests/
  LocalPodUITests/              # M0/M1/M2 UI 测试
  docs/
    M0-REPORT.md
    M0-SIGNING.md
    M0-DEVICE-CHECKLIST.md
    M1-REPORT.md
    M2-REPORT.md
    screenshots/
```

## 调试启动参数（M0/M1/M2）

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
| `--m0-auto-play-h264` | 启动后播放 H.264 视频 |
| `--m0-auto-play-hevc` | 启动后播放 HEVC 视频 |
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
- 不做 Share Extension（免费 Apple ID 无 App Groups），导入走文件夹、文件选择、收件箱/Wi-Fi（P1）。
- 不做 CarPlay、StoreKit/IAP、订阅。
- 导入需保持 App 前台；iCloud 下载进度为不确定进度，真实 iCloud 行为待真机验证。
- 锁屏/控制中心样式、来电打断、拔耳机、视频旋转/PiP/AirPlay、2 小时长播内存等真机项尚未确认，不计为通过。
- 队列、播放列表、睡眠定时按 M3 推进。
