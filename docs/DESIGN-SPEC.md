# LocalPod · Direction C「节拍 / Expressive」设计规格

> 来源：`~/Dev/code/podcast-design/podcast-design-directions.html` 的 `Direction C / Expressive`
> 章节（`#direction-c`、`.phone--c` 及其组件 CSS，三块 393×852 屏幕）。
> 本文是该方向落到 LocalPod（iOS 17+，iPhone，纯音频）的唯一实现口径。
> 口号：**把收听变成一盒磁带。** 粗描边、贴纸、高饱和、玩具般的物理感。

---

## 1. 设计原则

1. **实体感**：所有可点的东西都像一块可以按下去的塑料 / 磁带，而不是发光矩形。按下时硬阴影收缩、块体位移。
2. **盒子感**：奶油底 + 白卡 + 1.5px 墨黑描边 + 4px 无模糊硬阴影；不动用毛玻璃、渐变光晕。
3. **贴纸叙事**：状态、奖励、分类用旋转贴纸表达，不用系统 badge。贴纸会转、会弹。
4. **高饱和但克制**：酸柠只用于「当前 / 主行动 / 进度」；珊瑚用于贴纸与警示；电紫用于次强调与头像；大面积仍是奶油与白。
5. **玩具物理**：260ms 弹簧（response 0.26 / damping 0.55）是唯一主曲线；按压 120ms ease。
6. **信息密度不降级**：这是工具型播客库，不是概念稿。所有原有功能、字段、可访问性标识必须保留，视觉升级不等于功能删减。

---

## 2. 色彩

| Token | 值 | 用途 |
| --- | --- | --- |
| `cream` | `#FFF3DF` | 全局底色、输入框底、未选 chip 底 |
| `ink` | `#141414` | 文字、描边、硬阴影、主按钮文字 |
| `muted` | `#6E665A` | 次要文字（对奶油约 5.4:1） |
| `faint` | `#9B907E` | 三级文字、mono 元数据 |
| `acid` | `#D8FF3E` | 当前项、主行动、进度、选中态 |
| `coral` | `#FF5A36` | 贴纸、失败/警示、磁带壳、主按钮的对比面 |
| `violet` | `#6C5CE7` | 次强调、头像、分类贴纸、链接态 |
| `card` | `#FFFFFF` | 卡片底 |
| `track` | `#DFD3BF` | 进度槽、分隔线基色 |
| `coralSoft` | `#FFB6A5` | 头像/装饰 |
| `violetSoft` | `#C7BEFF` | 头像/装饰 |
| `peach` | `#FFD0C3` | 封面占位 |

规则：
- 文字只用 `ink` / `muted` / `faint`；不使用纯灰。
- 酸柠底上只用 `ink`；珊瑚底上文字用 `#FFF6E6` 且只用于 ≥16pt / Bold。
- 不再使用系统 `.secondary`（统一映射到 `muted`）与 `Color.accentColor`（统一映射到 `violet` 或 `ink`）。
- 资产目录 `AccentColor` 改为 `violet #6C5CE7`，确保系统控件（Slider、Picker、链接）落在同一色系。

---

## 3. 字体

随包内置（OFL，见 `LocalPod/Resources/Fonts/OFL-*.txt`）：
- **Space Grotesk**：`SpaceGrotesk-Regular / Medium / Bold`（标题、按钮、贴纸、Tab 文字；中文自动回退苹方）。
- **IBM Plex Mono**：`IBMPlexMono-Regular / Medium / SemiBold`（时间、计数、期数、技术标签、设置值）。

iOS 字号映射（设计稿 280pt 宽 → iPhone 393pt，按 1.4× 放大后再按可读性收敛）：

| Token | 字号/字重 | 用途 |
| --- | --- | --- |
| `displayXL` | 40 / Bold | 引导页、空状态大标题 |
| `display` | 34 / Bold | 首页 hero、播放页大标题 |
| `title1` | 28 / Bold | 屏幕标题 |
| `title2` | 22 / Bold | 播放标题、合集详情标题 |
| `title3` | 19 / SemiBold | 区块标题 |
| `headline` | 17 / SemiBold | 卡片标题、列表主标题 |
| `body` | 15 / Regular | 正文 |
| `bodySmall` | 14 / Regular | 密集列表正文 |
| `caption` | 13 / Regular | 辅助说明 |
| `captionSmall` | 12 / Regular | 行内元信息 |
| `kicker` | 11 / Medium，字距 1.4，大写 | 英文眉题 |
| `monoMeta` | 12 / Medium | 时长、期数、设置值 |
| `monoTime` | 12 / Medium，tabular | 播放时间、进度 |
| `monoMicro` | 10.5 / Medium，字距 0.5 |  badges、磁带标签 |
| `sticker` | 12 / Bold | 贴纸文字 |
| `tab` | 10 / SemiBold | Tab 标签 |
| `button` | 16 / Bold | 主按钮 |

