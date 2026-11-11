# LocalPod P1（Wi-Fi 上传 + 智能播放列表）实施与验证报告

> 日期：2026-11-11
> 工程：`/Users/xlf/Dev/code/localpod`
> 结论：**P1 前两项——Wi-Fi 局域网网页上传、智能播放列表——代码完成；LocalPodKit 174 个单元/集成测试与全部 44 个 UI 测试（含 4 个新增 P1 用例）在模拟器通过。真实浏览器（Mac/Windows）上传、本地网络权限弹窗、二维码扫描、公共 Wi-Fi/防火墙场景、大文件上传与前后台切换的真机行为仍需确认，未计为已通过。**
> 计划基线：`PLAN.md` 2.2、3.6.8
> 产品边界：仅音频；视频文件只播放音轨；不做 Share Extension/App Group；本阶段不涉及 P1 其他项（章节/字幕、链接文件夹、回收站、备份、Shortcuts、通知、RSS、EQ 等）。

## 1. 环境

| 项 | 值 |
| --- | --- |
| macOS | 27.0 |
| Xcode | 27.1 (27A9275) |
| Swift | 6.4（Swift 6 语言模式） |
| iOS SDK | 27.1 |
| 模拟器 | iOS 27.1 · iPhone Duo（UDID `3055696C-BC73-4190-A3F7-EE0AC55F1EE6`） |
| 部署目标 | iOS 17.0，仅 iPhone |
| 依赖 | 零第三方；HTTP server 用 Network.framework `NWListener` 自写最小实现 |

## 2. Wi-Fi 局域网网页上传

### 2.1 架构与数据流

```text
电脑浏览器 ──HTTP(局域网)──▶ NWListener server（App 前台）
    GET /                     内嵌上传页（无 CDN、中英双语、PIN gate）
    GET /api/verify           PIN 校验（204）
    POST /api/upload          单文件原始字节流 + X-LocalPod-Pin / X-LocalPod-Path
    POST /api/complete        批次完成，生成 .localpod-complete 标记
        ▼
WiFiUploadStore（Application Support/WiFiUploads/<sessionID>/…）
    隐藏 .partial-<uuid> 流式写入 → fsync → 原子改名；同名加 -2/-3 后缀不覆盖
        ▼  sessionCompleted 事件
ImportCoordinator.importWiFiSession → 复用 FolderImportService/ImportEngine
    （扫描 → SHA-256 去重 → AVFoundation probe → 入库；来源标记 .wifi）
    另一导入运行中 → 排队；App 重启 → 启动恢复队列消费
```

与 PLAN 3.6.8 的差异：暂存目录用 `Application Support/WiFiUploads/<sessionID>/` 而不是 `Documents/Import/WiFi/`。`Documents/Import` 是会被自动扫描的收件箱，浏览器上传的会话目录（含隐藏 partial 文件）放进去会与稳定性检测/自动导入相互干扰；Application Support 对用户不可见，完成后由同一导入流水线消费，语义不变。

### 2.2 主要文件

| 文件 | 职责 |
| --- | --- |
| `LocalPodKit/Sources/LocalPodKit/WiFi/WiFiUploadStore.swift` | 会话/文件落盘、路径校验、限额、完成标记、崩溃清理 |
| `LocalPodKit/Sources/LocalPodKit/WiFi/WiFiUploadServer.swift` | NWListener HTTP/1.1 server、路由、PIN、限流、事件流 |
| `LocalPodKit/Sources/LocalPodKit/WiFi/WiFiUploadPage.swift` | 内嵌上传页（约 41 KB 单文件 HTML/CSS/JS） |
| `LocalPodKit/Sources/LocalPodKit/WiFi/WiFiPIN.swift` | SecRandomCopyBytes 生成 6 位 PIN、恒定时间比较、失败限流器 |
| `LocalPodKit/Sources/LocalPodKit/WiFi/WiFiNetworkAddress.swift` | 私网/回环地址策略、本机 IPv4 枚举 |
| `LocalPod/App/WiFiUploadController.swift` | 服务器生命周期（前台开启、离开/后台即停）、事件消费 |
| `LocalPod/App/WiFiUploadStorage.swift` | 共享 store（与启动恢复共用同一目录） |
| `LocalPod/Features/Settings/WiFiUploadView.swift` | 上传 UI：地址/复制/二维码/PIN/计数/停止/错误重试 |
| `LocalPod/App/ImportCoordinator.swift` | `.wifi` 运行类型、批次导入、排队、启动恢复、完成后清理 |

