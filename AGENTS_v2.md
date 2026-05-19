# AGENTS_v2.md — SleepKit Probe / SleepEnough Alarm Phase 2 计划与进度

> 面向 Codex 的项目级实现说明。当前项目目标已经从「验证 HealthKit 睡眠数据是否实时」转向「Apple Watch 端自研 sleep/wake 检测」。不要再尝试依赖 Apple 官方 sleepAnalysis 的实时更新，也不要尝试伪装或自动打开 Health App。

## 当前实现进度快照

截至分支 `custom-asleep`：

已完成：

1. Phase 1 HealthKit `sleepAnalysis` 实时性验证、日志和导出。
2. watchOS App target：`SleepKitProbe Watch App`。
3. Watch 端 `Start Session` / `Stop Session`、manual awake/asleep 标注、本地 event/epoch 日志。
4. 默认 60 秒 epoch、`motionSampleHz = 1` 的 Core Motion 聚合。
5. 默认 passive HealthKit HR：每个 epoch 查询该分钟内 watchOS 已经保存的 heart-rate samples，不启动 workout live HR。
6. WatchConnectivity summary 同步，含 queued delivery fallback。
7. iPhone `Watch` tab：connection diagnostics、latest epoch、sync request、Watch event/epoch CSV export。
8. iPhone export 去重，避免同一 epoch 同时通过 `sendMessage` 和 `transferUserInfo` 到达后重复写出。
9. Motion-first baseline `SleepRuleEngine`。

仍未完成：

1. App 内一键生成 Watch prediction vs Apple Health sleepAnalysis comparison report。
2. 真正 smart alarm 唤醒、fallback latest wake time、AlarmKit/本地通知/震动策略。
3. 开源 sleep classifier / Core ML 模型集成。
4. 长期后台/extended runtime 合规产品化设计。
5. App Store 级产品 UI、云同步、账号、隐私政策。

---

## 0. 当前状况总结

### 0.1 已完成的 Phase 1 实验结论

用户已经在真机上完成一整晚测试，结论如下：

1. iOS App 可以读取 HealthKit 的 `sleepAnalysis` 数据。
2. `HKObserverQuery` / `HKAnchoredObjectQuery` 可以在 HealthKit store 出现新 sleep samples 时检测到更新。
3. 但是 Apple Watch / Apple Health 并不会在睡眠过程中实时把睡眠阶段写入 HealthKit。
4. 用户醒来后，在进入 Apple Health App 之前，手动点击本 App 的 refresh 也读不到新的睡眠数据。
5. 用户打开 Apple Health App 查看睡眠后，sleepAnalysis 数据才出现；随后本 App 的 observer 自动检测到 HealthKit 更新。
6. 因此，HealthKit sleepAnalysis 不能作为“睡满 7 小时后立刻叫醒”的实时数据源。

### 0.2 已判定不可行或不应继续投入的路线

不要继续做以下方向：

1. 不要尝试通过更频繁的 `HKSampleQuery` / `HKAnchoredObjectQuery` 来实现实时睡眠识别。
2. 不要假设 HealthKit sleepAnalysis 会在夜间持续更新。
3. 不要尝试调用 Apple 官方睡眠阶段实时 API，因为公开 API 中没有 `getCurrentSleepStage()` / `isUserAsleepNow()` 这类接口。
4. 不要尝试伪装成 Health App、调用私有 URL scheme、模拟点击 Health App、调用 private framework 或任何非公开 API。
5. 不要把核心产品逻辑建立在“用户打开 Health App 后刷新数据”上，因为用户睡着时无法执行这个操作，而且这不是可上架、可维护的产品路线。

### 0.3 新路线

新的产品技术路线是：

```text
Apple Watch 端实时采集公开可用传感器数据
→ Apple Watch 端自己判断 awake / asleep
→ Apple Watch 端累计 estimatedSleepSeconds
→ 达到目标睡眠时长后在 Watch 端震动/提醒
→ iPhone 端负责设置、可视化、日志导出、第二天对比 HealthKit 官方睡眠结果
```

