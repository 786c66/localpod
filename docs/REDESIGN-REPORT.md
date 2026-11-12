# LocalPod 设计重构报告 · Direction C「节拍 / Expressive」

> 分支：`feat/expressive-redesign` · Worktree：`~/Dev/code/localpod-redesign`
> 设计规格：`docs/DESIGN-SPEC.md`（来源 `~/Dev/code/podcast-design/podcast-design-directions.html` 的 Direction C）
> 口号：**把收听变成一盒磁带。**

## 1. 一句话结论

现有 LocalPod 的全部界面已从「系统默认表单 + 列表」换成 Direction C 的磁带盒语言：奶油底、
1.5px 墨黑描边、4px 硬阴影、酸柠/珊瑚/电紫三色贴纸、Space Grotesk + IBM Plex Mono 字阶、
260ms 弹簧转场与按压回弹。所有功能、字段、可访问性标识保持不变；仅 iOS、纯音频、无 CarPlay、
无内购、免费 Apple ID 侧载的约束没有被触碰（未引入 App Groups / Push / iCloud 容器）。

2026-11-12 owner 验收后又完成一轮 8 条打磨：示例内容移出正常流程（只在设置 → 诊断手动生成）、
合集支持多种排序与手动拖动、文件夹导入改为原地读取（security-scoped bookmark）、继续播放支持状态
切换、播放页队列默认折叠、倍速扩到 9 档、进度条可拖动、修掉「播放中」重影，底部 Tab 收敛为
资料库 / 播放两个核心入口，导入与收件箱整体迁入设置。逐条对照见 §2.4。

## 2. 改动总览

### 2.1 设计系统（新增）
- `TapeTheme` / `TapeType` / `TapeComponents`：颜色、字体、间距、圆角、描边、硬阴影、弹簧曲线。
- 组件：`TapeCard`、`TapeDashedCard`、`TapeRow`、`TapeKicker`、`TapeSectionHeader`、
  `TapeMonoLabel`、`TapeChip`、`TapeSegmentedChips`、`TapeSticker`、`TapeRewardSticker`、
  `TapeEmptyState`、`TapeProgressBar`、`TapeHairline`、按钮样式（主/次/危险/按压）。
- 字体随包内置（SIL OFL）：Space Grotesk、IBM Plex Mono。
- 系统外观：`TapeAppearance` 统一导航栏、Tab 栏、列表背景与强调色（电紫）。
- 列表分区 header/footer 统一清掉系统行背景（`.listRowBackground(Color.clear)`），
  避免奶油点阵画布上出现白色横带。

### 2.2 根壳与导航
- 自定义磁带 Tab 栏 `TapeTabBar` 收敛为两个核心入口：**资料库 / 播放**；酸柠圆形选中态、按压回弹、贴纸式顶部分隔线。
- 导入、收件箱、诊断从底部 Tab 移除，统一收进设置 sheet；设置内部用 `NavigationPath` 推入
  「导入与文件夹 / 收件箱 / 诊断」子页。子页在自己的 floating nav bar 下不显示工具栏按钮，
  因此用 `safeAreaInset` 固定一颗「完成」胶囊，任意滚动位置都可关闭。
- 深链（UI 测试启动参数、引导页「去导入」）通过 `SettingsView(initialDestination:)` 直接落到子页；
  sheet 内容以 `.id(destination)` 绑定身份，避免 SwiftUI 复用首次构造的空路径导致深链退回设置根页。
- 根视图仍是 TabView + 兄弟节点 Tab 栏（不悬浮），保证列表视口不被遮挡；功能与测试标识不变。

### 2.3 各界面

- **资料库**：统计 Hero 卡（条数 / 合集 / 占用 + 酸柠播放贴纸）、筛选 chip、合集卡、磁带盒式条目行、
  回收站区、播放列表入口；条目详情改为贴纸 Hero + 磁带信息卡；加入播放列表改为贴纸弹层。
  合集卡支持自然排序 / 自然倒序 / 名称 / 导入时间等排序，并可进入手动拖动排序；「继续播放」卡
  提供已完成 / 未完成 / 手动重置的状态切换。
