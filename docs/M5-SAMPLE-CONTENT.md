# M5 内置示例内容

## 概述

LocalPod 在 App 包内附带 3 段短语音示例，用户可在「导入」页一键添加，也可在「设置 → 示例内容」中一键删除。示例走与用户文件夹完全相同的导入流水线（`FolderImportService` → `ImportEngine`），因此具备同样的 SHA-256 去重、进度、分类报告、JSON 导入报告和合集归类行为。

- 来源标记：`MediaSource.sample`（raw value `"sample"`，显示名「示例」）
- 合集名称：`示例内容`
- 存放位置：`LocalPod/Resources/SampleContent/`
- XcodeGen：该目录以 **folder reference**（`type: folder`）方式加入 App target，构建后为 `LocalPod.app/SampleContent/`
- 运行时只读取 App 包内文件，再复制到 App 沙盒的 `Application Support/Media`；不会访问沙盒外路径，也不联网

## 示例清单

| 文件 | 时长 | 大小 | 系统语音 | 文本 |
|---|---|---:|---|---|
| `01 欢迎使用.m4a` | 11.39 s | 72.4 KB | Tingting（zh_CN，普通话） | 欢迎使用 LocalPod。这是一段内置示例音频，由系统语音合成生成。你可以试听、加入队列，或创建播放列表。 |
| `02 专注呼吸.m4a` | 9.08 s | 46.6 KB | Eddy（Chinese (China mainland)，普通话） | 现在，请放松肩膀，慢慢呼吸。这段示例音频可以用来体验播放进度、倍速调整和睡眠定时。 |
| `03 睡前放松.m4a` | 9.18 s | 48.7 KB | Flo（Chinese (China mainland)，普通话） | 夜深了，让声音陪你安静下来。示例内容可以随时在设置中一键删除，不会影响你自己导入的资料。 |

3 个文件合计 176 KB（171,682 字节），远低于 5 MB 的包体预算。文件为 AAC、单声道、22.05 kHz、约 38–49 kbps，便于快速导入。

## 生成方式

全部素材由本机 macOS `say`（系统 TTS）生成 AIFF，再用系统 `afconvert` 转为 M4A/AAC。命令如下（在仓库根目录执行）：

```bash
mkdir -p /tmp/localpod-samples

say -v Tingting -r 165 -o /tmp/localpod-samples/01.aiff \
  "欢迎使用 LocalPod。这是一段内置示例音频，由系统语音合成生成。你可以试听、加入队列，或创建播放列表。"
say -v "Eddy (Chinese (China mainland))" -r 165 -o /tmp/localpod-samples/02.aiff \
  "现在，请放松肩膀，慢慢呼吸。这段示例音频可以用来体验播放进度、倍速调整和睡眠定时。"
say -v "Flo (Chinese (China mainland))" -r 165 -o /tmp/localpod-samples/03.aiff \
  "夜深了，让声音陪你安静下来。示例内容可以随时在设置中一键删除，不会影响你自己导入的资料。"

mkdir -p "LocalPod/Resources/SampleContent"
afconvert /tmp/localpod-samples/01.aiff \
  -o "LocalPod/Resources/SampleContent/01 欢迎使用.m4a" -f m4af -d aac -b 48000 -c 1
afconvert /tmp/localpod-samples/02.aiff \
  -o "LocalPod/Resources/SampleContent/02 专注呼吸.m4a" -f m4af -d aac -b 48000 -c 1
afconvert /tmp/localpod-samples/03.aiff \
  -o "LocalPod/Resources/SampleContent/03 睡前放松.m4a" -f m4af -d aac -b 48000 -c 1
```

> 重新生成时，若本机未安装上述语音，可在「系统设置 → 辅助功能 → 朗读内容」下载普通话语音，或换用 `say -v '?'` 中任意可用普通话语音；只要保留文案和文件名，导入/测试行为不变。

校验：

```bash
afinfo "LocalPod/Resources/SampleContent/01 欢迎使用.m4a" | grep -E "duration|Data format|bit rate"
du -sh "LocalPod/Resources/SampleContent"
```

## 来源与许可

- 文本为本项目自写文案，无第三方引用。
- 语音全部由 macOS 系统语音合成生成，不使用第三方录音、音乐、音效或版权素材。
- 不需要在运行时下载语音包；上述音频在构建时已固化进 App 包。
- 项目所有者可随 LocalPod 一起分发这些自生成音频。

## 添加、去重与删除

- 添加：`ImportCoordinator.importSampleContent(modelContext:)` 扫描 `Bundle.main/SampleContent`，经 `FolderImportService` 导入，合集为「示例内容」，来源为「示例」。
- 去重：导入引擎以文件 SHA-256 指纹判重。示例仍在资料库时再次添加会得到「导入 0 · 重复 3」，不会产生重复条目。
- 删除：`LibraryService.deleteSamples(in:)` 删除全部 `source == .sample` 的条目，并级联清理：
  - 媒体文件与封面文件；
  - `PlaybackState` 进度；
  - `QueueEntry` 队列条目，以及 `QueueState` 中指向示例的当前项/随机顺序；
  - `PlaylistEntry` 播放列表引用。
- 删除不会影响用户自己导入的内容；播放列表本身与「示例内容」合集记录会保留（合集为空，重新添加时复用）。
- 删除后再次点击「添加示例内容」会重新导入 3 条；由于指纹已随条目删除，不会被误判为重复。

## UI 入口与自动化标识

- 「导入」页「示例内容」分区：按钮 `sampleAddButton`（文案「添加示例内容」）。
- 「设置」页「示例内容」分区：
  - 数量文本 `sampleCountText`；
  - 删除按钮 `sampleDeleteButton`（destructive，二次确认）；
  - 确认弹窗按钮标识 `sampleDeleteConfirmButton`（标签「删除」）；
  - 删除结果 `sampleDeleteSummary`。
- 进度与分类结果复用现有 `importProgressText`、`importCategorySummary`、导入报告 UI。

## 真机说明与限制

- 示例完全离线，不依赖网络或设备额外语音下载；模拟器与真机行为一致。
- 免费 Apple ID 侧载需要每 7 天重新签名；重签不会清除已导入的示例或用户资料。卸载 App 会连同沙盒中的示例副本一起删除，重新安装后可再次添加。
- 若构建产物缺少 `SampleContent` 文件夹引用，「添加示例内容」按钮会被禁用，并在导入页给出错误说明；正常 `xcodegen generate` + Xcode 构建不会出现该情况。

## 包体清理

M5 同时从 App target 移除了不再被 App 或 M0–M5 UI 测试引用的 `demo-h264.mp4` 与 `demo-hevc.mp4`（共 1,801,912 字节，约 1.8 MB）。`LocalPodKit` 单测仍保留自己的 `Tests/.../Resources/demo-h264.mp4` 测试夹具，未删除。