标题字距：`display/title` 使用 `-0.02em ~ -0.045em`（SwiftUI `.tracking(-0.8)`）；正文 `0`。
全部字体使用 `relativeTo:` 支持 Dynamic Type；现有可访问字号分支保持不变。

---

## 4. 描边、阴影、圆角、间距

| Token | 值 |
| --- | --- |
| `stroke` | 1.5pt 墨黑（所有卡片、按钮、chip、Tab 顶边、分隔强调） |
| `hairline` | 1pt，`ink` 24% 透明度（列表行内分隔） |
| `hardShadow` | `(x: 4, y: 4), blur: 0, color: ink`（hero、主卡、主按钮） |
| `smallShadow` | `(x: 2, y: 2), blur: 0`（小卡、chip、贴纸、tab 激活圆） |
| `tapeShadow` | `(x: 5, y: 5), blur: 0`（磁带封面） |
| `pressedShadow` | `(x: 1, y: 1), blur: 0` + 位移 `(3, 3)` |
| `radiusCard` | 12（大卡）、8（小卡/封面）、6（缩略图）、3（贴纸） |
| `radiusChip` | Capsule |
| `spacing` | 4 / 8 / 12 / 16 / 20 / 24 / 32 |
| 屏幕水平内边距 | 16（列表卡 14） |
| 区块间距 | 12（列表 section）、20（屏幕大区块） |

**禁止**：模糊阴影、渐变底色、玻璃材质、圆角超过 16（除胶囊）、无描边的悬浮元素。

---

## 5. 动效

| 场景 | 规格 |
| --- | --- |
| 主弹簧 | `.spring(response: 0.26, dampingFraction: 0.55)` |
| 按压 | 120ms ease-out：位移 `(3,3)`、阴影从 4→1、scale 0.98；松手弹簧回位 |
| 卡片进场 | 初始 `rotate 6° + scale 0.96 + opacity 0`，弹簧到 0°/1/1 |
| 贴纸弹出 | 弹簧 `response 0.34 / damping 0.5`：scale 0.6 → 1.08 → 1，rotation −8° → 0 |
| 贴纸摇摆 | 长按/奖励时 ±8° 两段弹簧；不常驻循环，避免干扰阅读 |
| 磁带卷轴 | 播放中连续旋转（约 0.6 圈/秒）；暂停即停；Reduce Motion 下为静态 |
| 进度条 | 值变化 `animation(.linear(duration: 0.25), value: progress)` |
| 页面/分段切换 | `withAnimation(TapeTheme.spring)` 切换内容；不使用系统 slide |
| 触感 | 播放/暂停 `UIImpactFeedbackGenerator(style: .light)`；导入完成 `.success`；贴纸奖励 `.soft` |
| Reduce Motion | 关闭卷轴旋转、贴纸摇摆、入场旋转；保留 120ms 按压反馈 |

---

## 6. 组件规格

### 6.1 TapeCard（基础卡）
白底（或 `acid` / `coral` / `violet` 变体），1.5 描边，圆角 12，硬阴影 4，内边距 16。卡片可叠加 `rotationEffect(±0.6°)` 制造手工感（仅装饰卡，列表容器不转）。

### 6.2 按钮
- **Primary**：`acid` 底、`ink` 文字、圆角 10 或胶囊、1.5 描边、4px 阴影；按下位移 3/阴影 1。
- **Secondary**：`card`/`cream` 底、`ink` 文字、同描边、2px 阴影。
- **Destructive**：`coral` 底、`#FFF6E6` 文字。
- **IconButton**：32–44 圆形，白/奶油底，1.5 描边，2px 阴影；图标 `ink`。
- **Ghost**：无底无阴影，仅文字/图标；用于行内次级操作。
- 所有按钮最小命中 44×44；文字按钮用 `SpaceGrotesk-Medium/Bold`。

### 6.3 贴纸
`TapeSticker`：`coral` / `violet` / `acid` 底，1.5 描边，圆角 3，2px 阴影，默认旋转 +6°（可配 −8…+8），`sticker` 字体。用途：hero 角标（「本周热单」式）、状态（已下载/缺失/已听完）、奖励（连续收听）、空状态。
每屏贴纸不超过 3 个，避免噪音。

### 6.4 Chips
胶囊，1.5 描边，高 30–34；未选 `cream` 底 `ink` 字，选中 `acid` 底 + 2px 阴影；带 `.isSelected` trait。用于速度、筛选、分类、章节。