- **播放页**：卡带封面 + 状态贴纸（常驻、可滚动时仍可读；阴影只画在胶囊底上，字形不再重影）、
  传输键优先的控制卡、可拖动 seek 的进度条、9 档倍速 chip（0.5 / 0.8 / 1.0 / 1.2 / 1.5 / 1.8 /
  2.0 / 2.5 / 3.0×）、睡眠定时/设置收纳进导航工具栏、章节列表。整个资料库列表不再铺在播放页，
  只保留「队列 · N」头与「展开当前队列 / 收起当前队列」按钮，展开后才是随机/循环/清空与队列行。
- **导入页**：Hero 卡（FOLDERS / AUDIO ONLY）、快速导入卡内嵌「上次结果 + 实时进度」状态块
  （导入后主按钮仍保持一屏可达）、详细结果卡、问题卡、最近导入与空状态。文件夹导入改为原地
  读取：只保存 security-scoped bookmark 与文件指纹，不复制媒体进沙盒；单文件渠道（文件选择器、
  AirDrop / 打开方式、Wi-Fi 上传、收件箱）仍走受控复制。
- **设置**：全部 Form 分组改为白卡 + ALL-CAPS kicker；倍速 chip、原生 Toggle/Picker 保留在卡内；
  存储/Wi-Fi/链接文件夹/备份/通知/导入记录/关于各自成卡；分享面板同步换肤。「导入与文件夹」「收件箱」
  「诊断」作为设置子页推入；示例内容不再出现在导入页，只在诊断页的「测试与示例内容」卡里手动生成。
- **引导页**：卡带 Hero + 功能卡 + 底部行动区（开始使用 / 去导入 / 跳过），保留全部四段说明。
- **收件箱**：作为设置子页提供计数卡与「上次结果 / 需要处理」（导入完成后首屏可见），下面是
  DROP ZONE 说明与手动扫描卡、空状态虚线卡、运行中/错误卡、Finder/外链/路径卡。
- **诊断 / 基准**：工具、维护、应用信息、签名、资料库数据、磁盘路径分区成卡；示例条目生成/删除与
  演示、验收文件夹导入集中在「测试与示例内容」卡；数值一律 mono；基准状态、动作、结果、列表行换肤，
  未删任何指标。
- **Wi-Fi 上传**：说明卡、连接地址/PIN/二维码/活动卡、停止/重试按钮、限制说明卡；服务生命周期未动。
- **回收站 / 播放列表 / 智能列表**：统计 Hero、卡片化列表行、虚线贴纸空状态、滑动操作与确认框原样保留。

### 2.4 Owner 验收后的 8 条打磨

| # | 要求 | 实现 |
| --- | --- | --- |
| 1 | 示例内容不出现在正式 App | 导入页与根导航不再出现任何示例入口；示例条目、演示/验收文件夹只在设置 → 诊断 →「测试与示例内容」卡里手动生成、删除。`SampleContent` 仍随包存在，但不自动导入、不展示。 |
| 2 | 合集顺序管理 | `CollectionOrdering` 支持自然、自然倒序、名称、名称倒序、导入时间、手动；合集卡排序菜单持久化 `sortModeRaw`，手动模式提供拖动排序与 `collectionPosition`。 |
| 3 | 导入改为原地读取 | 新增 V7 `isLinked` / `linkedFolderID` / `linkedBookmarkData`；`FolderImportService.importLinkedFolder` 原地扫描、下载 iCloud 占位、指纹去重、就地探测；`LinkedFolderStore` 解析/刷新 stale bookmark，失效时保留行并要求重新授权；启动/回前台 reconcile 外部删除并标记缺失。`Info.plist` 开启 `LSSupportsOpeningDocumentsInPlace`。单文件渠道仍复制。 |
| 4 | 「继续播放」状态切换 | 进度模型新增完成/手动重置语义与 `PlaybackProgressStore` 状态操作；资料库继续播放卡提供「标记已完成 / 标记未完成 / 重置进度」，播放页与队列进度同步刷新。 |
| 5 | 播放页只留队列入口 + 更多倍速 | 移除整库列表，仅保留「展开当前队列」，默认折叠；倍速扩为 0.5 / 0.8 / 1.0 / 1.2 / 1.5 / 1.8 / 2.0 / 2.5 / 3.0×，横向滚动 chip。 |
| 6 | 进度条拖动 seek | 可视进度条 + 拖拽圆点由自绘承担，触摸交给覆盖其上的原生 Slider（2% 不透明度、44pt 高）：按下、拖动、松手提交，拖动期间显示预览时间；纵向滑动仍能滚动列表。 |
| 7 | 「播放中」重影 | 根因是 `.shadow` 加在整枚贴纸（文字 + 胶囊）上，硬阴影复制了字形；改为只给胶囊底加阴影，文字保持单层渲染。 |
| 8 | Tab 收敛，导入/收件箱迁入设置 | 底部只剩资料库（tag 0）/ 播放（tag 1）；导入、收件箱、诊断作为设置子页，保留原页面与全部标识。 |

