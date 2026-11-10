# LocalPod 项目计划

> 版本：v0.3（决策定稿版）  
> 日期：2026-11-10  
> 状态：个人自用侧载版；决策已全部确认（见第 7 节）；M0 模拟器验证完成，真机签名/锁屏待验收（见 5.2.1）  
> 平台：iOS 17.0+（仅 iPhone）  
> 技术栈：Swift 6 / SwiftUI / SwiftData / AVFoundation  
> 分发：免费 Apple ID 自签名 + 侧载安装（7 天重签）；暂不上架 App Store  
> 周期：全职 9–10 周（含 1 周缓冲）；兼职 3–4 个月

---

## 0. 一页摘要

**一句话定位**：把用户自己合法持有的本地音视频文件，变成一个无需账号、播客式管理的私人媒体库。

**MVP 完成定义（一句话）**：用户把一个课程文件夹（含子目录）从 Files、Finder 或“用 LocalPod 打开”导入 iPhone，文件夹自动变成一个“节目/合集”；通勤时锁屏连续听，第二天从上次位置继续。**LocalPod 只做音频消费**：视频文件可以导入并播放其音轨，但不显示画面、不做全屏/旋转/PiP。

**已定决策（不再讨论）**

- **最低 iOS 17.0**，持久化使用 SwiftData；不讨论降级到 iOS 16。
- **仅 iPhone**：不构建 iPad 专属布局，不把 iPad 适配列入近期计划。
- **不做 CarPlay**：MVP 和近期都不做，不申请 entitlement。
- **完全免费、纯自用**：不接 StoreKit，不做内购/订阅；如未来上架，也按免费 App 处理。
- **当前分发方式**：免费 Apple ID 自签名 + 侧载安装，暂不上架 App Store；架构保留未来上架可能，不把“侧载”写死。
- **当前不做 Share Extension**（1A）：免费账号无 App Groups；用 Files/打开方式/Finder 替代，Wi-Fi 放 P1。
- **Wi-Fi 网页上传放 P1**（2）：不进 MVP。
- **只支持 AVFoundation 可播格式**（4）：不引入 VLCKit，不做 MKV/AVI/OGG 解码。
- **只播放音频，不显示视频画面**（M2 后明确）：视频文件保留导入与音轨播放；视频画面、全屏、旋转、PiP 和视频渲染全部不做，相关入口、后台模式和测试已从代码中移除。

**必须赢的三件事**

1. **文件夹递归导入**：从 Files/iCloud Drive 选一个文件夹，递归导入其中所有音频/视频；这是与 Pocket Casts 等产品最直接的差异。
2. **播客级播放体验**：Up Next、进度记忆、倍速、睡眠定时、后台播放、锁屏/控制中心，而不是“文件播放器”。
3. **导入渠道够全**：Files、iCloud Drive、AirDrop/打开方式、Finder 文件共享，外加 P1 的 Wi-Fi 网页上传。**分享扩展因免费账号不支持 App Groups，当前不启用**（见 3.6.6 与第 7 节）。

**推荐技术决策**

- 导入采用“**复制入库**”，不做长期外部引用；security-scoped bookmark 只用于 P1 的“链接文件夹/增量重扫”。
- 播放统一用 **AVPlayer**，只输出音频；音频用自定义 SwiftUI 播放器，不使用 `AVPlayerViewController`/视频渲染层；不用 AVAudioPlayer 作为主引擎。
- 持久化固定用 **SwiftData**；M0 用 5k 条数据做基准，只做批处理/索引/分页优化，不再讨论更换持久化框架。
- 当前侧载版**不建 Share Extension target**；用 Files 选择器、“用 LocalPod 打开”、AirDrop 到 Files、Finder 覆盖导入（Wi-Fi 放 P1）。代码保留 `ImportInbox` 抽象，未来上架/付费账号可加扩展，主架构不变。

**最大风险**：文件夹权限与 bookmark 失效、大文件导入的进度/内存/前台限制、iCloud 未下载文件、视频容器音轨兼容性、**免费账号 7 天签名过期/无 TestFlight/设备配额**。

**剩余待确认：无。** 四项范围决策已关闭：Share Extension 不做（A）、Wi-Fi 放 P1、仅 iPhone、不引入 VLCKit。可直接进入 M0。

---

## 1. 产品定位与核心差异

### 1.1 一句话定位

**LocalPod 不是文件浏览器，而是把本地文件夹变成私人播客库的播放器。**

用户导入的不是“一个文件”，而是“一个文件夹 = 一个节目”。App 负责递归扫描、去重、提取元数据、生成封面/缩略图，然后用播客的交互去消费这些内容。

### 1.2 目标用户与典型场景

| 用户 | 场景 | 关键诉求 |
|---|---|---|
| 通勤/健身人群 | 把课程、有声书、下载好的音频文件夹当播客听 | 锁屏播放、进度记忆、倍速、睡眠定时 |
| 语言学习者 | 一个课程一个文件夹，子目录是单元 | 递归导入、保留层级、按合集管理 |
| 课程录音用户 | 公开课、会议录像、手机拍摄的视频文件 | 能导入视频容器并只播音轨；后台连续听，不需要画面 |
| 隐私敏感用户 | 不想上传网盘、不想要账号 | 纯本地、无追踪、无订阅 |
| 播客重度用户 | 已有大量 MP3/MP4 存量文件 | 批量导入、Up Next、播客式播放 |

### 1.3 与竞品的差异

> 竞品功能以 2026-11 公开版本为准；实施前应再次复核，避免把营销判断写死。

| 能力 | Pocket Casts | VLC for iOS | Fileball | LocalPod |
|---|---|---|---|---|
| 核心定位 | RSS 播客 + 付费上传 | 万能本地/网络播放器 | 文件/网盘媒体库 | 本地音视频播客化 |
| 从 Files 递归导入整个文件夹 | 不是主路径（以 RSS + 付费上传为主） | 以文件浏览/单文件为主 | 以文件浏览/网络协议为主 | **核心能力** |
| 文件夹 = 节目/合集 | 无 | 无 | 部分 | **有** |
| Up Next / 播放队列 | 有（RSS 单集） | 弱 | 弱 | **有，且持久化** |
| 进度记忆 | 有 | 有（单文件） | 有 | **有（库级）** |
| 倍速 + 音调修正 | 有 | 有 | 有 | **有** |
| 睡眠定时 | 有 | 有 | 有 | **有** |
| 后台/锁屏/控制中心 | 有 | 有 | 有 | **有** |
| 本地视频文件 | 有限 | 强调画面 | 强调画面 | **可导入并仅播音轨（明确不渲染画面）** |
| 导入渠道完整度 | 弱 | 中 | 中 | **强** |
| 账号/订阅 | 需要 | 无 | 部分 | **无** |

### 1.4 核心差异点

1. **文件夹递归导入是主路径，不是隐藏功能。** 选择文件夹后展示扫描结果、总大小、文件数、失败/不支持清单，再开始导入。
2. **文件夹自动映射为“节目/合集”。** 顶层文件夹名 = 合集名；子目录保留为相对路径；单文件导入进入“单文件”合集。
3. **播客级播放，而不是文件级播放。** Up Next 持久化、自动下一集、继续播放、已播完阈值、倍速、睡眠定时、锁屏控制。
4. **导入渠道够全。** Files、iCloud Drive、AirDrop/打开方式、Finder 文件共享；Wi-Fi 网页上传放 P1；分享扩展当前因免费账号限制不启用，未来可加。
5. **完全免费、本地优先。** 无账号、无内购、无订阅、无追踪；默认不上传任何文件。
6. **音频优先的统一库。** 同一套资料库、队列、进度、播放列表管理音频与视频文件的音轨；视频只作为导入容器，不渲染画面、不做全屏/旋转/PiP。

### 1.5 产品边界与合规

- 只处理用户通过系统文件选择器、打开方式或局域网主动导入的文件；默认假设用户拥有或有权使用这些文件。
- **不提供**网页视频嗅探、流媒体下载、DRM 绕过、内置浏览器；这些也是未来上架时的高压线，当前自用同样不做。
- 不做公开内容平台、社交、评论、账号体系。
- 不在 App 内打包受版权保护的媒体；内置示例必须是公有领域素材或自录内容，并可一键删除。
- **当前为个人自用侧载版，不以 App Store 上架/审核为目标**；未来若上架，再补隐私清单、隐私政策和审核材料，核心架构不变。

---

## 2. 功能范围

### 2.1 MVP（P0）

| 模块 | 功能 | 验收要点 |
|---|---|---|
| 导入 | Files 单文件/多文件选择 | 从 Files 选择多个文件，全部进入导入队列 |
| 导入 | **Files 文件夹递归导入** | 选一个文件夹，递归导入所有音频/视频；显示文件数、总大小、进度 |
| 导入 | iCloud Drive | 未下载文件能触发下载并显示进度；断网有明确错误 |
| 导入 | AirDrop / “用 LocalPod 打开” | 通过 AirDrop 到 Files 或“用 LocalPod 打开”进入导入流程 |
| 导入 | Finder 文件共享收件箱 | Mac Finder 拖入 `Documents/Import`，App 前台自动导入 |
| 导入 | 进度、取消、失败报告 | 总进度 + 当前文件；取消后无脏数据；报告列出成功/重复/不支持/失败 |
| 导入 | 去重与不支持格式提示 | 重复导入不产生重复条目；不支持文件不静默丢失 |
| 资料库 | 列表/网格、搜索、音频/视频筛选、排序 | 1k–10k 条目下滚动流畅；自然排序 |
| 资料库 | 合集（顶层文件夹） | 文件夹导入后自动生成合集；可重命名 |
| 资料库 | 条目详情、删除、存储占用 | 删除同时删除文件；存储数字更新 |
| 资料库 | 缺失文件检测 | 启动时对账，标记缺失，可重新导入重链 |
| 播放 | 音频播放（视频仅音轨） | 音频锁屏可播；视频文件不显示画面 |
| 播放 | 进度记忆/继续播放 | 强退后恢复误差 ≤ 2 秒；已播完不自动续播 |
| 播放 | 0.5–3.0x 倍速 + 音调修正 | 人声不变调；切换后状态保持 |
| 播放 | 后台、锁屏、控制中心 | 播放/暂停/进度/±15s/下一集可用 |
| 播放 | AirPlay（音频） | 系统路由可用；不做视频全屏/PiP |
| 队列 | Up Next 持久化、下一首/加入队列、排序、清空 | 重启 App 后队列保留；自动下一集 |
| 播放列表 | 创建/重命名/删除/排序/播放 | 拖拽排序持久化；播放列表可整单入队 |
| 睡眠定时 | 5–90 分钟 + 本集结束 + 淡出 | 到点淡出暂停；后台仍生效 |
| 设置 | 默认倍速、跳过间隔、恢复策略、存储、关于 | 设置持久化；存储页能清理 |
| 引导 | 空状态、导入教程、支持格式 | 新用户 3 步内完成首次导入 |
| 质量 | 简体中文/英文、深色模式、Dynamic Type、基本 VoiceOver | 不截断、可操作、对比度达标 |

> **分享扩展不在当前 MVP**：免费 Apple ID（Personal Team）不支持 App Groups，扩展与主 App 无法共享容器，无法可靠交付文件。当前用 Files 选择器、“用 LocalPod 打开”、AirDrop 到 Files、Finder 替代；Wi-Fi 上传放 P1。代码保留 `ImportInbox` 抽象；未来使用付费账号或上架时再加 Share Extension（见 3.6.6、第 7 节）。

### 2.2 第二阶段（P1）

