# LocalPod M0 技术验证报告

> 日期：2026-11-10
> 工程：`/Users/xlf/Dev/code/localpod`
> 结论：**M0 代码与模拟器验证完成；真机免费账号签名、锁屏控制、真实文件夹选择待真机执行。**
> 计划基线：`PLAN.md` v0.3（决策定稿版）

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.0.1 (26A434) |
| Xcode | 27.1 (27A9275) |
| Swift | 6.4（工程语言模式 Swift 6） |
| iOS SDK | 27.1 |
| 模拟器 | iOS 27.1 · iPhone Duo（本机运行时可用的 iPhone 设备类型） |
| 部署目标 | iOS 17.0，仅 iPhone（`UIDeviceFamily = [1]`） |
| 签名 | 模拟器 ad-hoc；真机免费账号待用户执行 |

## 2. 交付与验证状态

| M0 交付 | 状态 | 证据 |
| --- | --- | --- |
| Xcode 工程骨架：iOS 17、SwiftUI、SwiftData、`LocalPodKit` | 完成 | `LocalPod.xcodeproj`、`LocalPodKit/`；无 Share Extension、无 App Group |
| Spike A：文件夹扫描 + 分块复制 + 进度 | 完成（模拟器） | 3 层 100 文件；进度 100/100、16.5 MB / 16.5 MB；见 `screenshots/M0-import-100-result.png` |
| Spike B：音频后台/Now Playing/远程控制 | 部分完成 | 后台音频已验证：切到 Settings 再返回，播放时间 0:02 → 0:12；锁屏/远程控制待真机 |
| Spike B：AVPlayerViewController 视频 | 完成（模拟器） | H.264 与 HEVC 均有画面、全屏；见 `screenshots/M0-video-h264.png`、`M0-video-hevc.png` |
| Spike C：ImportInbox + 外部打开/Finder | 完成（模拟器） | 收件箱投递自动导入 1 个；`file://` 外部打开导入 1 个；见 `screenshots/M0-inbox-imported-from-finder.png`、`M0-open-in-external.png` |
| SwiftData 5k 插入/查询/列表 | 完成（模拟器） | 插入 5000 条 268 ms；列表可滚动；Mac 内存库 255 ms；见 `M0-benchmark-*.png` |
| 签名验证：免费 Apple ID/7 天/重签保留数据 | 待真机 | 诊断页已能读取真机 `embedded.mobileprovision` 的到期时间；步骤见 `M0-SIGNING.md` |
| 技术验证报告 | 完成 | 本文件 |

## 3. 验收清单对照

| 计划验收项 | M0 结果 |
| --- | --- |
| 真机最老支持机型选 3 层文件夹导入 100 文件，进度正确 | **模拟器等价路径完成**（内置 3 层 100 文件）；真实 `UIDocumentPickerViewController` 选文件夹 + 真机性能待执行 |
| 锁屏后音频继续，锁屏/控制中心能播放/暂停/快进 | **后台音频已完成**；锁屏与远程控制待真机（本机模拟器为无 GUI 的 headless 运行，无法锁屏） |
| 视频有画面、能全屏；H.264 与 HEVC 各一个 | **模拟器完成**；H.264/HEVC 截图见上；真机解码/全屏待执行 |
| “用 LocalPod 打开”/Finder 收件箱导入 1 个文件 | **模拟器完成**（收件箱 seed + `simctl openurl file://`） |
| SwiftData 5k 插入 + 列表滚动可接受 | **模拟器完成**：268 ms 插入；只做批处理/索引/分页优化，不换框架 |
| 免费账号安装/重签，重签后数据仍在；7 天过期行为确认 | **待真机执行**；诊断页可读出到期日与剩余天数 |
| 第 7 节决策全部确认 | 完成，无变更 |

## 4. 自动化结果

### 4.1 LocalPodKit 单元测试

```text
Executed 15 tests, with 0 failures
SwiftData benchmark (macOS, in-memory): insert 0.255s, count+page 0.003s
```

覆盖：3 层 100 文件扫描、自然排序、文件上限、单文件、UTType 过滤、分块复制、重名、路径穿越、Inbox、Media 相对路径、SwiftData 5k。

### 4.2 UI 测试

```text
Executed 4 tests, with 0 failures in 64.391 seconds
- testImport100FilesAndAudioPlayback
- testBenchmarkInsertAndList
- testH264AndHEVCVideoLaunch
- testInboxImportFromFinderPath
```

### 4.3 构建