## 3. 刻意取舍

以下是这轮重构里**故意不按“全换掉”做**的地方，以及原因（含实测依据，验收时如果觉得某条
需要改，单独提即可）。

1. **设置页保留原生 Toggle / Picker。** Direction C 的开关可以是贴纸式，但原生 `UISwitch` 的
   a11y `value` 是 "1"/"0"，现有 M5 测试与 VoiceOver 都依赖它；换成自绘开关会同时改动可访问性语义、
   动态字体与系统手势。做法是保留系统控件本体，外套磁带卡、kicker、mono 数值与描边，颜色经
   `TapeAppearance` 向紫/墨靠拢。同理保留原生 Slider（播放进度）与系统 Alert。
2. **列表行用 Button + `navigationDestination`，不用 `NavigationLink`。** 系统 List 会给
   `NavigationLink` 自动加右侧 disclosure chevron 与默认行高，破坏「描边卡片」的完整轮廓；
   改为 Button 后在卡片内部画自己的 chevron，点击语义、可访问性角色与目标页面不变。
3. **自定义 Tab 栏是兄弟节点，不做悬浮。** XCUITest 的 `isHittable` 只看元素 frame 是否落在
   窗口内，悬浮栏遮住的列表行仍会报告“可点”，实际点击却落在栏上；而且悬浮栏会吃掉列表底部
   92pt。改成 TabView + 兄弟 Tab 栏后，列表视口在栏上方干净结束，既解决命中问题也不遮挡内容。
4. **播放状态是列表上方的常驻贴纸，不是导航栏文字。** 实测 iOS 27 上列表滚动后导航栏整体退出
   可访问性树，状态文本在队列区域查询不到；贴纸固定在视口右上、`allowsHitTesting(false)`，
   滚动时仍可读，也不挡行点击。
5. **导入页把「上次结果 + 实时进度」并进快速导入卡，而不是两个独立 Section。** 独立 Section 会
   把文件夹选择主按钮推到首屏之外；XCUITest 一次 `swipeUp` 约 681pt，会直接过冲，重加流程点不中。
   合并后主按钮始终一屏可达，信息密度也更高。
6. **音频文件不做视觉伪装。** 纯音频约束下不生成波形/视频画面；波形与卡带只是装饰贴纸，
   视频文件仍只取音轨。不给视频做“假装有画面”的 UI。
7. **只做浅色主态。** Direction C 的奶油底印刷风是一套完整配色；不做自动深色反转，避免出现
   与规格不符的第二套色板。系统深色模式下界面仍是奶油画布（贴纸与描边不变）。
8. **阴影只用无模糊硬阴影，不用材质/毛玻璃。** 保持印刷质感；也避免实时模糊带来的性能与
   截图不一致问题。
9. **贴纸与 kicker 使用未本地化的英文。** 它们是视觉元素（如 `QUICK ADD`、`NO TAPES`），
   不承载功能信息；用户数据与功能性文案全部走 `L10n`，中英文都完整。
10. **字体随包内置（SIL OFL）。** Space Grotesk / IBM Plex Mono 打包进 App，离线可用；
    字号使用相对字体，最大动态字体下不截断。