HealthKit 现在只用于：

```text
1. 第二天读取 Apple 官方 sleepAnalysis
2. 和我们自己的 estimatedSleepSeconds / sleep onset / wake segments 做对比
3. 作为算法校准与评估参考
4. 生成日报与用户报告
```

HealthKit 不用于：

```text
1. 实时判断用户是否睡着
2. 实时判断 REM / Core / Deep
3. 触发“睡满后叫醒”
```

---

## 1. 项目当前总目标

项目名建议：`SleepKitProbe` 或 `SleepEnoughProbe`。

长期产品目标：

> 做一个 Apple Watch + iPhone App：用户设定“真实睡眠目标”，例如 7 小时；Apple Watch 自己检测用户是否睡着并累计有效睡眠时长；睡够后再叫醒，同时保留最晚起床时间作为安全兜底。

当前开发目标：

> 实现 Phase 2：Watch-side Sensor Probe。验证 Apple Watch 是否能稳定整晚采集运动和心率数据，并用简单规则估算 asleep / awake。

---

## 2. 重要技术判断

### 2.1 Apple Watch 传感器可用性

Codex 需要实现并验证以下公开能力：

1. 使用 Core Motion / `CMMotionManager` 在 watchOS 端采集手腕运动数据。
2. 使用 HealthKit 读取心率。当前默认实现是每个 epoch 被动查询 watchOS 已保存的 HR samples；`HKWorkoutSession` + `HKLiveWorkoutBuilder` 只作为实验路径保留，不默认启用。
3. 使用 `WKExtendedRuntimeSession`，尤其关注 smart alarm 适用场景，支持一段时间内监测心率和运动，并在合适时间发出提醒。
4. 使用 WatchConnectivity 在 Watch 与 iPhone 之间同步低频 summary 数据。

### 2.2 算法部署位置

最终产品核心算法必须放在 Apple Watch 上，而不是 iPhone 上。

原因：

```text
1. 闹钟/唤醒功能不能依赖 Watch → iPhone 的实时通信。
2. 夜间蓝牙/Wi-Fi/系统后台状态可能不稳定。
3. iPhone 可能不在身边、低电量、被系统挂起。
4. Watch 端本地判断最可靠，也最符合“戴表睡觉 → 表震动叫醒”的使用体验。
```

iPhone 的职责：

```text
1. 设置目标睡眠时长
2. 设置最晚起床时间
3. 显示 Watch 传来的 summary
4. 导出 CSV 日志
5. 第二天读取 HealthKit sleepAnalysis
6. 对比 Apple 官方睡眠结果与我们的估计
7. 用于算法调参和可视化
```

### 2.3 当前算法目标只做二分类

当前不要做完整睡眠分期。不要做 REM / Core / Deep / Light / Awake 五分类。

Phase 2 只做：

```text
awake / asleep
```

产品核心只需要知道：

```text
1. 用户是否真的睡着
2. 累计有效睡眠时间是多少
3. 什么时候达到目标睡眠时长
```

---

## 3. 参考开源项目与许可证要求

### 3.1 推荐参考：ojwalch/sleep_accel

用途：Apple Watch 采集加速度和连续心率的 Swift 项目参考。

要求：

1. 可以参考其采集架构和数据格式。
2. 注意不要盲目复制旧代码；需要适配当前 Xcode / SwiftUI / watchOS 项目结构。
3. 检查仓库 MIT License。
4. 如果复制代码片段，需要保留许可证声明。

### 3.2 推荐参考：ojwalch/sleep_classifiers

用途：Apple Watch acceleration + PPG-derived heart rate 的 sleep classifier 算法参考。

要求：

