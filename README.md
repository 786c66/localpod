# LocalPod

本地播客式播放器（iPhone / iOS 17+）。核心区别：从文件 App 选择一个**文件夹**，递归导入其中所有音频/视频，之后像播客一样管理、播放。

当前处于 **M0 技术验证**阶段。M0 只做工程骨架和关键路径 spike，不是完整产品。

## 已实现（M0）

- SwiftUI + SwiftData + Swift 6 工程骨架，仅 iPhone，无 Share Extension、无 App Group。
- `LocalPodKit` 本地 Swift Package：文件夹扫描、分块复制导入、Inbox、SwiftData 模型、AVPlayer 播放控制。
- Spike A：`UIDocumentPickerViewController` 文件夹选择；演示文件夹 3 层 100 文件、进度/取消/结果。
- Spike B：AVPlayer 音频后台播放、Now Playing、远程命令、锁屏信息；AVPlayerViewController 播放 H.264/HEVC。
- Spike C：`Documents/Import` 收件箱 + `onOpenURL`（用 LocalPod 打开 / Finder 文件共享）。
- SwiftData 5k 插入/查询/列表基准。
- 诊断页：Bundle/Team/描述文件到期时间/数据量/路径，方便真机免费账号 7 天重签验证。
- 15 个 `LocalPodKit` 单元测试 + 4 个 UI 测试（模拟器）。

M0 的详细结果、证据截图和真机待办见 [docs/M0-REPORT.md](docs/M0-REPORT.md)；免费账号签名步骤见 [docs/M0-SIGNING.md](docs/M0-SIGNING.md)。

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
  LocalPod/                     # App 与 M0 spike UI
    App/                        # App、RootView、ImportCoordinator
    Spikes/Import/              # Spike A
    Spikes/Playback/            # Spike B
    Spikes/Inbox/               # Spike C
    Spikes/Benchmark/           # SwiftData 5k
    Spikes/Diagnostics/         # 签名/路径/数据诊断
    Resources/                  # 内置测试音频与 H.264/HEVC 视频
  LocalPodKit/                  # 可复用核心
    Sources/LocalPodKit/
    Tests/LocalPodKitTests/
  LocalPodUITests/              # M0 UI 测试
  docs/
    M0-REPORT.md
    M0-SIGNING.md
    screenshots/
```

## M0 调试启动参数

仅在 Debug 构建生效，用于模拟器/UI 测试：

| 参数 | 作用 |
| --- | --- |
| `--m0-reset-data` | 清空 SwiftData、Media、DemoInput、Import |
| `--m0-auto-demo-import` | 启动后导入 3 层 100 文件演示文件夹 |
| `--m0-auto-play-audio` | 启动后播放内置音频 |
| `--m0-auto-play-h264` | 启动后播放 H.264 视频 |
| `--m0-auto-play-hevc` | 启动后播放 HEVC 视频 |
| `--m0-auto-benchmark` | 打开 SwiftData 基准页 |
| `--m0-auto-inbox` | 打开收件箱页 |
| `--m0-seed-inbox` | 把内置音频复制到 `Documents/Import`，模拟 Finder 投递 |

示例：

```bash
xcrun simctl terminate booted com.localpod.app 2>/dev/null || true
xcrun simctl launch booted com.localpod.app --m0-reset-data --m0-auto-demo-import
```

## 当前边界

- 只支持 AVFoundation 可解码的音频/视频；不支持 MKV/AVI/OGG，不引入 VLCKit。
- 不做 Share Extension（免费 Apple ID 无 App Groups），导入走文件夹、文件选择、收件箱/Wi-Fi（P1）。
- 不做 CarPlay、StoreKit/IAP、订阅。
- M0 未实现 PiP、队列、播放列表、睡眠定时、iCloud 文件下载、SHA-256 去重、完整取消清理；这些按 `PLAN.md` 的 M1–M4 推进。