- **Wi-Fi 局域网网页上传**：浏览器拖文件夹上传、PIN、二维码。
- **链接文件夹 + 增量重扫**：持久化 security-scoped bookmark，重新扫描新增/删除文件。
- **智能播放列表**：继续播放、未播完、最近添加、已播完、按合集筛选。
- **章节与字幕**：内嵌章节、内嵌字幕、外挂 SRT/VTT（视频）。
- **回收站/最近删除**：删除后保留 7–30 天，可恢复。
- **备份/导出**：播放列表、进度、库清单导出 JSON；支持从备份恢复。
- **Shortcuts / Siri**：继续播放、打开合集；小组件需 App Groups，当前免费账号不做（见条件性功能）。
- **通知**：导入完成/失败通知。
- **RSS 订阅**：如果确认要做，复用播放器/队列，新增 Feed/Episode 模型与刷新逻辑。
- **视频增强**：手势控制、字幕样式、画面比例、后台仅音频开关。
- **音频增强**：EQ、音量增强、跳过静音（成本较高，谨慎）。

**条件性功能（当前免费账号不做，未来付费账号/上架再加）**：

- **Share Extension（分享扩展）**：需要 App Groups；免费 Personal Team 不支持。当前用“打开方式/Files/Finder”替代（Wi-Fi P1），未来加扩展时复用同一导入流水线。
- **Widget/小组件**：需要 App Groups 共享容器；当前免费账号不做。Shortcuts/Siri 等进程内集成不受影响。

### 2.3 明确不做（非目标）

- RSS 订阅的 MVP 版本（只留扩展位，不做 UI 和抓取）。
- 云同步/自建 iCloud 媒体库（MVP 不做；见 3.6.5）。
- **CarPlay：当前及近期都不做，不申请 entitlement。**
- **App Store 上架与审核材料：当前不做**；未来如需要，再补隐私清单/政策/审核材料，架构不变。
- **StoreKit、内购、订阅、付费墙：不接、不做。**
- **iPad 专属适配：不做**；只构建 iPhone 布局。
- **VLCKit / 第三方解码：不引入**；MKV/AVI/OGG 等导入时明确标记不支持。
- **Share Extension：当前不做**（免费账号无 App Groups），用打开方式/Files/Finder 替代；Wi-Fi 放 P1。
- 网页下载器、视频嗅探、浏览器、DRM 绕过。
- 转码、剪辑、格式转换、字幕压制。
- macOS/Windows/Android/Apple Watch 客户端。
- Chromecast、Sonos、DLNA 投屏（AirPlay 由系统提供）。
- SMB/WebDAV/DLNA 网络媒体库（P2 再评估，避免变成 Fileball 的竞品）。
- 照片图库导入（MVP 只走 Files；如需求强烈再评估权限文案）。
- 社交、账号、评论、广告、第三方分析 SDK。
- 直播、电台、RSS 之外的内容平台。

### 2.4 MVP 完成定义

你（主要自用）可以在 **10 分钟内**完成：

1. 在 Mac 上把课程文件夹拖进 Finder 里的 LocalPod，或从 iPhone Files 选中该文件夹；
2. 看到扫描结果、导入进度和最终报告；
3. 在资料库看到“课程名”合集和所有单集，元数据/时长正确；
4. 锁屏播放，锁屏和控制中心能暂停/继续/快进；
5. 第二天打开 App，从上次位置继续；
6. 点开一个视频文件，只播放音轨，App 不显示视频画面（按产品决策，不提供全屏/PiP）。

---

## 3. 技术架构

### 3.1 技术栈与版本

| 项 | 选择 | 说明 |
|---|---|---|
| 语言 | Swift 6 | 严格并发；核心逻辑用结构化并发 |
| UI | SwiftUI + Observation | iOS 17+ 用 `@Observable`；列表用 Lazy 容器 |
| 持久化 | **SwiftData（固定）** | iOS 17+；M0 基准只用于优化批处理/索引/分页，不更换框架 |
| 媒体 | AVFoundation | 音轨播放、探测、缩略图、AirPlay；不引入 AVKit 视频渲染 |
| 系统集成 | MediaPlayer | Now Playing、远程控制 |
| 文件类型 | UniformTypeIdentifiers | 文件夹/音频/视频筛选 |
| 哈希 | CryptoKit | SHA-256 指纹，导入时流式计算 |
| 网络 | Network.framework | Wi-Fi 上传（P1）和 Bonjour |
| 设备 | **仅 iPhone** | `TARGETED_DEVICE_FAMILY = 1`；不做 iPad 分栏/专属适配 |
| 日志 | OSLog | 分类日志；不上传 |
| 支付 | **无** | 不接 StoreKit，不做内购/订阅/付费墙 |
| 分发 | 免费 Apple ID 自签名 + 侧载 | 7 天 profile；无 App Groups/TestFlight；当前不上架 |
| 最低版本 | **iOS 17.0（已定）** | 不讨论 iOS 16 降级；SwiftData 固定 |
| 依赖 | MVP 零第三方；Wi-Fi P1 可引入轻量 HTTP server | 避免重依赖和隐私清单负担 |

### 3.2 工程结构

```text
localpod/
├── PLAN.md
├── LocalPod.xcodeproj
├── LocalPod/                       # App target
│   ├── App/                        # 入口、AppEnvironment、路由
│   ├── Features/
│   │   ├── Library/                # 资料库、合集、条目详情
│   │   ├── Player/                 # 音频播放器、队列、迷你播放器（无视频画面）
│   │   ├── Queue/                  # Up Next
│   │   ├── Playlists/
│   │   ├── Import/                 # 导入向导、进度、报告
│   │   ├── Settings/
│   │   └── Onboarding/
│   ├── UI/                         # 设计系统、通用组件
│   └── Resources/                  # Assets、String Catalog、示例内容
├── Packages/LocalPodKit/           # 可测试的领域/基础设施
│   ├── Sources/LocalPodKit/
│   │   ├── Models/                 # SwiftData 模型
│   │   ├── Persistence/            # ModelContainer、迁移、仓储
│   │   ├── Files/                  # 路径、存储、磁盘空间
│   │   ├── Import/                 # 扫描、复制、探测、去重
│   │   ├── Playback/               # 播放控制、队列、Now Playing
│   │   ├── Media/                  # 元数据、封面/缩略图
│   │   └── Support/                # 日志、错误、扩展
│   └── Tests/LocalPodKitTests/
├── LocalPodTests/
├── LocalPodUITests/
└── Tools/                          # 测试素材生成、脚本
```

说明：

- `LocalPodKit` 让导入/播放/模型可单测，也能被未来 Share Extension 复用。
- **当前不建 Share Extension target**：免费 Apple ID 无 App Groups，扩展无法与主 App 共享容器。未来若用付费账号或上架，再加 `LocalPodShareExtension/`，复用 `LocalPodKit` 的收件箱/模型类型，**不打开数据库**，主架构不变。
- 不为了“架构好看”过度分层；Feature 内部可以直接调用 Core 服务。

### 3.3 分层、并发与数据流

```text
Files / iCloud / AirDrop / Open in / Finder / Wi-Fi
                    │
                    ▼
        ImportInbox / DocumentPicker
                    │
                    ▼
 FolderScanner → ImportPlanner → CopyEngine(Staging) → MediaProbe → Deduper
                    │
                    ▼
              LibraryWriter（单写入）
                    │
                    ▼
   SwiftData：MediaItem / PlaybackState / Collection / Playlist / Queue
                    │
                    ▼
 PlaybackController（AVPlayer）→ AudioSession / NowPlaying / RemoteCommands
                    │
                    ▼
        SwiftUI：Library / Player / Queue / Playlist / Import
```

并发约定：

- **主线程**：SwiftUI、`PlaybackController`、`NowPlayingManager`、`SleepTimer`、用户交互。
- **Actor**：`ImportEngine`、`FolderScanner`、`ArtworkCache`；文件复制/哈希/探测全部离开主线程。
- **数据库**：导入在后台 `ModelActor` 分批提交；导入会话结束后通知主界面刷新（不要求半成品实时出现在资料库）。播放进度是独立小模型，主 context 节流保存（每 5–10 秒 + 暂停/切后台/切换条目时立即保存）。
- **进度事件**：用 `AsyncStream<ImportEvent>` 向 UI 推送；UI 侧 10Hz 节流，避免每字节刷新。
- **取消**：所有导入任务支持 `Task` 取消；取消后清理 staging，已提交批次保留，报告说明。
- **M0 性能门**：用 5k 条数据测 SwiftData 插入/查询/刷新；若主界面明显卡顿，只优化批处理/索引/分页/刷新策略，**不更换持久化框架**。

### 3.4 数据模型

#### `MediaItem`（媒体条目）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | 主键，同时用于文件名 |
| `title` | String | 优先元数据标题，回退文件名 |
| `sortTitle` | String? | 自然排序辅助（可选） |
| `originalFileName` | String | 原始文件名，仅展示/导出 |
| `relativePath` | String | 相对 App 容器的路径，如 `Media/<uuid>.mp3`；**绝不存绝对路径** |
| `fileSize` | Int64 | 字节 |
| `duration` | Double | 秒；探测前为 0 |
| `kind` | String | `audio` / `video`（原始字符串，便于迁移） |
| `container` | String? | mp3/m4a/mp4/mov 等 |
| `sourceType` | String | `files` / `icloud` / `openIn` / `finder` / `wifi`；`share` 预留（未来 Share Extension） |
| `sourceName` | String? | 来源文件夹名/来源 App 名 |
| `collectionID` | UUID? | 所属合集 |
| `relativeFolderPath` | String? | 文件夹内的相对层级，保留“单元/章节”结构 |
| `fingerprint` | String | SHA-256，唯一索引，用于去重和缺失重链 |
| `artworkKey` | String? | 封面/缩略图缓存 key |
| `addedAt` | Date | 导入时间 |
| `isMissing` | Bool | 文件对账失败时置 true |
| `isFavorite` | Bool | P1 可用；MVP 可留字段 |
| `notes` | String? | P1 |

#### `PlaybackState`（播放进度，独立小表）

| 字段 | 类型 | 说明 |
|---|---|---|
| `itemID` | UUID | 唯一，一对一 |
| `position` | Double | 秒 |
| `duration` | Double | 以播放器探测为准 |
| `isFinished` | Bool | 阈值：≥ 95% 或剩余 ≤ 30 秒 |
| `playCount` | Int | 播放次数 |
| `lastPlayedAt` | Date? | 用于“继续播放”排序 |
| `updatedAt` | Date | 写入时间 |

> 进度单独建表，避免每次播放进度更新都使 `MediaItem` 失效、导致资料库大列表重绘。

#### `Collection`（节目/合集）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | UUID | |
| `name` | String | 顶层文件夹名；单文件导入为“单文件” |
| `createdAt` | Date | |
| `sortOrder` | Int | 手动排序 |
| `defaultSpeed` | Double? | P1，按节目记忆倍速 |

#### `Playlist` / `PlaylistEntry`

| 实体 | 字段 | 说明 |
|---|---|---|
| `Playlist` | `id`, `name`, `createdAt`, `updatedAt`, `sortOrder` | 用户手动播放列表 |
| `PlaylistEntry` | `id`, `playlistID`, `itemID`, `position` | 显式 position；**不要依赖无序关系** |

#### `QueueEntry` / `QueueState`

| 实体 | 字段 | 说明 |
|---|---|---|
| `QueueEntry` | `id`, `itemID`, `position`, `addedAt` | Up Next 的持久化顺序 |
| `QueueState` | `currentItemID`, `shuffle`, `repeatMode`, `updatedAt` | 单例状态 |

#### `ImportSession` / `ImportIssue`

| 实体 | 字段 | 说明 |
|---|---|---|
| `ImportSession` | `id`, `startedAt`, `endedAt`, `sourceType`, `rootName`, `totalFiles`, `totalBytes`, `imported`, `skipped`, `failed`, `status`, `reportPath` | 导入历史/报告 |
| `ImportIssue` | `sessionID`, `fileName`, `reason`, `message` | 不支持/读取失败/重复等明细；MVP 可先落日志文件 |