1. 优先参考其特征设计与分类思路。
2. Phase 2 先不急着移植完整模型。
3. 先实现简单规则 baseline，再考虑 Logistic Regression / Random Forest / Core ML。
4. 检查仓库 MIT License。
5. 如果复制代码或模型权重，需要保留许可证声明。

### 3.3 可参考但不能直接商用：OxWearables/asleep

用途：学习 wrist accelerometer sleep staging 的现代算法思路。

限制：

1. 其许可证偏学术使用，不能直接集成进商业闭源 App。
2. 除非之后获得商业授权，否则不要复制其代码或模型权重。
3. 只能作为算法思路参考。

### 3.4 谨慎参考：GPL 项目

如果遇到 GPL-3.0 项目，例如 pyActigraphy，不能直接复制进闭源商业 App。

要求：

```text
不要把 GPL 代码合入本项目。
可以阅读论文/文档理解算法思想，但要自己重新实现，且记录来源。
```

---

## 4. Phase 2：Watch-side Sensor Probe

### 4.1 Phase 2 核心目标

实现一个 watchOS + iOS companion app，验证以下问题：

1. Watch 能否整晚稳定运行 session？
2. Watch 能否整晚采集加速度/运动特征？
3. Watch 能否周期性采集心率？
4. 电量消耗是否可接受？
5. 简单规则模型能否粗略估计 sleep onset / awake periods？
6. 第二天能否和 HealthKit 官方 sleepAnalysis 对齐比较？

### 4.2 Phase 2 不做的事情

不要做：

1. 不要做正式产品 UI。
2. 不要做付费、登录、云同步。
3. 不要做完整睡眠分期。
4. 不要做 App Store 上架准备。
5. 不要做 AlarmKit 复杂闹钟逻辑。
6. 不要依赖 HealthKit sleepAnalysis 实时触发。
7. 不要使用私有 API。

---

## 5. 推荐项目结构

如果当前项目已经存在 iOS App，请在现有项目中添加 Watch App target，而不是重建整个项目。

建议结构：

```text
SleepKitProbe/
  SleepKitProbe.xcodeproj
  iOSApp/
    SleepKitProbeApp.swift
    ContentView.swift
    HealthKitSleepStore.swift
    WatchConnectivityManager.swift
    LogExportView.swift
    Models/
      SleepEpoch.swift
      WatchSessionSummary.swift
      HealthKitSleepSample.swift
  WatchApp/
    SleepWatchProbeApp.swift
    WatchContentView.swift
    WatchSessionManager.swift
    MotionSampler.swift
    HeartRateSampler.swift
    SleepRuleEngine.swift
    WatchConnectivitySender.swift
    WatchLocalLogStore.swift
    Models/
      WatchEpoch.swift
      SleepState.swift
      SensorAvailability.swift
  Shared/
    EpochSummary.swift
    CSVEncoder.swift
    Constants.swift
  Docs/
    phase1_healthkit_findings.md
    phase2_watch_probe_protocol.md
    sensor_permissions.md
    license_notes.md
```

如果 Xcode 默认生成不同目录，也可以保留默认结构，但必须保证代码职责清楚。

---

## 6. Watch 端功能要求

### 6.1 Watch UI

实现一个最简单的 watchOS UI：

```text
Title: Sleep Watch Probe
Status: Idle / Running / Stopped / Error
Current State: Unknown / Awake / Asleep
Estimated Sleep: HH:mm:ss
Current HR: -- or bpm
Motion Score: numeric
Battery: %

Buttons:
- Start Session
- Stop Session
- Mark Awake
- Mark Asleep Manually
- Export/Sync Now
```

说明：

1. `Mark Awake` 和 `Mark Asleep Manually` 用于调试标注，不是正式产品功能。
2. Watch 屏幕小，UI 简洁即可。
3. 所有关键事件必须写入日志。

### 6.2 Session 生命周期

实现 `WatchSessionManager`：

```text
startSession(goalSeconds, maxEndTime?)
stopSession(reason)
pauseSession(reason)
resumeSession()
```

