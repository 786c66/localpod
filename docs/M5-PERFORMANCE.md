# M5 性能基线

## 范围

M5 只记录**模拟器基线**，不设通过/失败阈值。以下项目明确仍是真机待测，本文不把它们写成已通过：

- 1 GB 文件夹导入；
- 最老支持机型（iOS 17 兼容的旧 iPhone）；
- 连续 2 小时后台音频播放（发热、耗电、内存、进度保存）。

## 环境

| 项 | 值 |
| --- | --- |
| Mac | Apple M4，macOS 27.0.1 (26A434) |
| Xcode | 27.1 (27A9275) |
| 模拟器 | iPhone Duo，iOS 27.1 (24A94425)，UDID `3055696C-BC73-4190-A3F7-EE0AC55F1EE6` |
| App | Debug 构建，iOS 17.0 deployment target，Swift 6 |
| 测试 | `LocalPodUITests/M5PerformanceTests`（XCTest） |

模拟器共享 Mac 的 CPU/内存/磁盘，数值不能外推到真机。

## 命令

只运行性能测试：

```bash
xcodebuild test \
  -project LocalPod.xcodeproj \
  -scheme LocalPod \
  -destination 'platform=iOS Simulator,id=3055696C-BC73-4190-A3F7-EE0AC55F1EE6' \
  -only-testing:LocalPodUITests/M5PerformanceTests
```

M5 端到端回归时同一条命令可再加 `-only-testing` 选择 M5Signing/M5Delivery/M5UITests（见 `docs/M5-REPORT.md` 的最终命令）。

## 方法

### 1. 冷/干净启动

`testAppLaunchPerformance`：

- 每次迭代先 `app.terminate()`，再带 `--m0-reset-data --m5-skip-onboarding` 启动；
- `--m0-reset-data` 每次删除 SwiftData store、`Application Support/Media`、staging、收件箱、封面缓存和设置，因此这是**偏悲观的“干净数据启动”**，不是日常热启动；
- `XCTApplicationLaunchMetric()`，`XCTMeasureOptions.iterationCount = 3`；
- 只测 3 次，避免把 UI 测试总时长推到 2–3 分钟以上。

### 2. 资料库滚动

`testLibraryScrollPerformanceWithFiveThousandItems`：

- 启动参数 `--m0-reset-data --m5-skip-onboarding --m1-seed-library-5000`；
- 等待 `libraryStatsText` 显示 `5,000 条`（约 5,000 条 SwiftData 行，媒体文件为占位/缺失状态，这是列表压力夹具，不是 5,000 个真实文件）；
- 度量指标 `XCTOSSignpostMetric.scrollDecelerationMetric`，3 次迭代；
- 每次迭代在资料库列表上执行一次 `swipeUp(velocity: .fast)`；
- 不对滚动时长做硬阈值断言，只记录 XCTest 输出的平均值与相对标准差。

## 结果（本次运行）

命令：`xcodebuild test ... -only-testing:LocalPodUITests/M5PerformanceTests`，Debug，iOS 27.1 模拟器。

| 指标 | 迭代 | 平均值 | 相对标准差 | 各次值 |
| --- | ---: | ---: | ---: | --- |
| App 启动（`XCTApplicationLaunchMetric`） | 3 | **2.473 s** | 0.449% | 2.471920 / 2.460549 / 2.487657 s |
| 资料库滚动减速（`scrollDecelerationMetric`） | 3 | **2.433 s** | 0.060% | 2.430630 / 2.433579 / 2.433886 s |

本地化前三次运行启动基线为 2.481 s（RSD 0.343%）、2.470 s（RSD 0.379%）和 2.499 s（RSD 0.553%），滚动为 2.434 s；本地化后独立回归为 2.473 s（RSD 0.449%），滚动 2.433 s（RSD 0.060%）。差异在模拟器噪声范围内。

XCTest 原始输出（摘要）：

```text
measured [Duration (AppLaunch), s] average: 2.473, relative standard deviation: 0.449%,
values: [2.471920, 2.460549, 2.487657]

measured [Duration (Scroll_Deceleration), s] average: 2.433, relative standard deviation: 0.060%,
values: [2.430630, 2.433579, 2.433886]
```

### 解读

- **启动约 2.47 s 包含每次清空数据**（删 SwiftData store、媒体、收件箱、设置）。日常覆盖安装后的启动不执行 `--m0-reset-data`，通常更快；该数字用于回归对比，不是用户感知的固定冷启动值。
- **滚动 2.433 s 是系统滚动减速 signpost 的持续时间**，代表一次快速上滑后的减速过程，不是“滚动卡顿 2.4 秒”。3 次几乎一致说明合成手势和列表行为稳定；它只能用于同一模拟器/同一测试下的回归对比。
- 5,000 行是 SwiftData 列表虚拟化压力测试；没有真实媒体文件、没有解码、没有网络。它不覆盖 1 GB 导入或播放。

## 启动优化结论

**本次未应用启动优化。** 检查启动路径后没有发现“低风险且不改变语义”的明显优化点：

- `LocalPodApp.init` 创建 SwiftData 容器、确保收件箱存在，均为启动必需；
- `RootView.task` 依次挂载播放会话、启动维护/收件箱、可选 Debug 种子、首次引导解析、安排本地签名提醒；
- 性能测试的 `--m0-reset-data` 本身包含大量文件删除和 store 重建，是测量设计的一部分，不应为优化数字而移除。

为避免回归，没有改动导入、资料库查询、启动维护或 SwiftData 模型。后续如要优化，应先在同一模拟器上建立本表作为对照，再单独做“无 `--m0-reset-data` 的日常启动”基线。

## 真机待测（未通过，勿写成已通过）

| 项目 | 状态 | 建议方法 |
| --- | --- | --- |
| 1 GB 文件夹导入 | **待真机验证** | 真机选择 ≥1 GB 音频文件夹，记录扫描/复制/探测耗时、峰值内存、失败与去重；模拟器不能代表闪存和热限制 |
| 最老支持 iPhone | **待真机验证** | 在 iOS 17 兼容的最老设备上重跑启动/5,000 行滚动，并做一次 1 GB 导入 |
| 2 小时连续播放 | **待真机验证** | 锁屏/后台播放 2 小时，记录电量、发热、内存、进度保存与中断恢复 |
| 本地通知真实送达 | **未验证** | 见 `docs/M5-INSTALL-RESIGN-BACKUP.md` 的演练清单；当前只验证了诊断横幅和开关持久化 |
| 真机安装/重签/备份恢复 | **待真机验证** | 同上文档的证据表 |

## 如何复现与记录

1. 在本机用上面的 `xcodebuild` 命令运行；XCTest 会在日志里打印 `measured [...]` 行。
2. 若用 Xcode 运行，打开 Test Report → Performance，查看每个指标的 3 次值和平均值。
3. 记录时必须同时写明：Mac 型号、Xcode 版本、模拟器/真机型号与系统版本、Debug/Release、是否带 `--m0-reset-data`。
4. 不要为通过“验收”而添加设备相关硬阈值；本项目只比较同一环境下的前后回归。