关系与删除规则：

- `Collection 1—* MediaItem`；删除合集只解除关联，不默认删除文件（需二次确认）。
- `MediaItem 1—1 PlaybackState`；级联删除。
- `MediaItem 1—* PlaylistEntry / QueueEntry`；级联删除。
- `Playlist 1—* PlaylistEntry`；级联删除。
- `ImportSession 1—* ImportIssue`；级联删除。

索引与迁移：

- 唯一索引：`MediaItem.fingerprint`；`PlaybackState.itemID`；`QueueState` 单例。
- 常用索引：`addedAt`、`title`、`collectionID`；iOS 18+ 可用 SwiftData `#Index`，iOS 17 用查询优化/分页。
- 从第一天使用 `VersionedSchema` + 迁移计划；不要在未迁移的情况下重命名/删字段。
- 枚举一律存原始字符串，避免 Codable 枚举迁移麻烦。
- 不用 SwiftData 的“有序关系”（没有可靠内建支持）；排序一律显式 `position`。

### 3.5 文件存储、沙盒与备份

```text
<App 容器>/
├── Library/Application Support/
│   ├── Media/<uuid>.<ext>          # 媒体文件（不备份）
│   ├── LocalPod.store              # SwiftData（备份）
│   └── ImportReports/              # 导入报告（可选备份）
├── Documents/
│   ├── Import/                     # Finder / 打开方式收件箱（用户可见）
│   └── Inbox/                      # 系统“拷贝到 App”落点（如使用）
├── Library/Caches/
│   └── Artwork/<key>.jpg           # 封面/缩略图（可再生，不备份）
└── tmp/ImportStaging/<sessionID>/  # 导入暂存（崩溃后可清理）
```

> 当前侧载版**不使用 App Group**（免费 Apple ID 不支持）。未来若加 Share Extension，再增加 App Group `ShareInbox/`，主库仍由主 App 单写入。

关键规则：

- **绝不持久化绝对路径。** iOS App 容器路径在重装/恢复后可能变化；数据库只存相对路径，运行时拼绝对 URL。
- 媒体放 `Application Support/Media`，不放 `Documents`：`Documents` 默认进 iCloud 备份且对用户可见，媒体体积大，不适合备份。
- `Documents/Import` 仅作为“从 Finder/打开方式进来的收件箱”；导入完成后移到 `Media`，避免重复扫描和双份占用。
- 对 `Media`、`Caches/Artwork`、`Documents/Import` 设置 `isExcludedFromBackup = true`（目录级设置会作用于子项）。
- 数据库、播放列表、进度、设置**不主动排除备份**（是否随设备备份取决于系统/安装方式）；换机恢复后媒体缺失，用 `fingerprint` 重链，UI 显示“重新导入”提示。侧载场景不要只依赖系统备份，P1 提供显式导出。
- 文件保护：媒体目录使用默认的 `CompleteUntilFirstUserAuthentication` 或显式设置它；**不要用 `Complete`**，否则锁屏后台播放会读不到文件。
- 磁盘预检：导入前用 `volumeAvailableCapacityForImportantUsage` 估算可用空间，预留 200MB；空间不足时在开始前阻止并给出所需/可用数字。
- 删除：先删 DB 记录再删文件（或反过来并保证对账）；MVP 二次确认，P1 加回收站。
- 对账：启动/前台时对比 DB 记录与 `Media` 文件；缺失置 `isMissing`，孤儿文件移到 `Orphaned/` 并记录日志（P1 提供清理 UI）。

### 3.6 文件导入方案（核心）

#### 3.6.1 渠道矩阵

| 渠道 | 入口/关键 API | 处理位置 | 注意点 |
|---|---|---|---|
| Files 单/多文件 | `UIDocumentPickerViewController(forOpeningContentTypes:asCopy:false)`；`allowsMultipleSelection = true` | 主 App | 使用 security scope；逐文件复制 |
| Files 文件夹 | 同上，`UTType.folder`；`asCopy: false` | 主 App | 递归枚举；MVP 一次一个文件夹，P1 支持多选 |
| iCloud Drive | 同一个 document picker | 主 App | 未下载文件要触发下载并显示进度 |
| AirDrop / 打开方式 | `CFBundleDocumentTypes`；`scene(_:openURLContexts:)` / `onOpenURL` | 主 App | 区分“已拷贝到 Inbox”和“security-scoped 外部 URL” |
| Finder 文件共享 | `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` | 主 App | 扫 `Documents/Import`；等文件大小稳定后再导入 |
| Wi-Fi 网页上传（P1） | 内嵌 HTTP server + 浏览器 `webkitdirectory` | 主 App | 仅前台、局域网、PIN、路径清洗 |

> **分享扩展不在当前矩阵**：免费 Personal Team 不支持 App Groups，扩展无法把文件交给主 App。当前用“打开方式/Files/Finder”替代（Wi-Fi P1）；未来方案见 3.6.6。
>
> SwiftUI 的 `.fileImporter` 也能选文件夹，但不同 iOS 版本行为有差异；**文件夹导入用 UIKit 包装的 `UIDocumentPickerViewController`**，控制力更强。

#### 3.6.2 文件夹递归导入：步骤

1. **拿到 URL**：用户选中文件夹后，先 `startAccessingSecurityScopedResource()`，整个导入期间保持；结束时 `stopAccessingSecurityScopedResource()`（必须成对）。
2. **检查 iCloud 状态**：读取 `isUbiquitousItem` / `ubiquitousItemDownloadingStatus`；未下载则调用 `startDownloadingUbiquitousItem(at:)`，显示“正在从 iCloud 下载”，用 `NSMetadataQuery` 或状态轮询观察；离线/超时给明确错误。
3. **枚举**：`FileManager.enumerator(at:includingPropertiesForKeys:options:errorHandler:)`，预取 `isRegularFile`、`isDirectory`、`fileSize`、`contentType`、`isSymbolicLink`、`isPackage`、`creationDate`、iCloud 状态等 key；options 用 `.skipsHiddenFiles`、`.skipsPackageDescendants`。
4. **过滤**：
   - 跳过隐藏文件、包（`.app`、`.photoslibrary` 等）、符号链接；
   - 深度上限 32 层；文件数上限 20,000（超过提示分批导入）；
   - UTType 兼容 `.audio` / `.movie` / `.audiovisualContent`；无 content type 时回退扩展名，再交给探测阶段判断。
5. **生成计划**：按自然排序（`localizedStandardCompare`）排列；统计文件数、总字节、未知类型数；做磁盘预检；展示确认页（尤其是 >1GB 或 >1000 个文件）。
6. **复制/探测/提交**：进入 3.6.3 流水线。
7. **报告**：展示成功、重复、不支持、失败；失败项可重试；报告写入 `ImportReports/`。

实现细节：

- 用 enumerator 预取的 resource values，避免每个文件单独 `stat` 造成 I/O 放大。
- 保留相对路径（`relativeFolderPath`），但**不创建深层物理目录**；物理文件扁平放 `Media/<uuid>.<ext>`，层级只存数据库。这样移动/重命名/备份都简单。
- 文件名只用于展示；物理名用 UUID + 原扩展名，避免重名、非法字符、路径穿越。
- 对来自第三方 provider 的文件，逐个用 `NSFileCoordinator` 协调读取；单文件失败不影响整批。

#### 3.6.3 复制入库流水线

```text
扫描 → 计划 → 复制到 Staging（流式 SHA-256）→ 探测元数据/轨道 → 去重
→ 移动到 Media（原子 rename）→ 批量写 DB → 生成封面/缩略图 → 报告
```

1. **Staging**：每个导入会话使用 `tmp/ImportStaging/<sessionID>/`；复制先写这里，成功后再移动到 `Media`，保证不会出现“DB 有记录但文件半个”的状态。
2. **流式复制**：用 `FileHandle` 分块读写（1–4MB 缓冲），同时更新 SHA-256 和进度；内存占用与文件大小无关。`FileManager.copyItem` 更快但没有进度，不适合大文件 UX；可作为“小文件快速路径”。
3. **元数据探测**：`AVURLAsset` 异步加载 `duration`、`tracks`、`commonMetadata`、`isPlayable`；视频轨存在则 `kind = video`，否则 `audio`。iOS 16+ 用 async `load(...)`，不要用已废弃的同步属性。
4. **封面/缩略图**：音频取内嵌 artwork；视频用 `AVAssetImageGenerator` 取 1 秒处帧；生成 512×512 封面和列表缩略图，写 `Caches/Artwork`；失败用占位图。
5. **去重**：复制时计算 SHA-256；与现有 `fingerprint` 比较。若命中，删除 staging，记“重复”。可选优化：复制前用“文件大小 + 标题”做候选筛选，减少明显重复的复制。
6. **提交**：同一卷内 `moveItem` 到 `Media/<uuid>.<ext>`（原子 rename）；DB 每 50–100 条批量插入；插入失败则删除已移动文件。
7. **清理**：成功/失败/取消后删除 staging；App 启动时扫描并清理残留 staging。
8. **取消语义**：取消后停止新工作；已提交批次保留；当前文件和 staging 删除；报告说明“已导入 N 个，取消时丢弃 M 个”。
9. **崩溃语义**：DB 只提交完整批次；staging 启动时清理；`Media` 与 DB 对账处理孤儿文件。
10. **前台限制**：iOS 不允许普通 App 在后台长时间做本地复制。导入时保持前台，设置 `isIdleTimerDisabled = true` 防止锁屏；进入后台用 `beginBackgroundTask` 只够收尾当前文件，然后暂停，回前台继续。UI 必须明确提示“导入中请保持 App 在前台”。

#### 3.6.4 权限与 security-scoped bookmark

- 从 document picker 拿到的 URL 在 `asCopy: false` 时是 security-scoped；使用前 `startAccessingSecurityScopedResource()`，用完 `stopAccessingSecurityScopedResource()`。文件夹的 scope 覆盖其子项，但**不要长期持有**，只在扫描/复制期间持有。
- **MVP 的复制模式不持久化 bookmark**：复制完成后文件已在 App 容器内，不再依赖外部权限。只记录来源名称/类型用于展示。
- P1 的“链接文件夹/增量重扫”才需要持久化：
  - 用 `bookmarkData()` 创建 bookmark，存为数据库 `Data`；
  - 启动/重扫时 `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)`；
  - 检查 `bookmarkDataIsStale`，stale 时重新创建；解析失败或权限丢失时，UI 显示“重新授权”，让用户重新选择文件夹；
  - 重新授权后按相对路径/指纹匹配，尽量保留已有条目。
- iOS 上没有 macOS 的 `.withSecurityScope` 创建选项；iOS 的 document picker URL 自带作用域语义，核心是 `startAccessingSecurityScopedResource()` 与 bookmark 解析。不要照抄 macOS 代码。
- bookmark 会因文件/文件夹被移动、重命名、provider 更换、App 重装、iCloud 状态变化而失效；**这是不能把“外部引用”作为 MVP 主路径的原因**。复制入库最稳。
- 如果未来做外部引用，播放期间必须持有 scope；锁屏后台播放时 scope 丢失会直接断播，这也是复制模式的另一个优势。

#### 3.6.5 iCloud Drive 与第三方 provider

- **MVP 不需要 iCloud entitlement**：document picker 由系统进程提供文件访问，选 iCloud Drive 中的文件/文件夹即可读取；App 不需要自己的 iCloud 容器。
- 未下载文件：
  - 先看 `ubiquitousItemDownloadingStatus`；`.notDownloaded` 时调用 `startDownloadingUbiquitousItem`；
  - 用 `NSMetadataQuery`（`NSMetadataItemURLKey` 等）或文件状态轮询观察下载；显示字节/百分比（provider 不一定给，退化 indeterminate）；
  - 读取时用 `NSFileCoordinator`，避免读到半同步状态；
  - 离线、iCloud 空间不足、provider 报错分别给可行动的错误文案。