Session 状态：

```swift
enum ProbeSessionState {
    case idle
    case starting
    case running
    case stopping
    case stopped
    case failed(String)
}
```

必须记录事件：

```text
session_started
session_stopped
motion_started
motion_stopped
heart_rate_started
heart_rate_stopped
extended_runtime_started
extended_runtime_invalidated
connectivity_sent
connectivity_failed
manual_awake_mark
manual_asleep_mark
```

### 6.3 Core Motion 采集

实现 `MotionSampler`。

最低要求：

1. 使用 `CMMotionManager`。
2. 支持配置采样频率，例如 10 Hz 或更低。
3. 不要长期保存全部原始高频数据作为默认行为。
4. 每 30 秒或 60 秒聚合成一个 epoch。

每个 epoch 至少计算：

```text
epochStart
epochEnd
sampleCount
accelMeanX
accelMeanY
accelMeanZ
accelStdX
accelStdY
accelStdZ
accelMagnitudeMean
accelMagnitudeStd
motionScore
motionBurstCount
isMotionDataAvailable
```

`motionScore` 第一版可以定义为：

```text
mean(abs(|accel|-1g)) 或 accelMagnitudeStd
```

请在代码注释中明确当前定义。

### 6.4 心率采集

实现 `HeartRateSampler`。

Phase 2 已经实现两种路径中的低功耗默认路径：

1. 默认：HealthKit `HKSampleQuery` 按 epoch 时间窗读取已存在的 heart-rate samples。
2. 保留实验代码：`HKWorkoutSession` + `HKLiveWorkoutBuilder`，可用于对比 workout-level HR 采集，但默认不接入 session。

最低要求：

```text
1. 请求 HealthKit 心率读取权限。
2. 尝试在 session 中周期性获取 heart rate。
3. 每个 epoch 记录 meanHR / latestHR / hrSampleCount。
4. 如果心率不可用，不要崩溃；记录 heartRateAvailable=false。
```

注意：

```text
默认 passive HR 不会强制 Apple Watch 每分钟测心率，因此 `heartRateAvailable=false` 是预期数据质量信号，不是崩溃或逻辑错误。

`HKWorkoutSession` 可能影响 Activity Rings 并显著增加耗电。后续如果重新接入 workout live HR，必须在 README 中明确标注，并单独记录电量对比。
```

### 6.5 Extended Runtime Session

实现或预留 `WKExtendedRuntimeSession` 支持。

要求：

1. 尝试使用适合 smart alarm 的 extended runtime session 配置。
2. 记录 session 是否成功启动。
3. 记录 invalidation reason。
4. 如果 extended runtime 不可用，App 仍然可以在前台运行采集调试。

不要硬编码任何私有 entitlement。

### 6.6 Watch 本地日志

Watch 必须本地保存日志，不能只依赖实时传给 iPhone。

原因：

```text
夜间 Watch → iPhone 通信可能中断。
本地日志是最终实验数据的可靠来源。
```

本地日志格式建议 JSONL 或 CSV。

每个 epoch 一行：

```text
sessionId
epochIndex
epochStart
epochEnd
watchTimestamp
motionScore
accelMagnitudeMean
accelMagnitudeStd
motionBurstCount
heartRateMean
heartRateLatest
heartRateSampleCount
heartRateAvailable
batteryLevel
isCharging
predictedState
asleepProbability
estimatedSleepSeconds
algorithmVersion
notes
```

---

## 7. Sleep/Wake 规则模型要求

实现 `SleepRuleEngine`。

### 7.1 第一版目标

第一版只做可解释规则，不要上复杂模型。

输入：

```text
motionScore
motionBurstCount
heartRateLatest / heartRateMean
heartRateBaseline
minutesSinceSessionStart
manualOverride(optional)
previousState
```

输出：

```text
predictedState: unknown / awake / asleep / restless
asleepProbability: 0.0 - 1.0
estimatedSleepSeconds cumulative
reason string
```

