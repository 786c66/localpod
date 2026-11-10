# LocalPod M4 实施与验证报告

> 日期：2026-11-10
> 工程：`/Users/xlf/Dev/code/localpod`
> 结论：**M4「当前渠道导入」代码完成；打开方式/收件箱稳定性/去重/统一报告/失败重试在模拟器自动化中通过。真实 AirDrop、文件 App「用 LocalPod 打开」、Finder 数据线拖入、真实 iCloud 占位文件、大文件夹打开方式的真机行为仍需确认，未计为已通过。**
> 计划基线：`PLAN.md` 5.6
> 产品边界：仅音频；视频文件只播放音轨；不做 Share Extension、App Group、Wi-Fi 上传（P1）。

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.0.1 (26A434) |
| Xcode | 27.1 (27A9275) |
| Swift | 6.4（Swift 6 语言模式） |
| iOS SDK | 27.1 |
| 模拟器 | iOS 27.1 · iPhone Duo（UDID `3055696C-BC73-4190-A3F7-EE0AC55F1EE6`） |
| 部署目标 | iOS 17.0，仅 iPhone |
| 签名 | 模拟器 ad-hoc；无 App Group/entitlements；真机免费账号见 `docs/M0-DEVICE-CHECKLIST.md` |

## 2. M4 交付

| 交付 | 状态 | 说明 |
| --- | --- | --- |
| 打开方式/AirDrop/文档类型 | 完成（模拟器） | `CFBundleDocumentTypes` 声明 `public.audio`、`public.movie`、`public.folder`；`.onOpenURL` 进入同一收件箱/导入流水线；来源标记 `.openIn` |
| 收件箱扫描 + 稳定性检测 | 完成 | `Documents/Import` 在启动、回前台及前台每约 2 秒扫描；`ImportInboxStability` 要求两次间隔 ≥1 秒观察的递归元数据一致，且最新 mtime 静默 ≥2 秒；未稳定文件不导入 |
| 防半截导入 | 完成 | 打开方式先复制到隐藏临时项再原子重命名；引擎复制后校验实际字节数与扫描大小，不一致记 `copyFailed` 并保留来源；启动清理崩溃残留 |
| 渠道来源 / 统一流水线 | 完成 | 文件夹、收件箱、外部打开均走 `FolderImportService`/`ImportEngine`，共享扫描、SHA-256 去重、进度和错误分类；Finder/收件箱为 `.finder`，打开方式为 `.openIn` |
| 统一汇总报告 | 完成 | 一次运行聚合所有 URL 的导入/重复/不支持/失败/字节数，写运行级 JSON（含各 URL 的 `reportPaths`），收件箱页可查看路径 |
| 失败重试 / 不支持隔离 | 完成 | 失败项保留并暂停自动重试，提供「重试失败」；顶层不支持文件移入隐藏 `.Skipped`，不进入导入、不反复重扫；新文件或手动重试可恢复 |
| 免费账号签名 | 结构满足 | 工程无 entitlements/App Group；`generic/platform=iOS` 不签名构建通过；实际免费账号安装仍需真机步骤 |
| 测试与文档 | 完成 | LocalPodKit 110 个测试；M4 UI 3 个；全量 UI 回归 23 个；本报告、PLAN 勾选、README、截图 |

主要新增/修改文件：

- `LocalPodKit/Sources/LocalPodKit/Import/ImportInboxStability.swift`：递归稳定性跟踪（首见不稳定、间隔观察、静默期、隐藏项跳过）。
- `LocalPodKit/Sources/LocalPodKit/Import/ImportInbox.swift`：原子暂存、失败清理、崩溃残留清理。
- `LocalPodKit/Sources/LocalPodKit/Import/ImportEngine.swift`：复制字节数与扫描大小校验。
- `LocalPod/App/ImportCoordinator.swift`：稳定性扫描、前台轮询、打开方式排队、聚合报告、隔离与重试。
- `LocalPod/App/RootView.swift`：前后台轮询任务、M4 调试启动参数。
- `LocalPod/App/M4DebugSupport.swift`：打开方式/慢速写入/不支持文件测试夹具（仅 Debug）。
- `LocalPod/Spikes/Inbox/InboxView.swift`：未稳定数、隔离数、重试入口、运行报告路径。
- `LocalPod/Info.plist` / `project.yml`：新增 `public.folder` 文档类型。
- 测试：`ImportInboxStabilityTests`、`ImportInboxTests`、`ImportEngineTests`、`M4UITests`。

## 3. 验收标准对照