- 第三方 provider（Dropbox/Google Drive/OneDrive 等）可能给占位文件或返回 provider 特有错误；不要集成各家 SDK，统一按 `NSFileProvider` 行为处理，失败则报告单文件。
- 如果未来要“LocalPod 出现在 iCloud Drive 里”，才需要 iCloud Documents entitlement + `NSUbiquitousContainers`；免费账号也不支持该 entitlement，且大媒体跨设备同步冲突多、备份膨胀，**不建议 MVP 做**。更现实的是让用户把 iCloud Drive 文件夹作为“链接文件夹”（P1）增量重扫。

#### 3.6.6 Share Extension（当前不启用，未来条件性方案）

**为什么当前不做**：免费 Apple ID 的 Personal Team 不支持 App Groups（也不支持 iCloud 容器、Push、Keychain Sharing 等）。Share Extension 与主 App 没有共享容器，无法把文件/状态可靠地交给主 App；强行启用通常会在签名/安装阶段失败，或运行时拿不到共享目录。

**当前替代路径**：

- 单文件：Files 里“用 LocalPod 打开”，或 AirDrop 到 Files 后再从 App 内选择；
- 文件夹：Files 文件夹选择器、Finder 拖入；Wi-Fi 网页上传放 P1；
- 以上全部走同一个 `ImportEngine`，只是入口不同。

**架构预留**：

- 定义 `ImportInbox` 协议抽象“收件箱”；当前实现 `DocumentInbox`（`Documents/Import` + open-in），未来可加 `AppGroupShareInbox`。
- `MediaItem.sourceType` 预留 `share`；导入流水线不关心入口。
- 未来加 `LocalPodShareExtension` target，复用 `LocalPodKit` 的模型/导入逻辑，不改主 App 架构。

**未来实现要点（付费账号或上架时）**：

- **Activation Rule**：用自定义 `NSExtensionActivationRule` predicate 覆盖 `public.audio`、`public.movie`、`public.audiovisual-content`、`public.file-url`、`public.folder`；不要只开 `NSExtensionActivationSupportsFileWithMaxCount`，否则文件夹/视频可能不出现。
- **不要依赖扩展直接拉起主 App**：分享扩展不能可靠地 `UIApplication.open`；用本地通知/提示“已加入导入队列，打开 LocalPod 完成”，或让用户在扩展里等待小文件导入完成。
- **内存/时间限制**：扩展进程内存上限远低于主 App，执行时间有限。禁止在扩展里解码视频、生成缩略图、遍历巨大文件夹。
- **收件箱模式**：
  1. 扩展把附件复制到 App Group `ShareInbox/<sessionID>/`（仅限本地已存在、体积小于阈值，如 200MB 的单文件）；
  2. 大文件/文件夹只写 `share-inbox.json` 清单（原始 URL、bookmark、UTI、文件名、大小）并尽快 `completeRequest`；
  3. 主 App 启动/前台消费收件箱：能复制就复制，bookmark 失效则提示“重新分享”；
  4. 主 App 成功后删除收件箱，保证幂等。
- **文件夹分享**：部分 provider 会把文件夹压缩成 zip 或只分享一层；遇到 zip 先记录并提示（P1 可解压导入），不要假装递归成功。
- **单写入原则**：扩展不打开 SwiftData store，避免两个进程并发写同一 SQLite。数据库只由主 App 写。
- **App Group**：entitlement `com.apple.security.application-groups`，App 和 Extension 使用同一个 group；共享容器路径通过 `containerURL(forSecurityApplicationGroupIdentifier:)` 获取。需要付费 Apple Developer Program，免费账号不可用。

#### 3.6.7 Open in / AirDrop / Finder

- **Open in / AirDrop**：
  - `CFBundleDocumentTypes` 声明 `public.audio`、`public.movie`，`LSHandlerRank` 用 `Alternate`；
  - `LSSupportsOpeningDocumentsInPlace = true`；
  - 在 `scene(_:openURLContexts:)`（或 SwiftUI `onOpenURL`）处理 URL；
  - 如果 URL 已在 App 的 `Documents/Inbox`，说明系统已拷贝，直接移入导入流程；如果是外部 security-scoped URL，按 3.6.2 复制。
  - 文件夹在 iOS 上不一定提供“用 LocalPod 打开”；文件夹导入以 Files 选择器/Finder/Wi-Fi 为主。
- **Finder 文件共享**：
  - `UIFileSharingEnabled = true` 让 App 的 `Documents` 出现在 Finder 的设备 → 文件共享中；
  - 用户在 Finder 里把文件/文件夹拖进 `Documents/Import`；
  - App 启动/回前台扫描 `Documents/Import`；文件可能仍在复制，需检查大小连续两次稳定（间隔约 1 秒）再导入；
  - 导入成功后移动到 `Media`，避免重复扫描；失败保留原文件并报告。
- **兼容性**：Finder 对文件夹的拖放行为受 macOS/iOS 版本影响，M0 用真机验证一次；如果不支持文件夹，保留“拖入多个文件 + Wi-Fi 上传文件夹”作为替代。

#### 3.6.8 Wi-Fi 网页上传（P1，已定不进 MVP）

定位：从 Mac/PC 浏览器把文件夹拖进 iPhone，解决“Finder 拖文件夹不顺手”或 Windows 用户的问题。已定放 P1，不在 MVP 排期与验收范围内。

- **服务端**：轻量 HTTP server（Swifter/Hummingbird，或 `NWListener` 自写最小实现），只监听局域网；App 前台运行，显示 `http://<iPhone IP>:<port>` 和二维码。
- **发现**：可选 Bonjour（服务类型按 `_localpod` + `._tcp` 约定）；Info.plist 配 `NSBonjourServices` 与 `NSLocalNetworkUsageDescription`。iOS 14+ 首次访问会弹本地网络权限。
- **上传页**：
  - 支持多文件选择、拖拽、`webkitdirectory` 选择整个文件夹；
  - 用 `webkitRelativePath` 保留子目录；
  - 前端显示单文件/总进度、取消、错误。
- **落盘**：
  - 写入 `Documents/Import/WiFi/<sessionID>/<relativePath>`；
  - 每个路径组件做清洗：拒绝 `..`、绝对路径、空组件、控制字符；限制深度 16、文件数 20k、总大小；
  - 不信任 MIME/扩展名，导入前用 UTType + AVAsset 校验；
  - 只提供上传页和上传端点，不做目录列表/任意文件读取；上传文件放在 Web 根之外。
- **安全**：
  - 4–6 位 PIN，App 内显示，上传页必须输入；绑定局域网，提示“不要在公共 Wi-Fi 使用”；
  - MVP 不做 HTTPS（自签证书体验差）；如果后续加 TLS，更新出口合规声明；
  - 服务在 App 进入后台时停止；上传页提示保持前台。
- **为什么放 P1**：Files/Finder/打开方式/AirDrop 已覆盖绝大多数导入；Wi-Fi 是体验加分项，但会带来本地网络权限、安全文案和 HTTP server 依赖成本。

#### 3.6.9 去重、不支持格式与错误报告

- **去重**：以内容 SHA-256 为准；复制时顺带计算，不额外读一遍。重复项不复制、不建记录，计入 `skipped`。
- **缺失重链**：如果 `isMissing` 的条目与再次导入的文件指纹相同，更新 `relativePath`/`fileSize`，保留原播放进度和播放列表引用。
- **不支持格式**：不要静默跳过。每个不支持文件记录原因（容器/编码/损坏/无权限），在报告里可展开；用户可一键复制报告。
- **失败重试**：读取失败/网络 provider 超时可单文件重试；整批失败不阻塞已成功项。
- **报告内容**：总数、总大小、耗时、成功、重复、不支持、失败、取消；按类别分组；写入 `ImportReports/<date>-<session>.json`，P1 提供分享/导出。
- **日志**：OSLog 分类 `import`，记录阶段、文件数、错误码；不记录文件内容；不包含用户隐私路径（可做相对路径/哈希截断）。

### 3.7 播放器设计

#### 3.7.1 选型对比

| 方案 | 音频 | 视频 | 倍速/音调 | 后台/Now Playing | 结论 |
|---|---|---|---|---|---|
| **AVPlayer** | 支持 | 支持 | 支持 `rate` + `audioTimePitchAlgorithm` | 需自己接 AudioSession/Now Playing，但成熟 | **主引擎** |
| AVAudioPlayer | 支持 | 不支持 | `enableRate`/`rate` 范围有限 | 需自己接 | 不用：无视频、格式/能力受限 |
| AVAudioEngine | 支持 | 不支持 | 需自己实现 | 需自己接 | 不用：复杂度高，无收益 |
> 视频渲染方案（AVPlayerLayer / SwiftUI `VideoPlayer` / `AVPlayerViewController`）已在 M2 后按产品决策排除；表格保留仅为历史选型记录。

推荐组合：

- **一个 `PlaybackController` 持有 AVPlayer**，音频与视频文件的音轨共用播放状态、队列、进度、Now Playing。
- **音频/视频音轨**：自定义 SwiftUI 播放器（大封面、进度条、倍速、睡眠定时、队列）；不创建任何视频渲染层。
- 不使用 `AVPlayerViewController`、`AVPlayerLayer`、SwiftUI `VideoPlayer`；不声明横屏/PiP。
- 不要用 AVAudioPlayer 播视频文件；AVPlayer 只负责输出音轨。

#### 3.7.2 播放状态机

```text
idle → preparing → ready → playing ⇄ paused
                  ↘ buffering（本地少见）
任意状态 → interrupted（来电/耳机拔出/媒体服务重置）
任意状态 → ended / failed
```

- 单一事实来源：`PlaybackController`；UI 只读状态，不各自持有 player。
- 监听：`AVPlayerItem.status`、`AVPlayer.timeControlStatus`、`reasonForWaitingToPlay`、`AVPlayerItemDidPlayToEndTime`、`AVPlayerItemFailedToPlayToEndTime`。
- 播放失败：展示错误，自动跳到下一集（可配置），不静默停住。
- 媒体服务重置：监听 `AVAudioSession.mediaServicesWereResetNotification`，重建 player/session，恢复到原位置（暂停）。

#### 3.7.3 队列与播放列表

- `QueueManager` 维护有序 item ID、当前索引、shuffle 顺序、repeat（off/all/one）、历史。
- 用户语义要区分：
  - **播放下一首**：插到当前项之后；
  - **加入队列**：追加到队尾；
  - **播放**：替换队列（播放列表/合集点“播放全部”）。
- 自动下一集：`AVPlayerItemDidPlayToEndTime` 后按 repeat/shuffle 推进；队列空则停止并保存进度。
- 队列持久化：`QueueEntry` + `QueueState`；重启恢复当前项和位置，但不自动播放。
- 当前项被删除：自动前进到下一项；队列空则回到 idle。
-  MVP 不做无缝 gapless；本地文件切换延迟很小。若后续做音乐无缝/交叉淡入，再评估 `AVQueuePlayer` 或双 player。

#### 3.7.4 倍速与音调

- 范围 0.5–3.0，步进 0.1；预设 0.8/1.0/1.2/1.5/1.8/2.0/2.5/3.0。
- `AVPlayerItem.audioTimePitchAlgorithm = .timeDomain`：适合人声播客，1.0–3.0x 不易变调；音乐质量优先可用 `.spectral`，但 CPU 更高。
- 使用 `AVPlayer.rate` 控制播放速度；不要在播放/暂停时丢失 rate：暂停保存期望速率，恢复播放时重新应用。
- P1：按合集记忆默认倍速（课程 1.2x、有声书 1.5x），全局设置提供默认值。

#### 3.7.5 进度记忆