### 7.2 建议初始规则

可以先实现以下非常简单的规则：

```text
1. Session 开始后前 10 分钟设为 settling period，不直接判定 asleep。
2. 如果连续 N 个 epoch motionScore 低于阈值，且无 motion burst，则 asleepProbability 上升。
3. 如果心率相对 session 初期 baseline 下降，asleepProbability 上升。
4. 如果 motionScore 明显升高或出现 burst，则判定 awake/restless。
5. 只有 predictedState == asleep 的 epoch 才累计 estimatedSleepSeconds。
6. restless 是否累计睡眠，先提供配置项：countRestlessAsSleep true/false。
```

默认配置：

```text
epochSeconds = 60
settlingMinutes = 10
lowMotionConsecutiveEpochsForSleep = 10
highMotionEpochsForAwake = 2
countRestlessAsSleep = false
```

### 7.3 所有阈值必须可配置

不要把阈值散落在代码中。

集中到：

```swift
struct SleepRuleConfig { ... }
```

并在 iPhone App 或 debug panel 中能看到当前配置。

---

## 8. WatchConnectivity 要求

实现 Watch → iPhone 的低频 summary 同步。

不要传整晚原始高频加速度。

传输策略：

```text
1. 每个 epoch 生成后尝试发送一条 summary。
2. 如果 iPhone reachable，可用 sendMessage 做实时显示。
3. 同时使用 transferUserInfo 或 transferFile 保证最终送达。
4. iPhone 收到后保存到本地数据库/文件。
5. 如果同步失败，Watch 本地日志仍然保留。
```

数据结构：

```swift
struct EpochSummary: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let epochIndex: Int
    let startDate: Date
    let endDate: Date
    let motionScore: Double
    let accelMagnitudeMean: Double?
    let accelMagnitudeStd: Double?
    let heartRateMean: Double?
    let heartRateLatest: Double?
    let heartRateSampleCount: Int
    let heartRateAvailable: Bool
    let batteryLevel: Double?
    let predictedState: SleepState
    let asleepProbability: Double
    let estimatedSleepSeconds: TimeInterval
    let algorithmVersion: String
}
```

---

## 9. iPhone 端功能要求

### 9.1 iPhone UI

实现一个简单调试 UI：

```text
SleepEnough Probe

Watch Connection: Connected / Not Connected
Current Watch Session: Running / Not Running
Estimated Sleep: HH:mm:ss
Current State: Awake / Asleep / Unknown
Last Epoch Received: timestamp
Heart Rate: bpm or --
Motion Score: number
Watch Battery: %

Buttons:
- Send Goal to Watch
- Request Watch Sync
- Export Epoch CSV
- Export Watch Event CSV
- Clear iPhone Watch Logs
```

HealthKit refresh/export 仍在 Phase 1 tabs 中；`Compare With Apple Sleep` 是后续计划，当前未实现为按钮。

### 9.2 设置下发

iPhone 可以设置：

```text
sleepGoalHours
maxWakeTime
settlingMinutes
epochSeconds
countRestlessAsSleep
motionThreshold
heartRateDropThreshold
```

通过 WatchConnectivity 发给 Watch。

### 9.3 日志导出

iPhone 当前支持导出：

1. Watch epoch CSV
2. Watch event log CSV
3. HealthKit sleepAnalysis CSV

后续计划导出：

4. Comparison report JSON 或 CSV

导出字段必须足够完整，方便后续 Python 分析。

### 9.4 HealthKit 事后对比

保留并改造 Phase 1 的 HealthKit 读取代码。

当前状态：Phase 1 的 HealthKit 读取和导出已保留，App 内自动 comparison report 尚未实现。现阶段先手动对比 `watch_epoch_summaries.csv` 和 `sleep_samples.csv`。

后续新增比较功能：

