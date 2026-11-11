# LocalPod 设计重构报告 · Direction C「节拍 / Expressive」

> 分支：`feat/expressive-redesign` · Worktree：`~/Dev/code/localpod-redesign`
> 设计规格：`docs/DESIGN-SPEC.md`（来源 `~/Dev/code/podcast-design/podcast-design-directions.html` 的 Direction C）
> 口号：**把收听变成一盒磁带。**

## 1. 一句话结论

现有 LocalPod 的全部界面已从「系统默认表单 + 列表」换成 Direction C 的磁带盒语言：奶油底、
1.5px 墨黑描边、4px 硬阴影、酸柠/珊瑚/电紫三色贴纸、Space Grotesk + IBM Plex Mono 字阶、
260ms 弹簧转场与按压回弹。所有功能、字段、可访问性标识保持不变；仅 iOS、纯音频、无 CarPlay、
无内购、免费 Apple ID 侧载的约束没有被触碰（未引入 App Groups / Push / iCloud 容器）。

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
- 自定义磁带 Tab 栏 `TapeTabBar`：五个入口、酸柠圆形选中态、按压回弹、贴纸式顶部分隔线。
- 根视图改为 TabView + 兄弟节点 Tab 栏（不悬浮），保证列表视口不被遮挡；功能与测试标识不变。

### 2.3 各界面

- **资料库**：统计 Hero 卡（条数 / 合集 / 占用 + 酸柠播放贴纸）、筛选 chip、合集卡、磁带盒式条目行、
  回收站区、播放列表入口；条目详情改为贴纸 Hero + 磁带信息卡；加入播放列表改为贴纸弹层。
- **播放页**：卡带封面 + 状态贴纸（常驻、可滚动时仍可读）、传输键优先的控制卡、进度条、倍速 chip、
  睡眠定时/设置收纳进导航工具栏、队列头部的随机/循环/清空胶囊、章节列表。
- **导入页**：Hero 卡（FOLDERS / AUDIO ONLY）、快速导入卡内嵌「上次结果 + 实时进度」状态块
  （导入后示例按钮仍保持一屏可达）、详细结果卡、问题卡、最近导入与空状态。
- **设置**：全部 Form 分组改为白卡 + ALL-CAPS kicker；倍速 chip、原生 Toggle/Picker 保留在卡内；
  存储/样本/Wi-Fi/链接文件夹/备份/通知/导入记录/关于各自成卡；分享面板同步换肤。
- **引导页**：卡带 Hero + 功能卡 + 底部行动区（开始使用 / 去导入 / 跳过），保留全部四段说明。
- **收件箱**：计数卡与「上次结果 / 需要处理」置顶（导入完成后首屏可见），下面是 DROP ZONE
  说明与手动扫描卡、空状态虚线卡、运行中/错误卡、Finder/外链/路径卡。
- **诊断 / 基准**：工具、维护、应用信息、签名、资料库数据、磁盘路径分区成卡；数值一律 mono；
  基准状态、动作、结果、列表行换肤，未删任何指标。
- **Wi-Fi 上传**：说明卡、连接地址/PIN/二维码/活动卡、停止/重试按钮、限制说明卡；服务生命周期未动。
- **回收站 / 播放列表 / 智能列表**：统计 Hero、卡片化列表行、虚线贴纸空状态、滑动操作与确认框原样保留。

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
   把示例按钮推到首屏之外；XCUITest 一次 `swipeUp` 约 681pt，会直接过冲，重加流程点不中。
   合并后按钮始终一屏可达，信息密度也更高。
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
验收时在模拟器上留存的旧界面截图（M0–M5 轮次，非本次重拍）；`after-*` 为本次重构后在 iPhone 17e
模拟器（iOS 27.1）上按统一数据集重拍。两者机型/系统版本可能不同，只用于看视觉语言的变化，不用于像素级
比对。

| 界面 | 旧 | 新 | 变化点 |
| --- | --- | --- | --- |
| 引导页 | `before-onboarding.png` | `after-onboarding.png` | 系统分组列表 → 卡带 Hero + 功能卡 + 底部双按钮，口号与四段说明保留 |
| 资料库（有内容） | `before-library.png` | `after-library.png` | 纯列表 → 统计 Hero + 酸柠播放键 + 筛选 chip + 描边条目卡 |
| 播放页 | `before-playback.png` | `after-playback.png` | 系统播放器控件 → 卡带封面 + 常驻状态贴纸 + 贴纸式传输控制 |
| 导入页（结果） | `before-import.png` | `after-import.png` | 表单式导入 → Hero + 快速导入卡（内嵌上次结果/进度）+ 结果卡 |
| 设置 | `before-settings.png` | `after-settings.png` | Form 分组 → 磁带卡 + kicker；开关/选择器保留系统本体 |
| 收件箱 | `before-inbox.png` | `after-inbox.png` | 计数/空状态 → 计数卡 + 虚线贴纸空状态 + 运行/错误卡 |
| 诊断 | `before-diagnostics.png` | `after-diagnostics.png` | 技术列表 → 分区工具卡，数值 mono，签名到期横幅卡片化 |
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
变化点：系统播放控件变成卡带封面 + 常驻状态贴纸 + 贴纸式传输键，队列操作收进头部胶囊。

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