- `addPeriodicTimeObserver(forInterval: 1s)` 更新 UI；持久化节流：
  - 播放中每 5–10 秒写一次；
  - 暂停、拖动结束、切换条目、进入后台、App 终止前立即写；
  - 使用独立的 `PlaybackState` 小表，避免大对象失效。
- 完成判定：`position >= duration * 0.95` 或 `duration - position <= 30s`；标记 `isFinished`。
- 续播规则：`3s < position < duration - 30s` 才恢复；否则从头开始（已播完条目点播放时从头开始）。
- 视频/音频同一规则；`duration` 以播放器加载到的为准，处理 `CMTimeIndefinite`/未知时长。
- 强制退出：依赖 `scenePhase` 进入 background + 定期写入；`willTerminate` 不保证调用，不能只靠它。

#### 3.7.6 后台播放、锁屏与控制中心

- Info.plist：`UIBackgroundModes = ["audio"]`。
- `AVAudioSession`：
  - category `.playback`，options 包含 `.allowAirPlay`；
  - mode：固定 `.spokenAudio`（播客/有声书）；不切换 `.moviePlayback`；
  - 首次播放时 `setActive(true)`；停止时 `setActive(false, options: .notifyOthersOnDeactivation)`；
  - 处理 interruption（来电/闹钟/Siri）：`.began` 暂停并记录；`.ended` 且 `.shouldResume` 时恢复；
  - 处理 route change：`.oldDeviceUnavailable`（拔耳机/断开蓝牙）暂停；
  - 处理 media services reset：重建。
- `MPNowPlayingInfoCenter.default().nowPlayingInfo`：
  - `MPMediaItemPropertyTitle`、`MPMediaItemPropertyArtist`（合集名）、`MPMediaItemPropertyAlbumTitle`；
  - `MPMediaItemPropertyPlaybackDuration`、`MPNowPlayingInfoPropertyElapsedPlaybackTime`；
  - `MPNowPlayingInfoPropertyPlaybackRate`（暂停为 0，播放为当前 rate）；
  - `MPMediaItemPropertyArtwork`（512×512，`MPMediaItemArtwork` 懒加载）；
  - 可选 `MPNowPlayingInfoPropertyPlaybackQueueIndex/Count`；
  - 在播放/暂停/seek/切歌/变速时更新；系统会用 rate 外推进度，不必每秒写。
- `MPRemoteCommandCenter`：
  - play/pause/togglePlayPause；
  - skipForward/skipBackward（15/30 秒，设置可改）；
  - changePlaybackPosition（拖动）；
  - nextTrack/previousTrack（有队列时启用）；
  - 无当前项时返回 `.noActionableNowPlayingItem`。
- 锁屏封面：音频取内嵌 artwork；视频文件使用导入时生成的缩略图；没有则生成带首字母的占位图。
- 后台策略：音频（包括视频文件的音轨）进入后台后继续播放；工程已移除视频画面与 PiP，因此不存在“后台视频暂停/回前台恢复”规则。
- 锁屏/控制中心/耳机/AirPods 全部走系统 Now Playing，不自己做锁屏 UI。

#### 3.7.7 视频文件：只导入、只播音轨（M2 后最终决策）

2026-11-10 产品决策明确：LocalPod **只做音频消费**，不渲染视频画面。原计划的 AVPlayerViewController 全屏/旋转/PiP/AirPlay 方案全部废止，已从代码中移除。

- 视频文件仍可被文件夹扫描、导入、去重、探测元数据并生成缩略图；资料库筛选和条目详情保留“视频”类型。
- 播放时使用同一个 `AVPlayer` 播放其音轨，不创建 `AVPlayerLayer`/`AVPlayerViewController`，不提供“打开视频画面”入口。
- 移除 `UIBackgroundModes` 的 `picture-in-picture`；仅保留 `audio`；界面锁定竖屏，不声明横屏方向。
- 音频会话固定为 `.playback` + `.spokenAudio` + `.allowAirPlay`，不切换 `.moviePlayback`。
- 不支持视频画面的产品边界需在 README、设置页“关于”和验收文档中明确写出，避免“只出声不出画”被误解为缺陷。
- 自动化边界：单元测试验证视频文件可播放音轨且后台继续；导入测试仍覆盖视频缩略图。真机只需确认音轨兼容性，不再验证画面/旋转/PiP。

#### 3.7.8 睡眠定时

- 选项：5/10/15/30/45/60/90 分钟 + “本集结束”。
- 用**截止时间**（Date）而不是 tick 计数；播放中的 periodic observer 检查是否到点，后台播放时同样有效。
- 到点：5 秒音量淡出（`AVPlayer.volume` 线性降低），暂停，保存进度，恢复音量。
- “本集结束”：监听当前 item 结束事件，不自动下一集，直接停止。
- UI 显示剩余时间；手动暂停不默认取消定时（用户可显式取消）；重新播放时保留未到期的定时。
- 如果 App 被系统挂起（已暂停），定时在回前台时按截止时间结算。

### 3.8 持久化、一致性与迁移

- `ModelContainer` 放在 `Application Support`，数据库文件默认参与备份；媒体不备份。侧载场景仍要依赖 P1 的显式导出作为兜底。
- 导入写入：后台 `ModelActor` 批量提交；会话结束后主界面刷新。不要在导入过程中把半成品逐条塞进 `@Query`。
- 播放进度写入：节流 + 小表；M0 测写入耗时，若主线程卡顿改后台 context。
- 跨 context：SwiftData 主 context 不保证自动合并后台写入；导入结束/回前台时显式刷新；不要依赖“自动出现”。
- 迁移：`VersionedSchema` + `MigrationPlan` 从 V1 开始；每次 schema 变更都加版本；M0 就写一个迁移演练测试。
- 对账：启动时 DB ↔ 文件；缺失标记、孤儿清理、staging 清理；重链用 fingerprint。
- 恢复：保存当前 item ID/position/队列；启动显示迷你播放器但不自动播放。
- 备份/导出：P1 提供库清单/播放列表/进度 JSON；MVP 至少保证 DB 可随 iCloud 备份恢复（媒体缺失可重导）。

### 3.9 UI/UX 信息架构

**M3 实际 Tab（5 个，保留 M0/M1 调试入口）**：资料库 / 导入 / 播放 / 收件箱 / 诊断。播放列表从资料库工具栏进入；设置从资料库和播放页的齿轮打开；队列、睡眠定时在播放页。原计划收敛为“资料库 / 播放列表 / 设置”3 Tab，但为避免破坏 M0/M1 验收路径，M3 暂不重排；上架前可再收敛并把收件箱/诊断并入设置。

| 页面 | 内容 |
|---|---|
| 引导 | 3 页：导入文件夹 → 自动整理 → 播客式播放；支持格式；不提前要权限 |
| 资料库 | 继续播放、最近添加、合集网格、全部条目；搜索；音频/视频筛选；排序；列表/网格切换 |
| 合集页 | 封面、条目数、总时长、播放全部/随机、单集列表（进度/已播完标记） |
| 条目详情 | 标题、合集、格式/大小/时长、路径信息、播放、加入队列、加入播放列表、删除 |
| 音频播放器 | 大封面、标题/合集、进度条、±跳过、上一集/下一集、倍速、睡眠定时、队列、AirPlay、更多；**没有视频画面入口** |
| 队列 | 当前播放 + Up Next；拖拽排序；移除/清空；“播放下一首/加入队列”入口统一 |
| 播放列表 | 列表；新建/重命名/删除；详情拖拽排序；播放全部 |
| 导入 | 来源选择 → 扫描确认 → 进度（文件数/字节/当前文件）→ 报告 |
| 设置 | 播放默认值、跳过间隔、恢复策略、存储管理、导入历史、Wi-Fi 上传（P1）、关于/隐私 |
| 空状态 | “从文件 App 选择一个文件夹开始”；展示支持格式；内置示例入口 |

交互原则：

- 导入是“向导”，不是后台黑盒：先展示扫描结果和大小，再开始；导入中禁止误导性“可关闭”文案。
- 删除必须二次确认；显示将删除的文件数和释放空间。
- 视频列表项显示“视频 · 仅音频”标记/时长/缩略图，避免用户误以为能看画面。
- 深色模式、Dynamic Type、VoiceOver：进度条提供 adjustable action；按钮有明确 label；对比度达标。
- 方向：全局仅竖屏（Info.plist 只声明 Portrait）；不做视频横屏。
- 设备：**仅 iPhone**；不做 iPad 分栏/键盘快捷键，iPad 兼容模式不承诺体验。

### 3.10 隐私、日志与可观测性

- **不做第三方分析/广告 SDK**；MVP 无账号、无上传。
- OSLog 分类：`import`、`playback`、`files`、`inbox`、`wifi`；日志不含媒体内容，路径做相对化/哈希截断。
- 导入报告本地保存，可分享；用于用户反馈和排障。
- 崩溃/卡顿：可选 MetricKit，本地收集，不自动上传；如需上传先做隐私说明。
- **当前侧载不需要 App Store 隐私清单**；保持无追踪、无第三方 SDK。未来若上架，再补 `PrivacyInfo.xcprivacy`（FileTimestamp/DiskSpace/UserDefaults 等）和隐私政策 URL，不影响架构。
- 本地网络（Wi-Fi 上传）只在用户主动开启时请求权限；目的字符串写清楚“用于从同一 Wi-Fi 的电脑浏览器导入文件”。

### 3.11 分发与签名（免费账号侧载）

- 免费 Apple ID 的 Personal Team：provisioning profile **7 天过期**；App 会停止启动，重签/重装后恢复。用 Xcode 直连设备重签，或 SideStore/AltStore 自动续签。
- 免费账号**不支持 App Groups、iCloud 容器、Push、Keychain Sharing、TestFlight** 等能力。因此当前不做 Share Extension、不做 iCloud 容器；document picker 读取 iCloud Drive 不受影响。
- 重签时保持**同一 bundle ID**；通常不会清空 App 数据容器，但仍建议定期导出备份（P1），避免误删/换机丢进度。
- 免费账号有设备/App ID 配额限制，以 Apple 当前政策为准；只在自己和少量设备上安装。
- **不上架、不做审核专项设计**；但代码不硬编码侧载身份/路径。未来若上架，只补签名、隐私清单、审核材料，核心导入/播放/模型不变。

---

## 4. 关键难点与风险清单