11. **44pt 命中区兜底，视觉尺寸可以更小。** 贴纸式图标按钮保留 36/40pt 的视觉直径，
    但 `TapeIconButtonStyle` 的布局与 `contentShape` 统一按 ≥44pt 兜底；Tab、列表行与胶囊
    按钮的高度也不低于 44pt。玩具感不牺牲可点性，也避免自动化与真机点击落空。

## 4. 截图对比

`docs/screenshots/redesign/` 下按 `before-*.png` / `after-*.png` 成对存放。`before-*` 取自此前各里程碑
验收时在模拟器上留存的旧界面截图（M0–M5 轮次，非本次重拍）；`after-*` 为本轮 8 条打磨完成后
（2026-11-12）在 iPhone 17e 模拟器（iOS 27.1）上按统一数据集重拍，反映最终的双 Tab 导航与
设置内导入/收件箱/诊断。两者机型/系统版本可能不同，只用于看视觉语言的变化，不用于像素级
比对。

| 界面 | 旧 | 新 | 变化点 |
| --- | --- | --- | --- |
| 引导页 | `before-onboarding.png` | `after-onboarding.png` | 系统分组列表 → 卡带 Hero + 功能卡 + 底部双按钮，口号与四段说明保留 |
| 资料库（有内容） | `before-library.png` | `after-library.png` | 纯列表 → 统计 Hero + 酸柠播放键 + 筛选 chip + 描边条目卡 |
| 播放页 | `before-playback.png` | `after-playback.png` | 系统播放器控件 → 卡带封面 + 常驻状态贴纸 + 贴纸式传输控制；队列默认折叠 |
| 导入页（结果） | `before-import.png` | `after-import.png` | 表单式导入 → Hero + 快速导入卡（内嵌上次结果/进度）+ 结果卡；不再出现示例入口 |
| 设置 | `before-settings.png` | `after-settings.png` | Form 分组 → 磁带卡 + kicker；导入/收件箱/诊断收敛为子页入口 |
| 收件箱 | `before-inbox.png` | `after-inbox.png` | 计数/空状态 → 计数卡 + 虚线贴纸空状态 + 运行/错误卡；现为设置子页 |
| 诊断 | `before-diagnostics.png` | `after-diagnostics.png` | 技术列表 → 分区工具卡，数值 mono，签名到期横幅卡片化；示例内容只在这里生成 |
| 播放列表 | `before-playlists.png` | `after-playlists.png` | 默认行 → 卡行 + 智能列表贴纸行；空态卡移到智能列表下方 |
| Wi-Fi 上传 | `before-wifi.png` | `after-wifi.png` | 表单 → 连接/PIN/二维码/活动卡，状态胶囊化 |
| 基准 | `before-benchmark.png` | `after-benchmark.png` | 表格 → 状态卡 + 动作卡 + mono 结果卡 |

（前后对照：左旧右新。点击图片可看原图。）

### 引导页
<table><tr>
<td><img src="screenshots/redesign/before-onboarding.png" width="300" alt="旧引导页"></td>
<td><img src="screenshots/redesign/after-onboarding.png" width="300" alt="新引导页"></td>
</tr></table>
变化点：系统分组列表变成卡带 Hero + 功能卡 + 底部行动区，口号与四段说明完整保留。

### 资料库
<table><tr>
<td><img src="screenshots/redesign/before-library.png" width="300" alt="旧资料库"></td>
<td><img src="screenshots/redesign/after-library.png" width="300" alt="新资料库"></td>
</tr></table>
变化点：统计信息变成 Hero 卡，条目变成描边磁带卡，筛选与播放入口变成贴纸/胶囊控件。

### 播放页
<table><tr>
<td><img src="screenshots/redesign/before-playback.png" width="300" alt="旧播放页"></td>
<td><img src="screenshots/redesign/after-playback.png" width="300" alt="新播放页"></td>
</tr></table>
变化点：系统播放控件变成卡带封面 + 常驻状态贴纸 + 贴纸式传输键；队列收进「展开当前队列」，
不再把整个资料库铺在播放页。