```bash
# 模拟器
xcodebuild ... -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# 真机编译（未签名）
xcodebuild ... -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

两者均 **BUILD SUCCEEDED**，无工程源码 warning。

## 5. 技术发现与处理

1. **MediaPlayer 封面回调不在主线程**
   `MPMediaItemArtwork` 的 request handler 被 MediaPlayer 在后台 `accessQueue` 调用。若在 `@MainActor` 方法内直接构造闭包，Swift 6 会让闭包继承 MainActor 隔离，运行时触发 `dispatch_assert_queue_fail` / SIGTRAP（M0 UI 视频测试首次运行时复现）。
   处理：把绘制与闭包移到 `nonisolated static func makeArtwork`；修复后 H.264/HEVC UI 测试通过。

2. **AVAudioSession 激活阻塞主线程**
   模拟器测试出现 `AVAudioSession_iOS.mm:978` 警告。处理：`setCategory`/`setActive` 放到 `Task.detached`，不再在主线程激活；警告消失。

3. **`TARGETED_DEVICE_FAMILY` 默认值**
   XcodeGen 生成的 target 默认是 `1,2`，会生成 iPad 图标与 `UIDeviceFamily = [1,2]`。已在 target 与 project 设置显式改为 `1`，构建产物确认 `UIDeviceFamily = [1]`，符合“仅 iPhone”决策。

4. **文件共享边界**
   `UIFileSharingEnabled` 会暴露整个 `Documents`。当前 App 只在 `Documents/Import` 放收件箱；媒体库与 SwiftData 在 `Application Support`，已按计划执行。

5. **iCloud 未下载文件**
   M0 扫描器会识别 `ubiquitousItemDownloadingStatus != current` 并记 issue 后跳过，不阻塞整个导入；M1 再加下载进度/重试。

6. **模拟器限制**
   本机 Xcode 27.1 的 iOS 27.1 运行时只创建了 iPhone Duo 设备；无法在该环境做“最老 iOS 17 真机”和锁屏 GUI 操作。相关项保留为真机验收。

7. **取消路径**
   导入引擎支持 `Task.checkCancellation`、`.part` 临时文件与取消后保留已完成文件；M0 UI 有取消按钮，但未写自动化取消测试，M1 与强杀恢复一起补。

## 6. 证据截图

| 截图 | 内容 |
| --- | --- |
| `screenshots/M0-import-100-result.png` | 3 层 100 文件导入完成，100/100、16.5 MB / 16.5 MB |
| `screenshots/M0-audio-now-playing.png` | 内置音频播放，0:03 / 0:17，播放中 |
| `screenshots/M0-video-h264.png` | H.264 全屏画面 |
| `screenshots/M0-video-hevc.png` | HEVC 全屏画面 |
| `screenshots/M0-benchmark-insert-finished.png` | SwiftData 5000 条插入完成，268 ms |
| `screenshots/M0-benchmark-5000-list.png` | 5000 条 SwiftUI List |
| `screenshots/M0-inbox-imported-from-finder.png` | Documents/Import 收件箱自动导入 1 个，待处理 0 |
| `screenshots/M0-open-in-external.png` | `file://` 外部打开导入 1 个，来源“外部打开” |

## 7. 真机待执行清单（M0 剩余）

1. 用免费 Apple ID 安装主 App；记录 `Settings > General > VPN & Device Management` 中的描述文件到期时间。
2. 在文件 App / iCloud Drive 建一个 3 层、100 个媒体文件的文件夹，用“选择文件夹”导入；确认进度、取消、结果。
3. 播放音频后锁屏：确认继续播放、锁屏标题/封面/进度；控制中心播放/暂停、±15s、拖动。
4. 用 H.264 与 HEVC 各测一个真实文件：画面、全屏、旋转；确认后台默认暂停视频。
5. 文件 App 长按 → 共享 → LocalPod；Finder 文件共享拖入 Import；确认两条路径都能导入。
6. 等 7 天描述文件过期，确认 App 无法启动；用同一 Bundle ID 重新运行，确认 App 数据仍在（诊断页条目数/导入文件）。
7. 在最老支持机型上重跑 100 文件导入和 5k 列表，记录实际耗时/内存。

## 8. 对计划风险/决策的影响

- **SwiftData 性能风险下调**：模拟器 5k 插入 268 ms，Mac 内存库 255 ms；继续按计划只做批处理/索引/分页，不更换框架。
- **新增实现风险：Now Playing 封面回调线程**。已在 M0 修复；M2 扩充播放状态机时不要退回主线程隔离写法。
- **真机签名/锁屏仍是未关闭风险**：需要按第 7 节清单执行后才能把 M0 验收全部打勾。
- **无范围决策变更**：仍为免费自用侧载、无 Share Extension/App Group、无 CarPlay、无 VLCKit、Wi-Fi P1。