### 2.3 安全模型

- **仅本地网络**：远端地址必须是 loopback / RFC1918 私网 / 169.254 链路本地 / IPv6 ULA `fc00::/7` / `fe80::/10`，否则 403；服务器只在前台运行，进入后台或离开页面立即停止。
- **PIN**：6 位数字随机生成（SecRandomCopyBytes + 拒绝采样）；每个 `/api/*` 请求头 `X-LocalPod-Pin` 恒定时间比较；同一主机 8 次错误 PIN / 60 秒内进入 429 限流；上传页 PIN 存 sessionStorage，可更换。
- **路径防线**（写入前全部拒绝）：绝对路径、反斜杠、空组件、`.`/`..`、隐藏组件、冒号、控制字符、组件 >200 B、路径 >1 KB、深度 >16；HTTP 层只做一次 percent-decode，store 再复核标准化路径位于会话目录内。UI 测试验证 `..%2Fescape.mp3` 在 HTTP 边界被 400 拒绝且未创建任何文件。
- **限额**：单文件 8 GiB、单会话 32 GiB、20,000 文件（含在途预留）；`Content-Length` 必填、chunked 501、收满即停，字节数不匹配删除 partial 并报错。
- **页面安全**：CSP `default-src 'none'`（inline style/script、self connect、data: img）、`nosniff`、`no-referrer`、`DENY`、`Cache-Control: no-store`；页面不含 PIN、不含 `http://` 明文；文件名全部 `textContent` 渲染；无目录列表、无任意文件读取，上传文件在“Web 根”之外（服务器根本不提供文件服务）。
- **HTTP 解析**：请求头 ≤16 KiB、≤128 个；重复 `Content-Length`/`Transfer-Encoding`/`Host` 视为 smuggling 直接 400；一连接一请求（`Connection: close`）；30 秒空闲 watchdog 断连；最多 32 并发连接，状态路由经请求闸门串行化（同一时刻只有一个活跃 sink）。
- **明文 HTTP 说明**：按 PLAN 3.6.8 决定不做 HTTPS（自签证书体验差）；PIN + 私网地址策略是边界，页面明示“不要在公司/公共 Wi-Fi 开启”。

### 2.4 上传页（浏览器端）

- 中英自动（跟随浏览器语言，可切换）、PIN gate、文件夹选择（`webkitdirectory`，保留 `webkitRelativePath` 子目录）、多文件选择、递归拖拽（`webkitGetAsEntry`）。
- 顺序 XHR 上传，单文件 + 总进度条、取消、失败重试、完成后 `/api/complete`，可继续追加上传。
- 客户端过滤 `.DS_Store`、`Thumbs.db`、`desktop.ini`、`__MACOSX`、AppleDouble（`._`）等系统垃圾文件，避免整个文件夹批次因服务端严格路径校验而报错。

### 2.5 App 侧集成

- 入口：设置页「Wi-Fi 上传」与导入页「Wi-Fi 上传（电脑浏览器）」（`wifiUploadLink` / `wifiUploadImportLink`）。导入页入口放在「最近导入」区末尾：放在顶部导入区时（验收按钮之后）会让 M1 取消/强杀与 M5 英文导入三个既有 UI 用例稳定失败（启动导入不出现进度摘要，原因指向 NavigationLink 目标预实例化对首帧辅助功能快照的干扰），移到底部后全部恢复通过。
- 开启即创建会话并监听随机端口；显示真实局域网 IPv4 地址（回环地址不作为展示地址）、二维码（CoreImage）、PIN、已接收计数。
- 批次完成 → 立即进入现有导入流水线；若已有导入运行则排队（`queuedWiFiImports`），运行结束自动开始下一个。
- 启动恢复：`bootstrap` 先清理无标记的未完成会话，再把有 `.localpod-complete` 标记的目录按批次导入。上传批次导入完成（含用户取消）后删除暂存目录；只有抛错才保留给下次启动恢复。
- `--m0-reset-data` 同时清空 `WiFiUploads`。
- 本地网络权限：`project.yml` 配置 `NSLocalNetworkUsageDescription`（中英 `InfoPlist.strings` 均已生成进 bundle）；不用 Bonjour（PLAN 标注可选，未做），减少权限面。