| # | PLAN 5.6 验收项 | 结果 | 证据 |
| --- | --- | --- | --- |
| 1 | “用 LocalPod 打开”/AirDrop 到 Files：能进入导入并成功 | **通过（模拟器调用真实 onOpenURL 路径）** | `M4UITests.testOpenInImportAndDedup`：外部临时文件经 `handleOpenURL` 原子暂存并导入，来源标记“外部打开”；再次打开同内容只记重复，资料库仍 1 条 |
| 2 | Finder 拖入 `Documents/Import`：前台自动导入；复制中的文件不会被半截导入 | **通过（模拟器）** | `M4UITests.testForegroundInboxWaitsForStableFile`：5.6 秒分块写入期间保持未稳定、不导入；写完后自动导入一次。`ImportInboxStabilityTests` 覆盖首见不稳定、间隔观察、mtime/size/文件夹变化重置 |
| 3 | 所有 MVP 渠道统一去重/进度/报告 | **通过（模拟器）** | 所有渠道共用 `FolderImportService`/`ImportEngine`；`testOpenInImportAndDedup` 验证去重；运行级 JSON 聚合各 URL 计数与 `reportPaths`；模拟器手动启动确认 `.openIn` 来源与报告 |
| 4 | 免费账号签名/安装不因缺少 App Group entitlement 失败 | **结构满足，真机安装待验** | 无 `.entitlements`、无 App Group；`xcodebuild -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` 通过；实际免费账号签名安装未在本会话执行 |

> M4 报告只把模拟器可自动化的部分计为通过；真实 AirDrop/Files/Finder/iCloud 列入第 6 节。

## 4. 自动化结果

### 4.1 LocalPodKit 单元/集成测试

命令：

```bash
cd LocalPodKit
swift test
```

结果：

```text
Executed 110 tests, with 0 failures in 9.627 seconds
```

M4 新增覆盖：

- `ImportInboxStabilityTests`（12）：首见不稳定、第二次观察稳定、观察间隔、静默期、mtime/size 变化重置、文件夹树变化、空文件夹后续写入、频繁观察不推迟稳定、隐藏项忽略、不稳定文件不删除。
- `ImportInboxTests`（5，新增 3）：文件夹暂存、失败不留半截/临时项、旧临时项清理。
- `ImportEngineTests`（11，新增 1）：扫描大小与实际复制字节不一致时记 `copyFailed`、不导入、不删除来源。
- 既有 94 个 M0–M3 测试全部保留通过。

### 4.2 UI 测试

```text
M4UITests: 3 tests, 0 failures, 83.4 seconds（全量回归中）
M0UITests/testInboxImportFromFinderPath: 1 test, 0 failures, 8.1 seconds
```

| 用例 | 验证内容 |
| --- | --- |
| `testOpenInImportAndDedup` | 打开方式导入成功、来源“外部打开”、运行报告路径；再次打开同内容只记重复，资料库不新增 |
| `testForegroundInboxWaitsForStableFile` | 前台分块写入期间不导入；稳定后自动导入且仅一次 |
| `testUnsupportedInboxFileIsQuarantined` | 不支持顶层文件移入 `.Skipped`，待处理归零、资料库不变；重启后仍不导入 |

全量回归（同一次运行）：

```text
M0UITests: 4 tests, 0 failures, 47.2 seconds
M1UITests: 5 tests, 0 failures, 90.2 seconds
M2UITests: 5 tests, 0 failures, 102.4 seconds
M3UITests: 6 tests, 0 failures, 412.0 seconds
M4UITests: 3 tests, 0 failures, 83.4 seconds
合计 23 tests, 0 failures, 735.2 seconds（2026-11-11 00:05）
```

### 4.3 截图

| 截图 | 内容 |
| --- | --- |
| `screenshots/M4-open-in.png` | 打开方式导入完成：聚合结果与运行报告路径 |
| `screenshots/M4-foreground-growing.png` | 前台写入中：待处理 1、未稳定 1、无导入结果 |
| `screenshots/M4-foreground-imported.png` | 写入完成并自动导入后的收件箱结果 |
| `screenshots/M4-quarantine.png` | 不支持文件已隔离，待处理 0 |

### 4.4 构建

- 模拟器 Debug：定向 M4 UI 测试构建与执行成功。
- `generic/platform=iOS` Debug、`CODE_SIGNING_ALLOWED=NO`：**BUILD SUCCEEDED**（验证真机架构编译，不做签名安装）。

## 5. 关键实现说明