### 导入页
<table><tr>
<td><img src="screenshots/redesign/before-import.png" width="300" alt="旧导入页"></td>
<td><img src="screenshots/redesign/after-import.png" width="300" alt="新导入页"></td>
</tr></table>
变化点：表单变成 Hero + 快速导入卡；上次结果与实时进度内嵌在卡内，导入后按钮仍一屏可达。

### 设置
<table><tr>
<td><img src="screenshots/redesign/before-settings.png" width="300" alt="旧设置"></td>
<td><img src="screenshots/redesign/after-settings.png" width="300" alt="新设置"></td>
</tr></table>
变化点：Form 分组变成白卡 + kicker；开关与选择器保留系统控件，仅换外壳。

### 收件箱
<table><tr>
<td><img src="screenshots/redesign/before-inbox.png" width="300" alt="旧收件箱"></td>
<td><img src="screenshots/redesign/after-inbox.png" width="300" alt="新收件箱"></td>
</tr></table>
变化点：计数与空状态变成计数卡 + 虚线贴纸卡；运行、错误、Finder、外链各自成卡。

### 播放列表
<table><tr>
<td><img src="screenshots/redesign/before-playlists.png" width="300" alt="旧播放列表"></td>
<td><img src="screenshots/redesign/after-playlists.png" width="300" alt="新播放列表"></td>
</tr></table>
变化点：默认行变成硬阴影卡行；智能列表用贴纸徽标与计数胶囊区分。

### Wi-Fi 上传
<table><tr>
<td><img src="screenshots/redesign/before-wifi.png" width="300" alt="旧 Wi-Fi 上传"></td>
<td><img src="screenshots/redesign/after-wifi.png" width="300" alt="新 Wi-Fi 上传"></td>
</tr></table>
变化点：表单变成连接/PIN/二维码/活动四张卡，运行状态用酸柠胶囊表达。

### 基准
<table><tr>
<td><img src="screenshots/redesign/before-benchmark.png" width="300" alt="旧基准"></td>
<td><img src="screenshots/redesign/after-benchmark.png" width="300" alt="新基准"></td>
</tr></table>
变化点：表格变成状态卡 + 动作卡 + mono 结果卡，所有指标保留。

### 诊断
<table><tr>
<td><img src="screenshots/redesign/before-diagnostics.png" width="300" alt="旧诊断"></td>
<td><img src="screenshots/redesign/after-diagnostics.png" width="300" alt="新诊断"></td>
</tr></table>
变化点：技术列表按工具/维护/应用信息/签名/资料库数据/磁盘分区成卡，数值统一 mono。

（以上 20 张图均已落盘于 `docs/screenshots/redesign/`；`after-*` 为 iPhone 17e 模拟器实拍。）

## 5. 测试与验收

### 5.1 自动化测试

- **LocalPodKit 单元/集成测试**：在 `LocalPodKit/` 下执行 `swift test`，**270/270 通过**
  （含 5000 文件导入内存基准与 SwiftData 基准，均为断言性测试）。
- **模拟器 UI 回归**：iPhone Duo，iOS 27.1，全量 18 个套件 **53/53 通过**。

| 套件 | 通过/总数 | 覆盖 |
| --- | --- | --- |
| M0UITests | 4/4 | 启动参数、导入、收件箱、基准 |
| M1UITests | 5/5 | 100 文件导入、取消、报告、维护、5000 条资料库 |
| M2UITests | 5/5 | 播放/暂停、倍速、恢复、后台、结束态 |
| M3UITests | 6/6 | 队列、睡眠定时、设置、播放列表、章节 |
| M4UITests | 3/3 | 外部打开、前台导入、隔离 |
| M5DeliveryUITests | 3/3 | 示例导入、删除后重加、去重 |
| M5LocalizationUITests | 3/3 | 英文 Tab/设置/播放/导入 |
| M5PerformanceTests | 2/2 | 性能门槛 |
| M5SigningUITests | 2/2 | 签名到期开关 |
| M5UITests | 7/7 | 引导、空状态、辅助功能、深色模式 |
| P1SmartPlaylistUITests | 2/2 | 智能列表计数与合集筛选 |
| P1WiFiUITests | 2/2 | Wi-Fi 上传启停与恢复 |
| P2BackupUITests | 1/1 | 备份导出/恢复 |
| P2ChapterUITests | 1/1 | 章节跳转 |
| P2LinkedFolderUITests | 2/2 | 链接文件夹同步/移除 |
| P2NotificationUITests | 1/1 | 导入通知开关与持久化 |
| P2ShortcutUITests | 2/2 | App Intent / Siri 继续播放 |
| P2TrashUITests | 2/2 | 回收站恢复/彻底删除 |