| # | 风险 | 影响 | 概率 | 缓解 | 验证方式 |
|---|---|---|---|---|---|
| 1 | 文件夹权限/security-scoped bookmark 失效 | 导入失败、播放中断、用户丢库 | 中高 | 复制入库为主；bookmark 只用于 P1 链接文件夹；stale 检测 + 重新授权；绝不存绝对路径 | M0/M1 真机：移动/重命名文件夹、重装、iCloud 切换 |
| 2 | 大文件导入的内存/进度/磁盘/前台限制 | OOM、卡死、磁盘满、导入中断 | 中 | 分块复制、staging、哈希流式、磁盘预检、前台提示、idle timer、取消/清理 | 10GB 单文件、5000 文件、低存储设备 |
| 3 | iCloud 未下载/占位文件 | 枚举卡住、读取失败、体验像“卡死” | 高 | 检测下载状态、触发下载、NSFileCoordinator、进度/离线文案 | 关闭 iCloud 下载、飞行模式、第三方 provider |
| 4 | **免费账号 7 天签名过期** | App 停止启动，需重签 | 高（确定发生） | SideStore/AltStore 自动续签或 Xcode 重签；同一 bundle ID；数据备份；到期前提醒 | 安装后检查 profile 日期；重签后数据仍在 |
| 5 | **免费账号无 App Groups → Share Extension 不可用** | 少一个分享入口 | 高（确定发生） | 已决定 A：当前不做扩展；用“打开方式/Files/Finder”替代（Wi-Fi P1）；保留 `ImportInbox` 抽象，未来付费账号再加 | 免费账号签名验证；替代渠道覆盖测试 |
| 6 | 视频文件无音轨或音轨不可解码 | 条目可导入但无法播放 | 低 | 导入探测音轨；无音轨/不支持时明确标记；只承诺 AVFoundation 可解码格式 | 视频容器音轨探测测试；真机音轨播放 |
| 7 | 后台播放/Now Playing 被系统打断 | 锁屏控制失效、播放停止 | 中 | 统一 PlaybackController；AudioSession 中断/路由/重置处理；真机矩阵 | 来电、闹钟、拔耳机、蓝牙、低电量 |
| 8 | 数据不一致/容器路径变化 | 记录在、文件没了；重复/孤儿 | 中 | 相对路径、staging、批量提交、启动对账、fingerprint 重链 | 强杀、重装、升级、恢复备份 |
| 9 | SwiftData 性能/迁移 | 列表卡顿、升级丢数据 | 中 | M0 5k 基准；版本化 schema；迁移演练；批处理/索引/分页优化 | 5k/10k 导入、查询、滚动 |
| 10 | 不支持格式的预期管理 | 用户失望、差评 | 高 | 导入报告明确原因；支持格式列表；已决定不引入 VLCKit | MKV/AVI/OGG/损坏文件 |
| 11 | iCloud 备份膨胀 | 用户备份失败/体验差 | 中 | 媒体排除备份；文档说明；换机重导 | 检查备份大小/恢复流程 |
| 12 | Wi-Fi 上传安全/本地网络权限（P1） | 数据暴露、权限被拒 | 中 | PIN、局域网、路径清洗、仅前台、无目录浏览 | 安全测试、公共 Wi-Fi 提示 |
| 13 | 文件命名/路径攻击（Wi-Fi/分享） | 路径穿越、覆盖文件 | 中 | 物理名 UUID；Wi-Fi 路径逐段清洗；拒绝 `..`/绝对路径 | 恶意文件名测试 |
| 14 | 大库 UI 性能 | 滚动掉帧、启动慢 | 中 | 分页/懒加载、缩略图异步解码、缓存上限、避免主线程 I/O | 10k 条目 Instruments |
| 15 | 无 TestFlight、设备/App ID 配额有限 | 测试与交付受限 | 中 | 自用 + 少量设备；Xcode/SideStore 安装；人工回归；不做大规模 Beta | 安装/更新/重签流程演练 |

> **M0 更新（2026-11-10）**：
> - #9 SwiftData 风险下调：模拟器 5k 插入 268 ms、Mac 内存库 255 ms，列表可滚动；维持批处理/索引/分页优化，不换框架。
> - #7 新增已修复问题：`MPMediaItemArtwork` 封面回调在 MediaPlayer 后台队列触发，闭包不能继承 MainActor 隔离；M0 已改为 `nonisolated` 构造，后续播放状态机不得退回旧写法。
> - #4/#6/#7 的真机部分仍未关闭：免费账号 7 天重签、锁屏/控制中心与最老机型性能按 `docs/M0-REPORT.md` 第 7 节执行。视频画面相关真机项已随音频-only 决策取消。
> - 未新增范围决策；第 7 节九项决策保持不变。

### 4.1 文件夹权限与 bookmark 失效（重点）

- 根因：外部 URL 的访问权是“授权会话”而不是永久路径；文件夹移动/重命名、provider 变化、App 重装、iCloud 状态变化都可能让 bookmark stale 或解析失败。
- 策略：**MVP 复制入库**，导入完成即脱离外部权限；只有 P1 的“链接文件夹”才持久化 bookmark，并准备“重新授权”流程。
- 细节：`startAccessingSecurityScopedResource()` 必须配对；文件夹 scope 覆盖子项，但不要跨会话长期持有；解析 bookmark 时检查 stale 并重建；失败时按相对路径/指纹匹配已有条目。
- 验收：移动/重命名源文件夹后再导入不崩溃；链接文件夹（P1）失效时 UI 能引导重新选择；重装后数据库无绝对路径导致的“全库失效”。

### 4.2 大文件导入（重点）

- 根因：一次性 `Data` 读入会 OOM；`FileManager.copyItem` 无进度；iOS 后台执行时间有限；磁盘满时写到一半。
- 策略：1–4MB 分块流式复制 + 增量 SHA-256；staging 目录；写入前磁盘预检；前台导入 + idle timer；`beginBackgroundTask` 只用于收尾当前文件；取消/崩溃清理。
- UI：总字节进度 + 当前文件 + 预计剩余；>1GB 或 >1000 文件先确认；进入后台提示“导入已暂停，请回到前台继续”。
- 验收：10GB 单文件导入内存 < 200MB；5000 文件导入不卡死；磁盘剩 500MB 时给出明确错误且不留下半文件。

### 4.3 iCloud 未下载文件（重点）

- 根因：iCloud Drive/第三方 provider 的文件可能是 dataless 占位；直接读会阻塞或失败。
- 策略：先查 `ubiquitousItemDownloadingStatus`；未下载触发 `startDownloadingUbiquitousItem`；用 `NSMetadataQuery`/状态轮询显示下载；读取用 `NSFileCoordinator`；离线/空间不足/超时分别给文案。
- 验收：飞行模式下选择未下载文件夹，10 秒内给出可理解错误；联网后重试成功；下载大文件时 UI 不冻结。

### 4.4 免费账号与 Share Extension（重点）

- 结论：免费 Apple ID 的 Personal Team 不支持 App Groups，Share Extension 与主 App 没有共享容器，当前**不做分享扩展**。
- 影响：少一个系统分享入口；单文件用“用 LocalPod 打开”/AirDrop 到 Files，文件夹用 Files 选择器/Finder（Wi-Fi P1）。
- 未来：付费账号或上架时，加 App Group + `LocalPodShareExtension`，复用 `ImportInbox`/`LocalPodKit`；不要把 App Group 硬编码进主 App 逻辑。
- 验收：免费账号能正常签名/安装主 App；打开方式/Finder/Wi-Fi 三条路径都能导入；不出现缺 entitlement 导致的安装失败。

### 4.5 视频文件音轨兼容性（已降级，不再做画面）

- 最终决策：视频画面、全屏、旋转、PiP 全部不做；M2 中已实现的相关代码和测试已移除。
- 剩余风险：视频容器可能没有音轨，或音轨编码 AVFoundation 不支持；导入探测应记录音轨信息，无法播放时给出明确错误。
- 验收：视频文件可导入，能播放音轨并后台继续；无音轨文件在导入报告/条目状态中明确标记；不对画面做任何承诺。

### 4.6 分发与签名（当前重点）

| 事项 | 影响 | 应对 |
|---|---|---|
| 7 天 profile 过期 | App 停止启动，像“闪退” | SideStore/AltStore 自动续签，或 Xcode 直连重签；同一 bundle ID；提前提醒；数据不会因重签自动丢失 |
| 免费账号无 App Groups/iCloud 容器/Push/Keychain Sharing | Share Extension、iCloud 容器不可用 | 当前不做扩展/iCloud 容器；document picker 读 iCloud Drive 不受影响；未来付费账号再加 |
| 免费账号无 TestFlight | 无法大规模 Beta | 自用 + 少量设备；Xcode/SideStore 安装；人工回归 |
| 设备/App ID 配额 | 安装设备有限 | 以 Apple 当前政策为准；不频繁新建 App ID；固定 bundle ID |
| 当前不上架 | 没有审核/隐私清单压力 | 不做审核专项设计；保持无追踪/无第三方 SDK；未来上架再补材料 |

> 未来若上架：再准备隐私清单、隐私政策、审核备注、示例内容和截图；这些是“补材料”，不是架构改造。

### 4.7 其他需要提前验证的点

- **Mac 同步**：Finder 文件共享已覆盖“把 Mac 文件夹拖进 iPhone”；真正的双向媒体库同步需要 Mac 端 App，属于 P3，不在本轮。
- **RSS**：只留模型/协议扩展位（`sourceType` 预留 `rss`，`FeedProviding` 协议），不做抓取/刷新 UI；避免 MVP 范围膨胀。
- **格式预期**：AVFoundation 不支持 MKV/AVI/OGG 等；已决定不引入 VLCKit，导入报告明确标记不支持。若未来格式需求变化，再单独评估 LGPL/包体积/分发影响。

---

## 5. 分阶段实施计划

### 5.1 总览

| 里程碑 | 全职周 | 主要交付 | 退出标准 |
|---|---|---|---|
| M0 技术验证 | 第 1 周 | 工程骨架、3 个技术 spike、SwiftData 基准、免费账号签名验证 | 关键路径真机跑通，架构/分发方式确认 |
| M1 导入与资料库 | 第 2–3 周 | 扫描/复制/去重/DB/资料库 UI | 文件夹导入端到端可用，无脏数据 |
| M2 播放核心 | 第 4–5 周 | 音频（视频仅音轨）/进度/倍速/后台/Now Playing | 锁屏可播、进度可恢复、不渲染视频画面 |
| M3 队列/播放列表/睡眠定时 | 第 6 周 | 队列、播放列表、睡眠定时、设置 | 队列持久化、自动下一集、定时生效 |
| M4 当前渠道导入 | 第 7 周 | 打开方式/AirDrop、Finder | 所有 MVP 导入渠道统一走导入流水线 |
| M5 打磨与侧载交付 | 第 8–9 周 | 引导、无障碍、本地化、自用验收、安装/重签说明 | 无 P0/P1 bug，能日常自用 |
| 缓冲 | 第 10 周 | 修 bug、安装/重签演练 | 稳定可用 |

> 兼职（晚上/周末）按 2.5–3 倍换算，约 3–4 个月。若以后加 Wi-Fi 或其他扩展，再加 1–3 周。

### 5.2 M0 技术验证（第 1 周）

**目标**：在写完整产品前，验证最容易翻车的路径，并确认免费账号侧载可用。

**交付**

- Xcode 工程骨架：iOS 17、SwiftUI、SwiftData、`LocalPodKit`；**不建 Share Extension/App Group**。
- Spike A：`UIDocumentPickerViewController` 选文件夹 → 递归扫描 100 个文件 → 分块复制 + 进度。
- Spike B：AVPlayer 播音频 → 后台/锁屏/Now Playing/远程控制。（M0 曾额外验证 AVPlayerViewController 视频画面；该能力已在 M2 后取消。）
- Spike C：`ImportInbox` + “用 LocalPod 打开”/Finder `Documents/Import` 导入。
- 基准：SwiftData 5k 条插入/查询/列表滚动。
- 签名验证：免费 Apple ID 安装到真机；确认 7 天 profile 过期时间；重签后数据仍保留。
- 技术验证报告：更新本计划的风险与决策。

**验收标准**

- [ ] 真机（最老支持机型）上能选一个 3 层文件夹并导入 100 个文件，进度正确。
- [ ] 锁屏后音频继续，锁屏/控制中心能播放/暂停/快进。
- [x] **视频范围已关闭**：M0 曾用 AVPlayerViewController 验证 H.264/HEVC 画面；2026-11-10 产品决策改为只播放音频，画面/PiP/旋转能力已从代码和测试中移除，不再是验收项。视频文件仅保留“可导入、可播放音轨”。
- [ ] “用 LocalPod 打开”/Finder 收件箱能把 1 个文件投递并完成导入。
- [ ] SwiftData 5k 条插入 + 列表滚动达到可接受水平；只做批处理/索引/分页优化，不换框架。
- [ ] 免费账号能安装/重签，重签后 App 数据仍在；7 天过期行为已确认。
- [x] 第 7 节决策已全部确认，无剩余问题。

#### 5.2.1 M0 执行结果（2026-11-10）

**已完成（模拟器）**