```text
1. 读取指定日期区间的 sleepAnalysis。
2. 汇总 Apple 官方 asleep duration。
3. 计算 Apple sleep onset time。
4. 计算 Apple wake time。
5. 和我们 Watch-side prediction 比较：
   - sleep onset difference minutes
   - total sleep duration difference minutes
   - awake/restless overlap
   - estimated sleep seconds vs Apple asleep seconds
```

注意：

```text
不要再把 HealthKit 作为实时触发器。
所有 HealthKit 读取都标记为 post-hoc evaluation。
```

---

## 10. Phase 2 验收标准

当前代码已经支持以下测试；其中 app 内 comparison report 仍是后续计划。

### 10.1 白天短测

步骤：

```text
1. 在 iPhone 和 Watch 上安装 App。
2. Watch 点击 Start Session。
3. 手腕静止 5 分钟。
4. 手腕运动 1 分钟。
5. 停止 Session。
6. iPhone 导出 CSV。
```

通过标准：

```text
1. CSV 中有连续 epoch。
2. 静止期间 motionScore 低。
3. 运动期间 motionScore 明显升高。
4. App 不崩溃。
5. Watch 能同步 summary 给 iPhone。
```

### 10.2 夜间测试

步骤：

```text
1. 睡前 Watch 点击 Start Session。
2. iPhone 放床边但不依赖前台运行。
3. 正常睡觉。
4. 醒来后 Watch 点击 Stop Session。
5. iPhone 请求同步并导出 CSV。
6. 打开 Health App，让 Apple 官方 sleepAnalysis 出现。
7. 回到本 App，使用 Phase 1 refresh/export 导出 `sleep_samples.csv`。
8. 手动对比 `watch_epoch_summaries.csv` 和 `sleep_samples.csv`。
```

通过标准：

```text
1. Watch 没有整晚崩溃。
2. 日志至少覆盖大部分睡眠时段。
3. motion 数据连续或缺失段有明确记录。
4. heart rate 可用性被正确记录。
5. estimatedSleepSeconds 可以输出。
6. Watch epoch/event CSV 和 HealthKit sleep sample CSV 可以导出。
7. 电量消耗被记录。
```

---

## 11. 安全与可靠性要求

### 11.1 不要把 Probe 当成正式闹钟

Phase 2 期间必须在 UI 和 README 中明确：

```text
This is a research probe, not a reliable alarm.
Do not rely on it as your only wake-up alarm.
```

中文：

```text
这是实验性采集工具，不是可靠闹钟。测试期间请另设系统闹钟作为保底。
```

### 11.2 必须保留保底概念

即使 Phase 2 暂不实现正式 AlarmKit，也要在架构中保留：

```text
sleepGoalSeconds
latestWakeTime
fallbackAlarmTime
```

后续产品化阶段必须实现：

```text
睡够后叫醒 + 最晚时间兜底
```

### 11.3 隐私要求

健康数据和睡眠日志默认只保存在本地。

不要上传服务器。

如果未来需要云同步，必须另行设计隐私政策和用户授权。

---

## 12. 开发顺序与当前状态

下列步骤已经不再是全新的待办清单；保留它们是为了说明 Phase 2 的实现路径和剩余缺口。

### Step 1：整理现有 Phase 1 文档 — 已完成

创建或更新：

```text
Docs/phase1_healthkit_findings.md
```

内容包括：

```text
1. 用户实验结果
2. HealthKit sleepAnalysis 非实时结论
3. 为什么不继续使用 HealthKit 做实时触发
4. HealthKit 在后续作为 post-hoc evaluation 的角色
```

### Step 2：添加 Watch App target — 已完成

在现有 Xcode project 中添加 watchOS App target。

确保：

```text
1. iOS App 可以安装到 iPhone。
2. Watch App 可以安装到 paired Apple Watch。
3. Bundle IDs 合理且唯一。
4. Signing & Capabilities 设置正确。
```

### Step 3：实现 Watch UI + SessionManager skeleton — 已完成