## 3. 智能播放列表

### 3.1 设计

四个内置动态视图：**继续播放 / 未播完 / 最近添加 / 已播完**，外加「按合集筛选」浏览。核心决策：**不持久化**——每次渲染从资料库 + `PlaybackState` 现算（`SmartPlaylistEngine`），因此：

- 不需要 SwiftData schema V5 迁移（V1–V4 保持不变）；
- 删除条目/进度、重新导入永远不会留下“指向已删内容”的僵尸智能列表。

### 3.2 语义

| 智能列表 | 谓词 | 排序 |
| --- | --- | --- |
| 继续播放 | 有播放记录、未播完、`playCount > 0`、有限且 >0 的进度 | 最近播放优先 |
| 未播完 | 与继续播放同一谓词（全量列表 vs 短列表的区分仅在 UI） | 同上 |
| 最近添加 | `addedAt ≥ now − 30 天` | 添加时间倒序 |
| 已播完 | `isFinished == true` | 最近播放优先 |

共享规则：缺失条目（`isMissing`）全部排除；可选合集过滤（nil 表示不过滤，不是“无合集”）；非有限位置不可能命中继续播放；确定性排序（lastPlayedAt → addedAt → id）；`limit` 在过滤排序后应用。`SmartPlaylistEngine.entries/counts` 为纯函数，无 SwiftData 依赖。

### 3.3 文件与 UI

- `LocalPodKit/Sources/LocalPodKit/Library/SmartPlaylists.swift`：引擎 + 值类型快照（`SmartPlaylistEntry/Playback`）。
- `LocalPod/Features/Playlists/SmartPlaylistViews.swift`：播放列表页新增智能列表区（位于用户播放列表之后，避免影响既有 M3 测试布局）、智能列表详情（播放全部/随机、合集筛选菜单、进度条/已播完徽标/添加日期行）、按合集浏览。
- 所有文案走 `L10n` 语义键，中英 `.strings` 已由 `Tools/generate_localization.py` 重新生成。

## 4. 自动化验证结果

### 4.1 LocalPodKit 单元/集成测试

```bash
cd LocalPodKit && swift test
```

```text
Executed 174 tests, with 0 failures (0 unexpected) in 9.614 seconds
```

- 基线 M0–M5 142 个全部保留通过。
- 新增 Wi-Fi 32 个：store 18（路径校验/限额/冲突后缀/完成标记/崩溃清理/sink 字节流与幂等）、PIN 4、地址策略 4、HTTP 解析器 4（含 smuggling 拒绝）、server 集成 2。
- **真实回环端到端**（非 mock）：启动 → GET / 校验 CSP 等安全头且页面不含 PIN → 401/204 PIN 流程 → 恶意路径 400 → 嵌套目录上传 201 → uploadFinished 事件 → complete 200 → sessionCompleted 事件与建议合集名 `Course` → 磁盘字节逐一比对 → 标记与下一个活跃会话验证。另一条验证 8 次错误 PIN 后 429。
- 新增智能播放列表 14 个：四种谓词边界（30 天窗口边界、非有限位置、缺失排除、合集过滤、limit 语义）、排序确定性、counts 与 entries 一致。
- 上传页内嵌 JS 通过 `node --check` 语法校验。

### 4.2 UI 测试

新增 4 个用例：