回归过程中发现并修复过以下「新布局导致元素不可达」的问题。除导航/信息架构的显式规格变更
（Tab 收敛、导入/收件箱/诊断迁入设置）同步更新测试路径外，其余全部改的是 App 代码：

- 导入页的「最近导入」空状态被推到视口外 → 内嵌进快速导入卡；
- 播放列表空态卡把「按合集」行推出首屏 → 移到智能列表下方；
- 收件箱的「上次结果」被高大 Hero 卡推出首屏 → 计数卡与结果/错误卡置顶；
- Wi-Fi 上传页运行态的连接/PIN 卡在介绍卡下方、List 未实例化 → 运行态分区排在介绍卡之前；
- 设置页 Wi-Fi 入口滚到导航栏下方时仍被报为可点 → 卡内保留一行 `LOCAL LAN · PIN` kicker，
  使入口的 a11y 帧保持紧凑（315×44），被导航栏遮住时正确报不可点，测试或用户都会继续滚动到
  真正可点的位置；
- 设置页首屏过高使签名卡中心落在窗口外 → 倍速/间隔改为行内紧凑排布，签名卡上移；
- 签名开关所在卡片保留一行说明文案：实测单元素行会被 SwiftUI 把 a11y 帧提升为整行
  （450×63），而真实开关只有 310×28，测试按行框 0.9 取点会落到开关右侧空白；多一个
  可访问元素后帧恢复精确。
- 设置子页的「完成」在 iOS 27 的浮动导航栏里不进入可访问性树 → 改为 `safeAreaInset` 固定胶囊，
  任意滚动位置都可点；
- 导入与收件箱两个 `NavigationLink` 同处一张 `TapeCard`/一个 List 行时，SwiftUI 把整张卡
  报告为两个链接的 a11y 帧，点导入会打开收件箱 → 拆成两张卡；
- 启动参数深链落到设置子页时被复用为设置根页（sheet 内容首次构造于 destination 为 nil 时）→
  `.id(settingsDestination)` 让每次呈现按目标页重建；
- 诊断页推入的基准页仍自带 `NavigationStack`（原为 Tab 根页），嵌套栈使插入按钮不可达 →
  `BenchmarkView(embedded:)` 去掉内层栈；
- 诊断页的导入状态原本埋在「测试与示例内容」卡内、位于维护卡下方 → 有导入/结果时置顶为
  IMPORT 分区，进度与结果首屏可见；
- 播放页进度条最初用裸 `DragGesture` 自绘拖动，会抢占从进度条开始的纵向滑动，导致列表滚不到
  章节区 → 触摸改由覆盖其上的原生 Slider 承担（视觉仍是自绘进度条与圆点），纵向滚动恢复正常。

最终一轮全量回归使用收尾后的代码重跑，结果以上表为准。

### 5.2 手工验收

见第 6 节清单；建议按顺序走一遍并逐项勾选。

## 6. Owner 人眼验收清单

运行方式：用 Xcode 打开 `~/Dev/code/localpod-redesign/LocalPod.xcodeproj`，选 iPhone 模拟器
（或真机）跑 `LocalPod` scheme。每条都写清「在哪一屏、看什么、什么算通过」。全部勾完即通过验收。