### 6.5 Tab Bar
- 自定义，奶油底，顶部 1.5 墨黑描边，高度 56 + 安全区。
- 2 项：资料库 / 播放；SF Symbol 22pt。导入、收件箱、诊断不放根 Tab，作为设置 sheet 的子页。
- 激活项：图标置于 32×32 酸柠圆内（1.5 描边 + 2px 阴影），标签 `tab` 字重 SemiBold；未激活 `muted`。
- 按下 scale 0.92；切换弹簧。保留按钮文本（UI 测试按标签点击）。

### 6.6 磁带封面（播放页签名件）
`TapeCover`：珊瑚底，1.5 描边，圆角 10，5px 硬阴影；顶部 mono 标签（`TAPE SESSIONS / 042·90` 风格）；中间奶油窗 + 两枚黑色卷轴（酸柠轴心），播放时旋转；底部酸柠标签条写标题与 mono 时长。尺寸 180–220pt 正方形。无封面图时使用；有内嵌封面时在磁带窗内叠放封面缩略图并保留卷轴。

### 6.7 进度条
高 10pt 胶囊：奶油槽 + 1.5 描边；酸柠填充，右缘 1.5 墨线。保留一个不可见（opacity 0.02）的原生 Slider 覆盖其上，维持 `playbackSlider` 可访问性与拖动/辅助功能调节。

### 6.8 列表行
- 卡行：白卡、1.5 描边、圆角 10、2px 阴影、上下间距 4；内边距 12；最小高 56。
- 缩略图 36×36（圆角 6，1.5 描边，珊瑚/紫/酸柠轮换，字母或波形图标）。
- 主标题 `headline`（17 SemiBold），次行 `monoMeta`（12，faint）。
- 尾部：28 圆形播放/箭头按钮（1.5 描边）。
- 普通行（设置等）：透明底、1pt 24% 分隔线、最小高 44。
- 所有行保留原 `accessibilityIdentifier` 与 label。

### 6.9 开关
自定义 `TapeToggleStyle`：52×32 胶囊，开启酸柠/关闭奶油，1.5 描边；白色 24 圆钮 + 1.5 描边；弹簧 260ms。必须继续暴露 `value` 为 `"1"/"0"`（UI 测试依赖）。

### 6.10 空状态
虚线 1.5 描边大卡（圆角 12，奶油底）+ 60pt 旋转贴纸/星形 + `title2` 标题 + `body` 说明 + Primary CTA。保留原 identifier。

### 6.11 导航栏
系统 NavigationStack 保留（返回手势与 `navigationBars["标题"]` 测试依赖）。全局 `UINavigationBarAppearance`：奶油不透明底、墨黑标题（SpaceGrotesk-Bold 18）、墨黑 tint、1pt 墨黑 24% 底边。页面内的大标题由内容卡承担，系统栏只做导航。

### 6.12 搜索
系统 `.searchable` 保留；通过 `UISearchBarAppearance` 设置奶油底、1.5 描边感、圆角 10、`ink` 文字。

### 6.13 分区头
`TapeSectionHeader`：左列 `kicker`（mono，faint）+ `title3`（19 Bold）；右侧 `monoMeta` 计数或操作。列表 section header 使用同款排版，不加大写系统灰。

---

## 7. 屏幕映射

### 7.1 资料库（Library）
- 顶部 hero（酸柠）：贴纸「本地磁带」、kicker `YOUR MIXTAPE`、`display` 标题「我的磁带盒」、mono 统计（保留 `libraryStatsText`，仍含「N 条 · N 个合集 · 大小」）、右上 44 圆播放最近条目。
- 继续播放：横向大卡或首条 hero 下的「继续听」卡，酸柠进度条；保留 `continueItem-<title>`。
- 视图切换：自定义两枚 chip「条目 / 合集」（保留可点击文本；原 Picker 的选中语义用手动 `.isSelected`）。
- 条目：卡行（缩略图字母/波形、标题、mono 元信息、播放圆钮）；保留 `libraryItem-<title>`，仍用 NavigationLink 进详情。
- 合集：两列磁贴网格（封面块用酸柠/紫/珊瑚/网格/黑底六种变体，±0.6° 旋转），标题 + mono 副行；保留 `collectionRow-<name>`。
- 回收站：底部卡行，保留 `trashSectionLink` / `trashCountText`。
- 搜索、筛选菜单、播放列表入口、设置按钮全部保留。