| 用例 | 验证内容 |
| --- | --- |
| `P1SmartPlaylistUITests.testSmartPlaylistCountsAndContinueListening` | 种子数据下四个智能列表计数 1/1/1/3；继续播放含进行中的 C、排除已播完 B 与未播放 A |
| `P1SmartPlaylistUITests.testFinishedListAndCollectionFilter` | 已播完列表只含 B；按合集筛选“智能合集 A”只含 A/C，不含合集 B 的 B |
| `P1WiFiUITests.testWiFiUploadScreenStartsShowsPINURLAndStops` | Debug 无缝（`--p1-wifi-demo`，不触发本地网络权限）开启后状态/PIN 246810/URL/二维码齐全，停止后回到空闲 |
| `P1WiFiUITests.testCompletedUploadIsImportedOnLaunch` | `--p1-wifi-staged-upload` 预置已完成批次 → 启动恢复导入，资料库出现“Wi-Fi 示例” |

全量回归（同一次运行，2026-11-11）：

```text
M0 4 + M1 5 + M2 5 + M3 6 + M4 3 + M5 7 + 交付 3 + 签名 2 + 性能 2 + 本地化 3 + P1 4
= 44 个测试
```

最终结果见第 8 节“运行记录”。

### 4.3 构建

- 模拟器 Debug：**BUILD SUCCEEDED**（P1 UI 测试即在该构建上执行）。
- 生成产物核验：`Info.plist` 含中文 `NSLocalNetworkUsageDescription`；`en.lproj`/`zh-Hans.lproj` 的 `InfoPlist.strings` 均已打进展。

### 4.4 截图（第三轮全量回归运行中自动捕获）

| 文件（`docs/screenshots/`） | 内容 |
| --- | --- |
| `P1-smart-continue.png` | 继续播放列表：进行中的「队列测试 C」（6 秒 / 0:20 进度条）、播放全部/随机播放、合集筛选 |
| `P1-smart-finished.png` | 已播完列表：只含已播完条目（含已播完徽标） |
| `P1-smart-collection.png` | 智能列表按合集筛选视图 |
| `P1-wifi-running.png` | Wi-Fi 上传运行中：二维码、已接收文件计数、停止按钮、前台/可信 Wi-Fi 提示 |
| `P1-wifi-stopped.png` | 停止后回到空闲状态（重新开启按钮） |
| `P1-wifi-recovered-import.png` | 预置已完成批次启动恢复后，资料库出现「Wi-Fi 示例」 |

## 5. 关键实现说明

- **服务器生命周期**：`WiFiUploadController` 显式持有 `WiFiUploadServer`（非全局单例）；`onDisappear`/`scenePhase == .background` 即停止；`start()` 带代际（generation）保护，快速开关不会串状态。
- **事件驱动 UI**：`uploadFinished` 累加计数与最近文件名；`sessionCompleted` 回调 `ImportCoordinator`；`failed` 显示错误并提供重试。
- **启动恢复与排队共用一条路**：`recoverWiFiUploads` 与浏览器实时完成都调 `importWiFiSession`；`isRunning` 时入队，`finish` 后由 `startNextQueuedWiFiImportIfNeeded` 消费——浏览器批次永远不会丢，也永远不会与进行中的导入并发写库。
- **完成后清理语义**：导入成功或用户取消都删除暂存目录（用户主动取消的批次不应在下次启动复活）；只有抛错（磁盘/数据库失败）才保留，交给启动恢复重试。
- **UI 稳定性**：二维码区块移到 PIN 之前，减少长列表下元素滚出屏幕；UI 测试的 `reveal()` 兜底滚动。

## 6. 待真机验证（未计为通过）

- [ ] iPhone 与 Mac/Windows 处于同一 Wi-Fi：浏览器打开地址、输入 PIN、上传真实文件夹（含中文文件名/深层目录/数百文件），导入成功且结构正确。
- [ ] iOS 本地网络权限弹窗真实出现、文案正确；拒绝后 App 内有可行动的错误提示。
- [ ] 二维码从电脑/另一台手机扫描可打开上传页。
- [ ] 大文件（≥1 GB）上传的耗时、进度与手机发热/休眠表现；上传中锁屏（服务器应停止）后的浏览器错误提示。
- [ ] 公司/公共 Wi-Fi（AP 隔离）下浏览器无法访问的提示是否足以引导用户。
- [ ] VPN/代理开启时地址选择与可达性。
- [ ] 真机后台切换：上传中回桌面/切 App → 服务器停止、已传文件保留并可恢复导入。
- [ ] 免费 Apple ID 真机安装后本地网络权限与上传全流程（依赖 M0 真机签名步骤）。