- 工程骨架：iOS 17、SwiftUI、SwiftData、Swift 6、`LocalPodKit`；仅 iPhone；无 Share Extension/App Group。
- Spike A：3 层 100 文件导入完成，进度 100/100、16.5 MB / 16.5 MB；分块复制、`.part` 原子落盘、取消入口、导入报告可用。真实文件夹选择器待真机。
- Spike B：音频后台播放已验证（切到 Settings 再返回，0:02 → 0:12）；背景音频/Now Playing/远程命令/中断处理已实现，锁屏控制待真机。**历史记录：M0 曾验证 H.264/HEVC 出画面并可全屏；该视频画面能力已在 M2 后按产品决策移除，当前版本只播放音频。**
- Spike C：`Documents/Import` 收件箱自动导入 1 个；`file://` 外部打开导入 1 个，来源标为“外部打开”。
- SwiftData 5k：App 内插入 268 ms；列表可滚动；Mac 内存库 255 ms。
- 自动化：`LocalPodKit` 15/15 单元测试通过；UI 测试 4/4 通过（64.391 s）；模拟器与真机编译均无源码 warning。
- 诊断页可解析真机 `embedded.mobileprovision` 的名称、Team、到期时间与剩余天数，供免费账号验证。

**待真机执行**

- 真实“选择文件夹”与 100 文件导入、最老支持机型性能。
- 锁屏/控制中心：继续播放、标题/封面/进度、播放/暂停/±15s/拖动。
- 免费账号安装、约 7 天过期、同一 Bundle ID 重签后数据保留。
- Files 分享与 Finder 文件共享；视频文件只需确认音轨可播放与后台继续（不再验证画面/旋转）。

证据与详细发现见 `docs/M0-REPORT.md`、`docs/M0-SIGNING.md` 和 `docs/screenshots/`。

### 5.3 M1 导入与资料库（第 2–3 周）

**目标**：文件夹导入端到端可用，资料库能管理。

**交付**

- FolderScanner：过滤、深度/数量上限、自然排序、iCloud 状态。
- ImportEngine：staging、分块复制、SHA-256、取消、清理、报告。
- MediaProbe：时长、音/视频轨、元数据、封面/缩略图。
- SwiftData 模型 + 批量写入 + 启动对账 + 缺失重链。
- 资料库/合集/条目详情/搜索/筛选/排序/删除/存储占用。
- 导入向导 + 进度 + 报告。

**验收标准**

- [x] 3 层文件夹、100 文件（含 2 个不支持、1 个重复）导入：进度准确，报告分类正确。**（模拟器 + 单元/UI 测试通过：97 导入 / 1 重复 / 2 不支持 / 0 失败；真实文件夹选择器待真机）**
- [x] 导入中取消：已完成项保留，staging 清理，无半条记录。**（单元测试 + UI 测试通过）**
- [x] 导入中强杀 App：重启后无脏数据；孤儿/staging 被清理或可清理。**（UI 测试强杀 + 启动对账通过）**
- [x] 同一文件夹重复导入：新增 0，跳过 N，不重复建合集。**（UI 测试：第二次 0 导入 / 98 重复 / 2 不支持；合集仍为 1 个）**
- [ ] iCloud 未下载文件：显示下载进度；断网有明确错误；重试成功。**（部分自动化：下载重试/失败分类/本地文件 no-op 已测；真实 iCloud 下载进度、断网与重试待真机）**
- [x] 元数据/时长/类型正确；视频有缩略图；音频有封面或占位。**（真实 AVFoundation probe 测试 + UI 占位图通过；真实 iCloud 文件待真机）**
- [x] 删除条目后文件与记录都消失，存储数字更新。**（UI 测试 97→96 条；单元测试校验媒体与封面文件删除）**
- [x] 模拟重装/容器路径变化后，相对路径仍能解析。**（单元测试通过模拟容器迁移；真机重装见 M0 真机清单）**
- [x] 5000 文件导入内存 < 200MB，主界面不明显卡顿。**（本机测试峰值增量 100.3 MB；模拟器 5000 条列表滚动通过；最老真机性能待真机）**

> M1 执行结果与证据见 [`docs/M1-REPORT.md`](docs/M1-REPORT.md)。真实文件夹选择器、真实 iCloud 下载行为、真机性能仍列入“待真机”，未计为已通过。

### 5.4 M2 播放核心（第 4–5 周）

**目标**：音频与视频文件的音轨都能稳定播放；后台/锁屏/进度/倍速完整。产品决策：不渲染视频画面。

**交付**

- PlaybackController + 状态机 + 错误恢复。
- AudioSession、Now Playing、远程命令、中断/路由/媒体服务重置。
- 进度持久化/恢复、完成阈值。
- 倍速 + `timeDomain` 音调修正。
- 音频播放器 UI（不含视频画面入口）；视频文件仅播放音轨。
- 后台策略：音频（含视频文件音轨）持续播放；无视频画面/PiP。

**验收标准**

- [ ] 锁屏后音频继续；锁屏显示标题/封面/进度；控制中心播放/暂停/±15s/拖动生效。**（部分自动化：后台音频持续推进 UI 测试、Now Playing 元数据/远程命令启用单元测试通过；锁屏与控制中心实际显示/交互待真机）**
- [x] 强退后重开，进度恢复误差 ≤ 2 秒；已播完不自动续播。**（UI 测试：跳转 2:00 后强退恢复 2:00；播放中强退恢复误差 ≤ 2 秒；播放结束重开为 0:00）**
- [ ] 0.5/1.0/1.5/2.0/3.0x 可用，人声不变调。**（自动化通过：5 档倍速 UI 切换 + `timeDomain` 音调算法断言；实际听感需真机/人耳确认）**
- [x] **视频画面范围已取消（仅音频）**：不实现全屏/旋转/PiP/视频渲染；视频文件保留导入与音轨播放。**（已移除 VideoPlayerScreen、PiP、横屏声明与相关测试；新增“视频文件播放音轨且后台继续”单元测试）**
- [ ] 拔耳机暂停；来电/闹钟打断后按 shouldResume 恢复。**（部分自动化：打断恢复策略单元测试通过；真实来电/闹钟/拔耳机需真机）**
- [ ] 2 小时长音频播放内存稳定，无泄漏；切歌 100 次无崩溃。**（切歌 100 次单元测试通过；2 小时长播内存/泄漏需真机长跑）**

> M2 执行结果与证据见 [`docs/M2-REPORT.md`](docs/M2-REPORT.md)。锁屏/控制中心、真实中断/路由、2 小时内存仍列入“待真机”，未计为已通过。视频画面/PiP/旋转已按产品决策取消，不再列入待办。

### 5.5 M3 队列、播放列表、睡眠定时、设置（第 6 周）

**目标**：播客式消费闭环。

**交付**

- QueueManager + 持久化 + 自动下一集 + 随机/循环。
- 播放列表 CRUD/拖拽/播放全部。
- 睡眠定时（分钟/本集结束/淡出）。
- 已播完状态、继续播放排序、设置页。

**验收标准**

- [x] 队列重启后保留；播放下一首/加入队列语义正确；当前项删除后自动前进。**（自动化通过：`QueueManagerTests` 10 个、`PlaybackSessionTests` 删除/恢复用例、`M3UITests.testQueueSemanticsCurrentDeletionAndRelaunch`）**
- [x] 播放列表拖拽排序保存；随机/循环行为正确。**（自动化通过：`PlaylistServiceTests` 6 个、`QueueManagerTests` 随机/循环用例、`M3UITests.testPlaylistCreateReorderPersistAndPlayAll`）**
- [x] 睡眠定时 1 分钟测试到点淡出暂停；本集结束模式不自动下一集。**（自动化通过：`SleepTimerTests` 固定时钟淡出/取消、`PlaybackSessionTests`、M3 两个睡眠 UI 用例；锁屏后台到点需真机）**
- [x] 已播完阈值正确；“继续播放”不出现已播完条目。**（自动化通过：M2 完成阈值/进度测试、`M3UITests.testContinueListeningExcludesFinishedItems`）**
- [x] 设置项重启后保留。**（自动化通过：`AppSettingsStoreTests` 4 个、`M3UITests.testSettingsPersistAcrossRestart`）**

> M3 执行结果与证据见 [`docs/M3-REPORT.md`](docs/M3-REPORT.md)。锁屏状态下的睡眠定时、拖拽手感、控制中心上一首/下一首等真机项仍列入“待真机”，未计为已通过。

### 5.6 M4 当前渠道导入（第 7 周）

**目标**：所有 MVP 导入渠道统一走同一流水线。

**交付**

- Open in / AirDrop / 文档类型。
- Finder `Documents/Import` 扫描 + 文件稳定检测。
- 渠道来源标记、统一报告、失败重试。
- **不做 Share Extension**：免费账号无 App Groups；未来付费账号/上架再加。
- **Wi-Fi 上传放 P1**：不在 M4/MVP 交付与验收范围。

**验收标准**

- [x] “用 LocalPod 打开”/AirDrop 到 Files：能进入导入并成功。**（自动化通过：`M4UITests.testOpenInImportAndDedup` 走真实 `onOpenURL` 路径、来源标记与去重；真实 AirDrop/Files 界面需真机）**
- [x] Finder 拖入 `Documents/Import`：前台自动导入；复制中的文件不会被半截导入。**（自动化通过：`M4UITests.testForegroundInboxWaitsForStableFile`、`ImportInboxStabilityTests` 12 个、`ImportInboxTests` 暂存/清理用例、`ImportEngineTests` 字节校验；真实 Finder 数据线拖入需真机）**
- [x] 所有 MVP 渠道统一去重/进度/报告。**（自动化/集成通过：文件夹、收件箱、外部打开共用 `FolderImportService`/`ImportEngine`；运行级聚合 JSON 报告含各 URL `reportPaths`）**
- [x] 免费账号签名/安装不因缺少 App Group entitlement 失败。**（结构验证：无 entitlements/App Group，`generic/platform=iOS` 不签名构建通过；实际免费账号安装属真机步骤）**

> M4 执行结果与证据见 [`docs/M4-REPORT.md`](docs/M4-REPORT.md)。真实 AirDrop、文件 App 打开、Finder 拖入、iCloud 占位文件与真机签名安装仍列入“待真机”，未计为已通过。

### 5.7 M5 打磨与侧载交付（第 8–9 周）

**目标**：日常可用的自用 MVP，而不是“上架版”。

**交付**

- 引导、空状态、错误文案、动画与细节。
- 无障碍、深色模式、简体中文/英文。
- 性能优化（列表、图片、导入、启动）。
- 内置示例内容（公有领域/自录，可删除）。
- 连续 1–2 周自用验收；崩溃/问题修复。
- 安装/重签说明：Xcode 直连或 SideStore/AltStore；7 天提醒；数据备份方式。
- **不做 App Store 素材/审核材料/TestFlight**。

**验收标准**

- [ ] 连续 2 周日常使用，无 P0/P1 阻断问题。
- [ ] 1GB 文件夹导入达到基线（建议 < 2 分钟，按设备实测调整）；4K 视频容器仅音轨导入/播放正常（不验证画面/旋转）。
- [ ] VoiceOver 能完成“导入 → 播放 → 加队列 → 睡眠定时”；Dynamic Type 不截断。
- [ ] 在自己设备上完成一次“安装 → 7 天过期 → 重签”演练，数据仍在。
- [ ] 安装/重签/备份步骤写成文档，下一次不用重新查。

### 5.8 估算假设

- 1 名全职 iOS 开发者；设计遵循系统组件，不做大规模品牌设计。
- 仅 iPhone；Wi-Fi 按 P1，不在 MVP；不引入 VLCKit。
- 不含后端/账号/支付开发；**不接 StoreKit，不做内购/订阅**。
- 分发为免费账号侧载：7 天重签是运维成本，不计入开发周；无 TestFlight、无 App Store 审核时间。
- 如果只有兼职时间，按 2.5–3 倍时间规划，优先做 M1–M5 核心；P1 项（Wi-Fi、智能播放列表、字幕）后置。