**A. 视觉语言（任意一屏）**
- [ ] **A1 描边与硬阴影**：看卡片/按钮边缘 → 1.5px 墨黑描边 + 右下 4px 无模糊硬阴影，无毛玻璃、无渐变光晕 → 通过。
- [ ] **A2 字体**：看标题/数字 → 标题为 Space Grotesk（中文回退苹方）、数字与英文技术标签为 IBM Plex Mono → 通过。
- [ ] **A3 色彩纪律**：看整屏 → 奶油底为主，酸柠只出现在当前项/主行动/进度，珊瑚只在贴纸与警示，电紫只做次强调 → 通过。
- [ ] **A4 动效**：按任意按钮、切 Tab → 按压有回弹、贴纸/选中态有弹簧感（约 260ms），不卡顿、不拖沓 → 通过。

**B. 资料库（Tab「资料库」）**
- [ ] **B1 空库**：启动后看资料库 → 虚线卡 + `NO TAPES` 贴纸 + 「还没有导入内容」+ 选择文件夹按钮 → 通过。
- [ ] **B2 有内容**：在 设置 → 诊断 生成示例后看资料库 → 统计 Hero（3 条 / 1 个合集 / 172 KB）、酸柠播放键、筛选 chip、条目卡 → 通过。
- [ ] **B3 详情**：点一条条目 → 标题、来源「示例」、合集「示例内容」、时长、操作按钮齐全 → 通过。
- [ ] **B4 入口**：看右上角 → 齿轮能打开设置；播放列表图标能进入播放列表页 → 通过。

**C. 导入（资料库 → 齿轮 →「导入与文件夹」）**
- [ ] **C1 Hero**：看顶部 → 「把声音装进磁带盒」与「选择文件夹（文件 App）」按钮；页面不再出现「添加示例内容」→ 通过。
- [ ] **C2 原地导入**：选一个真实文件夹导入 → 结果摘要出现；到 设置 → 链接文件夹 能看到该文件夹，磁盘占用不随媒体大小增长（未复制进沙盒）→ 通过。
- [ ] **C3 去重**：再次导入同一文件夹 → 摘要显示「重复 N」，资料库不新增 → 通过。
- [ ] **C4 最近导入**：有内容时看底部 → 最近 5 条条目卡 + Wi-Fi 上传入口；空库时顶部提示「还没有导入内容」→ 通过。

**D. 播放（Tab「播放」）**
- [ ] **D1 播放器**：看顶部 → 卡带封面 + 酸柠状态贴纸（就绪/播放中/已暂停）；「播放中」字形干净、无重影或双层描边 → 通过。
- [ ] **D2 传输**：点播放/暂停、快退/快进、上一首/下一首 → 均有响应且时间/进度变化 → 通过。
- [ ] **D3 进度条拖动**：按住进度条拖到任意位置 → 拖动中有时间预览，松手后从新位置继续播放 → 通过。
- [ ] **D4 倍速**：横向滑动倍速 chip → 0.5 / 0.8 / 1.0 / 1.2 / 1.5 / 1.8 / 2.0 / 2.5 / 3.0× 共 9 档，切换后速率标签与听感变化 → 通过。
- [ ] **D5 队列**：播放页不再铺整个资料库；默认只显示「队列 · N」与「展开当前队列」→ 点开后才出现随机/循环/清空和队列行，再点「收起当前队列」恢复 → 通过。
- [ ] **D6 工具栏**：看导航栏 → 睡眠定时菜单可选 1 分钟并出现状态行；齿轮打开设置 → 通过。
- [ ] **D7 章节**：看章节列表 → 点章节能跳转到对应时间 → 通过。

**E. 设置（资料库 → 齿轮）**
- [ ] **E1 分区**：看设置页 → DEFAULTS / SIGNING / STORAGE / IMPORT / WI-FI / FOLDERS / BACKUP / NOTIFICATIONS / IMPORT LOG / ABOUT 卡片齐全；「导入与文件夹」「收件箱」「诊断」三个入口在 IMPORT 卡内 → 通过。
- [ ] **E2 控件**：操作默认倍速 chip、快进/快退选择器、恢复位置/自动下一集分段、签名开关 → 均为系统控件但嵌在磁带卡内，行为正常 → 通过。
- [ ] **E3 示例内容**：进入 设置 → 诊断 →「测试与示例内容」→ 点生成示例，资料库出现 3 条；点删除示例 → 计数 0；导入页始终不出现示例入口 → 通过。
- [ ] **E4 其它设置**：链接文件夹、备份导出/导入、通知开关、导入记录、关于 → 都存在且可操作 → 通过。
- [ ] **E5 子页返回**：从上述任一设置子页（导入 / 收件箱 / 诊断）顶部点「完成」→ 关闭设置回到原 Tab；子页滚动后按钮仍在 → 通过。