先让 Watch App 能：

```text
1. 启动
2. 显示状态
3. Start / Stop Session
4. 写本地 event log
```

### Step 4：实现 MotionSampler — 已完成

先只采集运动，不做心率。

完成白天短测：静止 vs 运动 motionScore 是否明显不同。

### Step 5：实现 epoch 聚合与本地日志 — 已完成

每 60 秒输出 `WatchEpoch`。

本地保存 JSONL/CSV。

### Step 6：实现 WatchConnectivity summary 同步 — 已完成

iPhone 能看到 Watch 发来的 epoch。

### Step 7：实现简单 SleepRuleEngine — 已完成

先用 motion-only 规则判断 asleep/awake。

### Step 8：实现 HeartRateSampler — 已完成默认 passive HR，保留 workout 实验路径

加入 HealthKit 权限、心率采集和 heart rate epoch 聚合。

### Step 9：实现 post-hoc HealthKit comparison — 部分完成

复用 Phase 1 的 HealthKit sleepAnalysis 读取。

已能导出 HealthKit sleep samples；App 内自动 comparison report 尚未实现。

### Step 10：写 README 和测试协议 — 已完成并持续更新

更新 README：

```text
1. 如何安装到 iPhone + Apple Watch
2. 需要哪些权限
3. 如何做白天短测
4. 如何做夜间测试
5. 如何导出 CSV
6. 如何解释结果
7. 已知限制
```

---

## 13. 权限与 Capability 检查清单

iOS target：

```text
HealthKit
WatchConnectivity
Background Modes（如需要；先谨慎添加）
```

watchOS target：

```text
HealthKit
WatchConnectivity
Motion Usage Description（如果需要）
```

默认 passive HR 不需要 Workout Processing。只有重新启用 `HKWorkoutSession` 实验路径时，才重新评估 Workout Processing / Background Modes capability。

Info.plist 文案建议：

```text
NSHealthShareUsageDescription:
This app reads sleep and heart rate data to evaluate sleep detection accuracy.

NSHealthUpdateUsageDescription:
Only needed if the experimental workout HR path is re-enabled. The default passive HR path does not write workouts.

NSMotionUsageDescription:
This app uses Apple Watch motion data to estimate sleep and wake periods during user-started sessions.
```

如果某些 key 不适用于 watchOS target，请根据 Xcode 提示调整，不要硬塞无效 key。

---

## 14. 代码质量要求

1. SwiftUI 优先。
2. 使用 MVVM 或清晰 service 层结构。
3. 所有 manager 类要有明确职责。
4. 所有长时间运行 session 必须可停止。
5. 所有传感器采集失败必须有错误状态，不允许静默失败。
6. 所有日志写入必须容错，不要因为文件写入失败导致 session 崩溃。
7. 不要引入第三方依赖，除非明确必要。
8. 不要上传数据到网络。
9. 不要使用私有 API。
10. 不要把本实验 App 宣称为医疗设备或诊断工具。

---

## 15. 后续 Phase 3 预留

Phase 2 完成后，如果数据质量可接受，再进入 Phase 3：

```text
1. 用多晚个人数据调规则阈值。
2. 引入 ojwalch/sleep_classifiers 风格特征。
3. 训练 Logistic Regression / Random Forest / small MLP。
4. 转成 Core ML，在 Watch 端本地推理。
5. 增加真正的 smart alarm window。
6. 增加 fallback latest wake time。
7. 做 battery optimization。
8. 做 App Store 合规检查。
```

Phase 3 之前不要过早优化 UI 或商业化功能。

---

## 16. 当前最重要的单一目标

Codex 当前最重要任务：

> 让 Apple Watch 能在用户主动点击 Start Session 后，稳定记录一整晚的 motion epoch + heart rate availability + estimated sleep/wake state，并同步/导出到 iPhone，与第二天 Apple Health sleepAnalysis 做对比。

不要被其他需求分散注意力。
