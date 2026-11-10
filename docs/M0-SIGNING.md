# LocalPod 免费 Apple ID 侧载与 7 天重签验证

> 目标：用免费 Personal Team 把 M0 App 装到真机，确认描述文件约 7 天到期、重签后数据保留，并记录证据。
> 约束：不做 App Groups、iCloud 容器、Push、Keychain Sharing、TestFlight；当前不上架。

## 1. 准备

- Mac 上 Xcode 已登录免费 Apple ID：Xcode → Settings → Accounts。
- iPhone 与 Mac 用数据线连接，iPhone 信任此电脑。
- iPhone 打开 **设置 → 隐私与安全性 → 开发者模式**（iOS 16+），按提示重启并确认。
- 同一 Bundle ID 贯穿所有重签：默认 `com.localpod.app`。若被占用，改 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER`（或 Xcode target 设置），之后每次重签都用同一个。

## 2. 首次安装

1. 打开 `LocalPod.xcodeproj`。
2. 选择 **LocalPod** target → **Signing & Capabilities**：
   - Team 选择你的 Personal Team；
   - 勾选 Automatically manage signing；
   - 不添加 App Group、iCloud、Push 等 capability。
3. 顶部设备选择你的 iPhone，Run。
4. 首次启动若被拦：iPhone **设置 → 通用 → VPN 与设备管理** → 信任你的开发者证书。
5. App 启动后进入 **诊断** 页，确认：
   - Bundle ID 与 Xcode 一致；
   - 描述文件名称、Team、App ID；
   - **到期时间 / 剩余天数**（免费账号通常约 7 天）。
6. 截图或点“复制诊断信息”保存证据。

## 3. 建立可核对的数据

在真机上：

1. 在“导入”页点“导入内置演示文件夹（100 个文件，3 层）”，等进度 100/100。
2. 在“播放”页播放内置音频，确认锁屏/控制中心（见 M0 报告的真机清单）。
3. 在“诊断”页记录：资料库 100 条、基准 0 条（或按需跑 5k）。
4. 也可以从 Finder/文件 App 导入 1 个文件，记录来源。

## 4. 到期与重签

1. 等到诊断页显示剩余 0 天/已过期，或直接等约 7 天后启动 App。
2. 预期：App 图标仍在，但点击后无法启动（描述文件过期）。
3. 不要先删除 App。保持同一 Bundle ID，在 Xcode 中连接 iPhone，重新 Run。
4. Xcode 会重新签名并覆盖安装。若 Xcode 提示无法安装，先在 iPhone 删除描述文件/重启，或检查设备是否仍在该免费账号的 3 台设备限制内。
5. 重新打开 App → 诊断页：
   - 新的到期时间约 7 天后；
   - 资料库条目仍为 100（或你导入的数量）；
   - 之前导入的文件仍能播放；
   - 媒体库路径仍在 `Application Support/Media`。

> 注意：如果先删除 App 再安装，或更换 Bundle ID，沙盒容器会变化，数据会丢失。免费账号重签应尽量覆盖安装；需要更高可靠性时再用 SideStore/AltStore 自动续签。

## 5. 免费账号限制（当前设计已避开）

| 限制 | 影响 | 当前处理 |
| --- | --- | --- |
| 描述文件约 7 天 | App 到期无法启动 | 诊断页显示到期；同 Bundle ID 重签 |
| 无 App Groups | Share Extension 不能可靠共享容器 | 不做 Share Extension；用文件夹/收件箱/文件选择；Wi-Fi 上传 P1 |
| 无 iCloud 容器 | 不能直接同步媒体 | 本地沙盒导入，iCloud 文件按需下载（M1） |
| 无 Push | 无远程通知 | 不需要 |
| 无 TestFlight | 不能分发测试 | Xcode 真机安装/侧载 |
| 设备数限制 | 免费账号最多少量设备 | 个人自用足够 |

## 6. M0 签名证据记录

| 项 | 记录 |
| --- | --- |
| 首次安装日期 | |
| 描述文件到期时间（诊断页） | |
| 首次安装后资料库条数 | |
| 到期日期/现象 | |
| 重签日期 | |
| 重签后描述文件到期时间 | |
| 重签后资料库条数/文件可播放 | |
| 结论（数据是否保留） | |

完成后把本表填好，并把诊断页截图放到 `docs/screenshots/`（文件名建议 `M0-signing-expiry.png`、`M0-signing-resign.png`）。