**F. 其它界面**
- [ ] **F1 引导页**：首次安装或 `--m5-show-onboarding` → 卡带 Hero + 四段说明 + 开始使用/去导入/跳过，三个按钮都能点 → 通过。
- [ ] **F2 回收站**：资料库删除条目后进入回收站 → 恢复 / 彻底删除均有确认框且生效 → 通过。
- [ ] **F3 播放列表**：新建列表 → 播放全部/随机可用、条目可排序/删除；智能列表「按合集」可进入并按合集筛选 → 通过。
- [ ] **F4 收件箱**：设置 → 收件箱 → 计数卡、虚线贴纸空状态；触发导入后运行/错误/最近结果卡完整 → 通过。
- [ ] **F5 诊断**：设置 → 诊断 → 工具/维护/应用信息/签名/资料库数据/磁盘路径均可读，维护按钮可运行；导入跑在诊断页时状态卡置顶 → 通过。
- [ ] **F6 基准**：插入 5000 条 → 状态/结果数字为 mono；列表行可进入；清理可用 → 通过。
- [ ] **F7 Wi-Fi 上传**：启动服务 → 地址/PIN/二维码/活动计数出现；停止、错误重试可用 → 通过。

**G. 本地化 / 辅助功能 / 约束**
- [ ] **G1 英文模式**：切英文后看两个 Tab（Library / Playback）、设置标签、播放状态、导入摘要、队列展开/收起 → 全英文；合集名/文件名等用户数据保持中文 → 通过。
- [ ] **G2 中文模式**：切中文 → 功能文案无英文泄漏（设计用 ALL-CAPS kicker / 贴纸英文除外）→ 通过。
- [ ] **G3 动态字体**：把系统字号调到最大看主要屏幕 → 文字不截断、按钮命中区不小于 44pt → 通过。
- [ ] **G4 约束**：导入一个视频文件 → 只出声音、不显示画面；App 无 CarPlay、无内购；未引入 App Groups / Push / iCloud 容器（免费 Apple ID 可侧载）→ 通过。

**H. Owner 8 条打磨逐项**
- [ ] **H1 示例内容**：正式流程（资料库 / 播放 / 导入）看不到任何示例按钮或示例条目；只有 设置 → 诊断 能手动生成 → 通过。
- [ ] **H2 合集排序**：进入合集列表 → 排序菜单含自然 / 自然倒序 / 名称 / 导入时间 / 手动；选手动后可拖动行改变顺序，退出重进顺序保留 → 通过。
- [ ] **H3 原地导入**：导入外部文件夹后，用 文件 App 修改其中一个文件名或删除一个文件 → 回 App 重扫/回前台，条目按缺失标记或新增更新；磁盘占用不增加媒体副本 → 通过。
- [ ] **H4 继续播放状态**：资料库「继续播放」条目打开状态菜单 → 标记已完成后从继续播放消失；标记未完成后重新出现；重置进度后回到未开始 → 通过。
- [ ] **H5 队列折叠**：播放页看不到整个资料库；只有「展开当前队列」入口，展开/收起正常 → 通过。
- [ ] **H6 进度条 seek**：拖动进度条任意位置松手，播放位置与锁屏/控制中心进度同步 → 通过。
- [ ] **H7 重影**：播放中贴纸文字边缘干净，截屏放大无第二层字形 → 通过。
- [ ] **H8 Tab 收敛**：底部只有资料库 / 播放两个 Tab；导入、收件箱、诊断都在设置内，原有功能均可到达 → 通过。