- **稳定性判定**：`ImportInboxStability` 以路径为键保存上次观察。首次观察永不稳定；仅当递归元数据连续一致、距首次一致观察 ≥1 秒、最新 mtime 距当前 ≥2 秒时才输出稳定 URL。文件看 size+mtime；文件夹看所有目录项（含空目录）的相对路径、size、mtime。频繁轮询不会推迟稳定时间。
- **隐藏临时项**：`ImportInbox.stage` 先复制到 `.localpod-stage-<UUID>`，成功后原子移动到唯一最终名；失败删除临时项。收件箱扫描跳过隐藏项，因此复制中/崩溃残留不会被当成待导入文件。启动时清理超过 1 小时的残留。
- **引擎防线**：扫描后源文件仍可能变化；复制完成后比较 SHA 计算字节数与扫描大小，不一致立即删除暂存 part、记 `copyFailed`，由协调器保留来源供重试。
- **前台轮询**：`RootView` 在 `.active` 时每 2 秒触发一次轻量扫描；与启动/回前台钩子共用 `isObservingInbox` 串行化，运行中不启动第二次。稳定性状态跨轮询保留。
- **打开方式排队**：`handleOpenURL` 原子暂存后立即导入；若已有任务则进入队列，`finish` 后再扫描消费，避免丢失并发打开。
- **汇总报告**：收件箱一次运行可能包含多个 URL；协调器累加各报告计数，写 `ImportReports/<时间>-run-<UUID>.json`，内含每个 URL 的分类计数与 `reportPaths`；DB 仍按每个 URL 写 `ImportSession`。
- **隔离与重试**：顶层不支持文件在稳定性确认后移入隐藏 `.Skipped`，不进入导入；支持文件失败则保留，暂停 2 秒轮询的自动重试并显示“重试失败”。新顶层文件出现会解除暂停，干净运行后旧失败获得一次自动重试。
- **来源标记**：Finder/收件箱 `.finder`，外部打开 `.openIn`；资料库详情显示来源。
- **免费账号**：未引入 App Group/entitlements；工程保持单一 App target，签名配置不变。

## 6. 待真机验证（未计为通过）

- [ ] 文件 App 长按音频/视频 →「共享」→ LocalPod，真实打开方式进入导入并成功。
- [ ] AirDrop 音频/视频到 iPhone 后选择 LocalPod，导入成功、来源正确。
- [ ] 数据线 Finder → 文件 → LocalPod → Import 拖入文件：前台自动导入；大文件复制过程中不出现在资料库。
- [ ] 真实 iCloud 未下载占位文件：下载、字节校验、进度与取消行为。
- [ ] 打开方式选择大文件夹时的主线程卡顿/内存占用（当前暂存为同步复制）。
- [ ] 免费 Apple ID 真机签名安装，确认不因缺少 App Group entitlement 失败。
- [ ] 真实设备上 `.Skipped` 隔离目录、重试失败与重启后的行为。
- [ ] 后台/锁屏时收到打开方式文件，回前台后的导入时机。
- [ ] 最老 iOS 17 真机上的文档类型注册与收件箱轮询耗电。

## 7. 已知限制

- 打开方式暂存使用同步 `copyItem`，超大文件夹可能短暂阻塞主线程；UI 无进度。
- 多 URL 收件箱运行期间，进度区显示当前 URL 的文件数/字节数；整批聚合计数在运行结束后显示，运行级报告另行落盘。
- 打开方式失败项的来源标记只保存在内存；重启后该残留项按 Finder 来源重试（成功流程来源正确）。
- 自动重试暂停状态只保存在内存；重启后失败项会自动再试一次，然后再次暂停。
- 只隔离顶层不支持文件；仅含不支持文件的文件夹会保留并暂停自动重试，需手动重试或移走。
- 稳定性检测依赖文件系统 size/mtime；不支持/异常文件系统可能一直不稳定，保留在收件箱。
- 不做 Share Extension、App Group、Wi-Fi 上传（P1）；不做视频画面。
- 真实 AirDrop/Files/Finder/iCloud 行为未在模拟器自动化覆盖。

## 8. 复现命令

```bash
cd /Users/xlf/Dev/code/localpod

# 核心测试
cd LocalPodKit && swift test && cd ..

# 生成工程（修改 project.yml 或新增文件后）
xcodegen generate

# M4 定向 UI 测试
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>' \
  -only-testing:LocalPodUITests/M4UITests \
  -only-testing:LocalPodUITests/M0UITests/testInboxImportFromFinderPath

# 全部 UI 回归（M0–M4 共 23 条）
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UDID>'
```

> 调试启动参数：`--m4-auto-open-in`、`--m4-foreground-write-inbox`、`--m4-seed-unsupported-inbox`（仅 Debug）。