## 7. 已知限制

- 无 TLS；PIN + 私网策略是唯一边界，页面/文案已提示不要在不受信 Wi-Fi 使用。
- 上传/完成路由串行化：一次只有一个活跃上传（与页面的顺序上传一致；多浏览器并发时后者等待）。
- PIN 限流是每 server 实例内存状态，重启 App 后清零。
- `maxTotalBytes` 按单个上传会话计，不跨已保留的已完成批次累计。
- 服务器广告地址只枚举 IPv4 私网/链路本地，无 IPv6 URL 与 Bonjour 发现；取不到私网地址时回退 127.0.0.1（UI 不把回环地址当展示地址，此时显示“暂无法获取局域网地址”）。
- 上传页不能恢复刷新前的上传进度（刷新后 PIN 保留，文件需重选）。
- 空闲超时直接断连（无 408 响应）；`requestTimeout` 错误 case 当前不会实际抛出。
- 智能播放列表每次渲染全量计算（`@Query` 快照 + 纯函数），在数千条目规模下成本可忽略；若未来十万级条目出现卡顿再引入缓存。

## 8. 运行记录

- LocalPodKit：`swift test` → **174 tests, 0 failures（9.614 s）**，2026-11-11。
- 模拟器 Debug 构建：`xcodebuild -scheme LocalPod -destination 'id=3055696C-BC73-4190-A3F7-EE0AC55F1EE6' build` → **BUILD SUCCEEDED**。
- P1 定向 UI：`-only-testing:LocalPodUITests/P1SmartPlaylistUITests -only-testing:LocalPodUITests/P1WiFiUITests` → 首轮发现 Wi-Fi 详情页二维码滚出屏幕，调整区块顺序后通过。
- 全量 UI 回归第一轮（44 个）：41 通过；M1 取消/强杀与 M5 英文导入 3 个用例失败。二分定位为导入页顶部 Wi-Fi NavigationLink 所致（基线无 P1 改动通过；恢复 P1 改动失败；仅移除/下移该链接通过），把链接移到「最近导入」区末尾后 3 个用例定向复跑全部通过。
- 全量 UI 回归第二轮：44 个用例，41 通过；P1 Wi-Fi 两个用例的 `reveal()` 滚动辅助在设置页长列表上不稳定（先 `wifiUploadLink` 后 `wifiReceivedCount`，两轮失败点不同）→ 重写 `reveal()`（逐次滑动 + 每次滑动后检查可命中性，方向只在整轮结束后反转），定向复跑通过。
- 全量 UI 回归第三轮（最终）：**44 个测试全部通过，0 失败（1120.6 秒，TEST SUCCEEDED）**，2026-11-11。

```text
Executed 44 tests, with 0 failures (0 unexpected) in 1120.583 (1120.641) seconds
```

## 9. 复现命令

```bash
cd /Users/xlf/Dev/code/localpod

# 核心测试
cd LocalPodKit && swift test && cd ..

# 生成工程（修改 project.yml 或新增文件后）
xcodegen generate

# P1 定向 UI 测试
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=3055696C-BC73-4190-A3F7-EE0AC55F1EE6' \
  -only-testing:LocalPodUITests/P1SmartPlaylistUITests \
  -only-testing:LocalPodUITests/P1WiFiUITests

# 全部 UI 回归
xcodebuild test -project LocalPod.xcodeproj -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=3055696C-BC73-4190-A3F7-EE0AC55F1EE6'
```

> Debug 启动参数：`--p1-wifi-demo`（演示状态，不发真实网络）、`--p1-wifi-staged-upload`（预置已完成批次验证启动恢复）、`--p1-seed-smart-playlists`（智能列表种子）；均仅 Debug 构建生效，Release 不包含。