---

## 6. 测试计划

### 6.1 单元 / 集成 / UI

| 层级 | 覆盖 |
|---|---|
| 单元测试 | 扫描过滤（隐藏/包/符号链接/深度/数量）、UTType 分类、自然排序、SHA-256、进度计算、完成阈值、队列前进/随机/循环、睡眠定时截止、路径清洗、磁盘预检、bookmark stale 处理（mock） |
| 集成测试 | 临时 fixture 文件夹导入、取消/强杀恢复、批量 DB 提交、iCloud 状态（手工）、打开方式/本地 Inbox、Finder 扫描与稳定性/隔离（Wi-Fi 上传属 P1，不在 MVP 回归） |
| UI 测试 | 导入（文件夹/收件箱/打开方式/稳定性/隔离）→ 资料库 → 播放 → 队列 → 播放列表 → 睡眠定时；删除/存储 |
| 手工测试 | 锁屏/控制中心、来电/闹钟、拔耳机/蓝牙、AirPlay 音频、低电量、低存储 |

### 6.2 设备与素材矩阵

- 机型：最老支持机型（如 iPhone XS/XR 级别）+ 当前主流 iPhone；**仅 iPhone**。
- 系统：最低支持版本 + 最新正式版。
- 免费账号有设备/App ID 配额限制；测试以自己设备 + 1–2 台备用机为主。
- 文件：
  - 音频：mp3、m4a、aac、wav、aiff、flac、alac；1 秒/1 小时/2 小时。
  - 视频容器：mp4/mov，H.264/HEVC，1080p/4K，含/不含音轨；仅验证导入与音轨播放，不验证画面/旋转。
  - 不支持：mkv、avi、ogg、opus、损坏文件、0 字节文件。
  - 命名：中文、emoji、空格、超长、无扩展名、大写扩展名、重复名。
  - 结构：3 层/10 层、100/1000/5000 文件、空文件夹、隐藏文件、包。
- 场景：iCloud 未下载、飞行模式、第三方 provider、Finder 拖入、打开方式/AirDrop（Wi-Fi 上传属 P1，不在 MVP 回归）。
- 存储：剩余 500MB/2GB/充足；导入中磁盘耗尽。

### 6.3 性能预算

| 指标 | 目标 |
|---|---|
| 冷启动 | < 2 秒；热启动 < 1 秒 |
| 资料库滚动 | 10k 条目 60fps（ProMotion 设备允许 120fps） |
| 导入内存 | < 200MB（与文件大小无关） |
| 1GB 文件夹导入 | 基线按设备实测；不出现卡死/进度停滞 |
| DB 查询 | 10k 条目首屏 < 100ms |
| 进度写入 | 单次 < 10ms，不阻塞主线程/播放 |
| 封面/缩略图 | 异步解码；缓存有上限；列表不一次性解码全部 |

工具：Instruments（Time Profiler、Allocations、Leaks、File Activity、Network）、MetricKit（崩溃/卡顿）、Xcode Organizer。

### 6.4 侧载测试与交付

- 免费账号**不能用 TestFlight**；以自用 + 少量设备为主，Xcode 直连或 SideStore/AltStore 安装。
- 收集：导入成功率、失败原因、视频问题、锁屏控制、崩溃（Xcode Console/MetricKit）。
- 交付前演练：安装 → 使用 → 7 天过期 → 重签 → 数据仍在；备份/恢复一次。
- **不做 App Store 审核前检查、隐私清单、截图/预览**；未来上架再补。
- 自用 Beta 标准：连续 2 周日常使用无 P0/P1 阻断问题，而非 50 人 crash-free 指标。

---

## 7. 已定决策（全部关闭）

| # | 决策 | 落地 |
|---|---|---|
| 1 | **最低 iOS 17.0** | 使用 SwiftData / `@Observable`；不讨论 iOS 16/Core Data 降级 |
| 2 | **仅 iPhone** | 只构建 iPhone 布局；不做 iPad 分栏/专属适配 |
| 3 | **不做 CarPlay** | MVP 和近期都不做；不申请 entitlement；排期、风险与附录已移除 |
| 4 | **完全免费、纯自用** | 不接 StoreKit，不做内购/订阅/付费墙；onboarding 不出现购买入口 |
| 5 | **免费 Apple ID 自签名 + 侧载** | 7 天重签；无 App Groups/TestFlight；当前不上架；架构保留未来上架可能 |
| 6 | **当前不做 Share Extension（1A）** | 免费账号无 App Groups；用打开方式/Files/Finder 替代（Wi-Fi P1），保留 `ImportInbox` 抽象 |
| 7 | **Wi-Fi 网页上传放 P1（2）** | 不进 MVP 排期与验收；P1 再做 |
| 8 | **只支持 AVFoundation 可播格式（4）** | 不引入 VLCKit；MKV/AVI/OGG 等明确标记不支持 |
| 9 | **当前不做 App Store 审核专项设计** | 不做隐私清单/审核材料/截图；未来上架再补，不改核心架构 |

> **无剩余待确认项。** M0 已开始并完成模拟器验证；九项决策均未变更。M0 实现发现（封面回调线程、AudioSession 激活线程）见 4 节与 `docs/M0-REPORT.md`。

---

## 8. 决策记录（ADR）

| 编号 | 决策 | 理由 | 代价/触发条件 |
|---|---|---|---|
| ADR-001 | 导入采用复制入库 | 避免 bookmark 失效、后台 scope 丢失、iCloud 占位；文件稳定可备份/删除 | 占用双份空间（源文件仍在 Files）；→ P1 可加“链接文件夹” |
| ADR-002 | AVPlayer 单引擎，只输出音频 | 音频/视频音轨/倍速/音调/AirPlay 统一；不维护视频渲染 UI | 视频文件无画面、无 PiP；产品边界需明确沟通 |
| ADR-003 | SwiftData（iOS 17+，固定） | 开发快、与 SwiftUI 集成好；iOS 17 已定 | 批量导入/迁移仍需谨慎；只做批处理/索引/分页优化，不换框架 |
| ADR-004 | 当前不做 Share Extension，保留 `ImportInbox` 抽象 | 免费账号无 App Groups，扩展无法与主 App 共享容器 | 少一个分享入口；未来付费账号/上架时加 App Group + extension |
| ADR-005 | MVP 不申请 iCloud 容器 | document picker 足够读 iCloud Drive；避免大媒体同步冲突；免费账号也不支持 iCloud entitlement | 无法“LocalPod 文件夹”跨设备自动出现；P1 再评估 |
| ADR-006 | 文件夹 = 合集，播放列表独立 | 符合播客心智；导入即组织 | 合集重命名/合并需要 UI；P1 加 |
| ADR-007 | 媒体排除 iCloud 备份 | 避免备份膨胀；媒体可重导 | 换机后媒体缺失，需要重链/重导；文档说明 |
| ADR-008 | 只播放音频，不渲染视频画面（M2 后修订） | 产品定位是播客式音频消费；避免视频渲染/PiP/旋转的复杂度 | 视频文件只能听音轨；如需画面需另立项目 |
| ADR-009 | RSS 只留扩展位 | 控制 MVP 范围；不引入抓取/刷新/下载 | 后续做 RSS 需新增 Feed 模型/刷新/下载策略 |
| ADR-010 | Wi-Fi 上传 P1（已定） | 主渠道已覆盖；本地网络权限/安全/依赖成本 | 少了 Windows/浏览器批量导入；P1 再补，不进 MVP |
| ADR-011 | 免费账号自签名侧载，暂不上架 | 个人自用，无 App Store/TestFlight/审核成本 | 7 天重签；无 App Groups；代码不硬编码侧载假设，未来上架只补材料 |
| ADR-012 | 完全免费，无 StoreKit/IAP/订阅 | 纯自用，无服务器成本 | Onboarding/设置不出现购买入口；未来上架也按免费 App 处理 |

---

## 9. 附录

### A. Info.plist / Entitlements / 关键 Build Settings

| 键/能力 | 值 | 用途 |
|---|---|---|
| `TARGETED_DEVICE_FAMILY` | `1` | 仅 iPhone |
| `UIBackgroundModes` | `audio` | 后台音频播放 |
| `UIFileSharingEnabled` | `YES` | Finder/文件 App 可见 `Documents` |
| `LSSupportsOpeningDocumentsInPlace` | `YES` | 打开方式/就地打开 |
| `CFBundleDocumentTypes` | `public.audio`、`public.movie`（`LSHandlerRank = Alternate`） | AirDrop/打开方式 |
| `NSLocalNetworkUsageDescription` | “用于从同一 Wi-Fi 的电脑浏览器导入本地文件” | Wi-Fi 上传（P1） |
| `NSBonjourServices` | `_localpod` + `._tcp`（按需） | Wi-Fi 上传发现（P1） |
| `ITSAppUsesNonExemptEncryption` | `NO` | 无 TLS/自定义加密 |
| `UISupportedInterfaceOrientations` | 竖屏 + 视频需要的横屏 | 资料库竖屏、播放器横屏 |
| App Groups entitlement | **当前不启用** | 免费 Personal Team 不支持；未来付费账号 + Share Extension 再加 |
| iCloud entitlement | **不申请** | document picker 读 iCloud Drive 不需要；免费账号也不支持 iCloud entitlement |
| 签名 | 免费 Apple ID Personal Team | 7 天 profile；无 TestFlight/App Groups；重签保持同一 bundle ID |

### B. 支持格式（以 AVFoundation 实际能力为准）

| 类型 | 容器/编码 | 说明 |
|---|---|---|
| 音频 | mp3、m4a/AAC、ALAC、wav、aiff、caf、flac | AVFoundation 常见支持；仍以 `AVAsset.isPlayable` + 轨道探测为准 |
| 视频容器 | mp4/m4v/mov，H.264/HEVC + AAC | 仅导入与音轨播放；不渲染画面，1080p/4K/HDR 画面能力不在范围 |
| 字幕 | 内嵌 mov/text 轨 | 外挂 SRT/VTT 为 P1 |
| 不支持 | mkv、avi、wmv、flv、webm、ogg/opus、ape、dsf、VIDEO_TS | 导入报告明确标记；当前不引入 VLCKit |

> 不要只看扩展名：同一容器可能编码不支持；用 `loadTracks`/`isPlayable` 判定，避免“能导入但播不了”。

### C. 导入状态机

```text
会话：idle → scanning → planning → downloading(iCloud) → copying → probing
      → committing → completed / cancelled / failed

单文件：pending → copying → probing → imported
              ↘ duplicate / unsupported / failed / cancelled
```

### D. 页面清单

- 引导（3 页）
- 资料库（继续播放/最近添加/合集/全部）
- 合集页
- 条目详情
- 音频播放器（视频文件只显示为音频条目）
- 队列（Up Next）
- 播放列表 / 播放列表详情
- 导入来源选择 / 扫描确认 / 进度 / 报告
- 设置 / 存储管理 / 导入历史 / Wi-Fi 上传 / 关于与隐私

### E. 术语表

| 术语 | 含义 |
|---|---|
| 合集 / Show | 一次文件夹导入生成的顶层分组，类似播客节目 |
| 单集 / Item | 一个音频或视频文件 |
| Up Next | 播放队列，当前项之后要播的内容 |
| Security-scoped bookmark | 记录外部文件/文件夹访问权限的持久化数据；可能 stale |
| Staging | 导入暂存目录，成功后原子移动到媒体库 |
| Fingerprint | 文件内容 SHA-256，用于去重和缺失重链 |
| Provider | Files/iCloud Drive/第三方网盘的文件提供方 |
| Now Playing | 锁屏/控制中心展示的正在播放信息 |

---

**下一步**：决策已全部确认，直接进入 M0：先做 3 个技术 spike + 免费账号签名验证，再开始 M1。