- **LocalPodKit 单元/集成测试**：在 `LocalPodKit/` 下执行 `swift test`，**245/245 通过**
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

回归过程中发现并修复过以下「新布局导致元素不可达」的问题，全部改的是 App 代码、未改动任何测试：

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
- [ ] **B2 有内容**：导入示例后看资料库 → 统计 Hero（3 条 / 1 个合集 / 172 KB）、酸柠播放键、筛选 chip、条目卡 → 通过。
- [ ] **B3 详情**：点一条条目 → 标题、来源「示例」、合集「示例内容」、时长、操作按钮齐全 → 通过。
- [ ] **B4 入口**：看右上角 → 齿轮能打开设置；播放列表图标能进入播放列表页 → 通过。

**C. 导入（Tab「导入」）**
- [ ] **C1 Hero**：看顶部 → 「把声音装进磁带盒」与「选择文件夹（文件 App）」按钮 → 通过。
- [ ] **C2 导入与结果**：点「添加示例内容」→ 卡内出现「上次结果 · 导入 3 …」与「文件 3/3」，且按钮仍在首屏 → 通过。
- [ ] **C3 去重**：再次点「添加示例内容」→ 摘要显示「重复 3」，资料库不新增 → 通过。
- [ ] **C4 最近导入**：有内容时看底部 → 最近 5 条条目卡 + Wi-Fi 上传入口；空库时顶部提示「还没有导入内容」→ 通过。

**D. 播放（Tab「播放」）**
- [ ] **D1 播放器**：看顶部 → 卡带封面 + 酸柠状态贴纸（就绪/播放中/已暂停）→ 通过。
- [ ] **D2 传输**：点播放/暂停、快退/快进、上一首/下一首 → 均有响应且时间/进度变化 → 通过。
- [ ] **D3 队列**：向下滚 → 「队列 · N」与随机/循环/清空胶囊；滚动后状态贴纸仍可见且不挡点击 → 通过。
- [ ] **D4 工具栏**：看导航栏 → 睡眠定时菜单可选 1 分钟并出现状态行；齿轮打开设置 → 通过。
- [ ] **D5 章节**：看章节列表 → 点章节能跳转到对应时间 → 通过。

**E. 设置（资料库 → 齿轮）**
- [ ] **E1 分区**：看设置页 → DEFAULTS / SIGNING / STORAGE / SAMPLES / WI-FI / FOLDERS / BACKUP / NOTIFICATIONS / IMPORT LOG / ABOUT 卡片齐全 → 通过。
- [ ] **E2 控件**：操作默认倍速 chip、快进/快退选择器、恢复位置/自动下一集分段、签名开关 → 均为系统控件但嵌在磁带卡内，行为正常 → 通过。
- [ ] **E3 示例删除**：删除示例 → 计数 0 + 摘要「已删除 3」；回导入页重新添加 → 资料库恢复 3 条 → 通过。
- [ ] **E4 其它设置**：链接文件夹、备份导出/导入、通知开关、导入记录、关于 → 都存在且可操作 → 通过。

**F. 其它界面**
- [ ] **F1 引导页**：首次安装或 `--m5-show-onboarding` → 卡带 Hero + 四段说明 + 开始使用/去导入/跳过，三个按钮都能点 → 通过。
- [ ] **F2 回收站**：资料库删除条目后进入回收站 → 恢复 / 彻底删除均有确认框且生效 → 通过。
- [ ] **F3 播放列表**：新建列表 → 播放全部/随机可用、条目可排序/删除；智能列表「按合集」可进入并按合集筛选 → 通过。
- [ ] **F4 收件箱**：看空白态与计数 → 计数卡、虚线贴纸空状态；触发导入后运行/错误/最近结果卡完整 → 通过。
- [ ] **F5 诊断**：看各卡 → 工具/维护/应用信息/签名/资料库数据/磁盘路径均可读，维护按钮可运行 → 通过。
- [ ] **F6 基准**：插入 5000 条 → 状态/结果数字为 mono；列表行可进入；清理可用 → 通过。
- [ ] **F7 Wi-Fi 上传**：启动服务 → 地址/PIN/二维码/活动计数出现；停止、错误重试可用 → 通过。

**G. 本地化 / 辅助功能 / 约束**
- [ ] **G1 英文模式**：切英文后看五个 Tab、设置标签、播放状态、导入摘要 → 全英文；合集名/示例文件名等用户数据保持中文 → 通过。
- [ ] **G2 中文模式**：切中文 → 功能文案无英文泄漏（设计用 ALL-CAPS kicker / 贴纸英文除外）→ 通过。
- [ ] **G3 动态字体**：把系统字号调到最大看主要屏幕 → 文字不截断、按钮命中区不小于 44pt → 通过。
- [ ] **G4 约束**：导入一个视频文件 → 只出声音、不显示画面；App 无 CarPlay、无内购；未引入 App Groups / Push / iCloud 容器（免费 Apple ID 可侧载）→ 通过。