### 7.2 播放（Playback）
- 顶部 `TapeCover`（磁带）替代原 56pt 缩略图；标题在其下居中（`title2`），mono 副标题；保留 `currentPlaybackTitle` / `playbackPhaseText`。
- 进度条用 6.7；时间行 mono；保留 `currentTimeText` / `remainingTimeText`。
- 控件：44 圆次级按钮（上一首/快退/快进/下一首）+ 64 酸柠圆形主按钮（硬阴影 4，按下收缩）；保留全部 identifier/label。
- 速度 chips、睡眠定时（chip + 菜单）、章节（chunky 章节条，保留行 identifier/label/44pt/contentShape）。
- 队列卡：序号缩略图 + 标题 + mono 时长 + 播放圆钮；保留 `queue*` identifier。
- 资料库/内置测试媒体：卡行 + secondary 按钮。
- 空状态：Tape 空状态（贴纸 + 去资料库）。

### 7.3 导入（Import）
- hero 酸柠：「把声音装进盒子」+ 贴纸；文件夹选择走系统 picker，**原地读取**（security-scoped bookmark），不复制媒体。
- 进度：粗进度条（6.7）+ mono 百分比 + 当前文件；取消按钮 destructive。
- 报告：白卡 + mono 数字三列（导入/重复/失败/不支持）；保留 `import*` identifier。
- 最近导入：卡行。示例内容/演示文件夹不再出现在此页，只在设置 → 诊断中手动生成。

### 7.4 收件箱（Inbox）
- 设置 sheet 的子页（推入），顶部 `safeAreaInset` 固定「完成」胶囊。
- hero（紫贴纸）/空状态贴纸；分类计数用 mono 大数字卡；稳定性提示用酸柠卡；保留 `inbox*` identifier。

### 7.5 设置（Settings）
- 每个逻辑分组一张白卡（Section → 卡），组头用 `TapeSectionHeader` 风格。
- 开关用 6.9；数值用 mono；危险操作（删除示例、恢复）用 coral 按钮。
- 备份/导出/恢复、通知、签名提醒、导入历史、链接文件夹、Wi-Fi 上传入口全部保留原结构与 identifier。
- 「导入与文件夹」「收件箱」「诊断」作为设置子页推入；子页同样使用固定「完成」胶囊。

### 7.6 引导（Onboarding）
- 全屏奶油 + 大贴纸 + 磁带插画；`displayXL` 标题；三条功能点用 chips；主按钮「开始使用」、次按钮「去导入」、跳过。
- 保留 `onboarding*` identifier。

### 7.7 诊断（Diagnostics）
- 签名信息用「磁带标签」卡：mono 值、酸柠/珊瑚状态贴纸；维护/计数卡；保留 `maintenanceDetailText` 等 identifier。
- 「测试与示例内容」卡：示例条目生成/删除、演示/验收文件夹导入只在这里；有导入时状态卡置顶。

### 7.8 回收站 / 播放列表 / 智能播放列表 / Wi-Fi / 基准
- 统一卡行 + hero + 空状态；保留全部 identifier 与文案。

---

## 8. 交互与可达性约束

1. **不删功能**：所有现有按钮、菜单、开关、字段、导航、表单一律保留。
2. **不改文案**：UI 测试断言的文本（「播放中」「已暂停」「章节 · N」「导入 1」「第 N 章：…」等）保持原样。
3. **不改 identifier**：`currentPlaybackTitle`、`playbackPhaseText`、`playbackSlider`、`playPauseButton`、`chapterRow*`、`libraryItem-*`、`collectionRow-*`、`settings*`、`import*`、`inbox*`、`trash*`、`backup*`、`smartPlaylistRow-*`、`wifi*` 等全部保留。
4. **命中区**：所有可点元素 ≥44pt，透明区域用 `.contentShape(Rectangle())` 扩展（章节行历史教训）。
5. **懒加载**：继续使用 List/Form，不用一次性 VStack 替换长列表；UI 测试的 reveal 依赖懒加载行为。
6. **对比度**：正文墨黑/奶油 15:1，次级 5.4:1；珊瑚底白字仅大号粗体。
7. **Dynamic Type**：字体用相对尺寸；现有 accessibilitySize 分支保留；卡片允许换行，禁止截断关键信息。
8. **Reduce Motion / Reduce Transparency**：卷轴与贴纸动效降级；不依赖动画传达状态。
9. **无付费能力**：不引入 App Groups、Push、iCloud 容器、CarPlay、内购；字体随包（OFL），不引入网络字体或第三方 SDK。
10. **纯音频**：视频条目仍只显示音频界面；封面/磁带视觉不引入视频播放画面。

---

## 9. 交付与验收

- 所有屏幕的模拟器 UI 测试（53 个）与 LocalPodKit（270 个）必须全绿。
- 截图对比存 `docs/screenshots/redesign/`，并在 `docs/REDESIGN-REPORT.md` 列出逐屏 before/after 与刻意取舍。
- 人眼验收清单见 `docs/REDESIGN-REPORT.md` 的「Owner 验收清单」。
