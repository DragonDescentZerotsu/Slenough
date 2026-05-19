# AGENTS.md — SleepKit Probe / Apple Watch 真实睡眠时长唤醒项目

## 当前状态：Phase 2 Watch-side Sensor Probe

截至当前分支 `custom-asleep`，项目已经从 Phase 1 的 HealthKit `sleepAnalysis` 实时性验证，进入 Phase 2 的 Apple Watch 端自研 awake/asleep 采集验证。

Phase 1 真机结论：

1. iOS App 可以读取 HealthKit `sleepAnalysis`。
2. `HKObserverQuery` / `HKAnchoredObjectQuery` 可以在 HealthKit store 出现新 sleep samples 后检测更新。
3. Apple Watch / Apple Health 不会在睡眠过程中可靠实时写入官方睡眠阶段。
4. 用户醒来后，打开 Apple Health 之前，本 App 手动 refresh 也可能读不到新 sleep samples。
5. HealthKit `sleepAnalysis` 后续只用于 post-hoc evaluation，不再作为实时触发源。

Phase 2 当前目标：

> Watch 端在用户主动点击 `Start Session` 后，记录 motion epoch、heart-rate availability、estimated awake/asleep state，并通过 WatchConnectivity 同步低频 summary 到 iPhone，第二天再和 Apple Health 官方 sleepAnalysis 做对比。

Phase 2 仍然不是正式闹钟。UI 和 README 必须持续提示：这是实验性采集工具，不是可靠闹钟，测试时必须另设系统闹钟作为保底。

### 当前完成进度

已完成：

1. Watch target / scheme，iPhone app 嵌入安装 Watch app。
2. Watch 端 `Start Session` / `Stop Session`、manual awake/asleep 标注、本地日志。
3. 默认 60 秒 epoch、`motionSampleHz = 1`。
4. 默认 passive HR：每个 epoch 查询该分钟内 watchOS 已保存的 heart-rate samples，不启动 workout live HR。
5. Baseline `SleepRuleEngine` 输出 `predictedState`、`asleepProbability`、`estimatedSleepSeconds`。
6. WatchConnectivity summary sync，含 queued delivery fallback。
7. iPhone `Watch` tab，包含 connection diagnostics、latest epoch、sync request、epoch/event CSV export。
8. iPhone export 去重，避免 `sendMessage` 和 `transferUserInfo` 双路径导致重复 epoch。

仍未完成：

1. App 内自动生成 Watch prediction vs Apple Health sleepAnalysis comparison report。
2. 真正 smart alarm 唤醒、fallback latest wake time、AlarmKit/本地通知/震动策略。
3. 开源 sleep model / Core ML 集成。
4. 产品化后台运行、电量优化和 App Store 合规设计。

---

## Phase 2 当前代码入口速查

### Xcode Targets / Schemes

```text
SleepKitProbe.xcodeproj
  Targets:
    SleepKitProbe              iOS app
    SleepKitProbe Watch App    watchOS app
    SleepKitProbeTests         iOS unit tests

  Shared schemes:
    SleepKitProbe
    SleepKitProbe Watch App
```

- `SleepKitProbe` scheme：运行 iPhone app，并嵌入安装 Watch app。真机测试时选择 paired iPhone + Apple Watch。
- `SleepKitProbe Watch App` scheme：单独运行或 preview Watch UI。查看 Watch UI preview 时打开 `WatchApp/WatchContentView.swift`，选择 Apple Watch simulator destination。

### Watch App

```text
WatchApp/
  SleepWatchProbeApp.swift
  WatchContentView.swift
  WatchSessionManager.swift
  MotionSampler.swift
  HeartRateSampler.swift
  WatchConnectivitySender.swift
  WatchLocalLogStore.swift
  WatchApp.entitlements
```

- `SleepWatchProbeApp.swift`：Watch SwiftUI App 入口。
- `WatchContentView.swift`：Watch 端极简测试 UI。显示 status、current state、estimated sleep、heart rate、motion score、battery，并提供 `Start Session` / `Stop Session` / `Mark Awake` / `Mark Asleep` / `Export/Sync Now`。
- `WatchSessionManager.swift`：Watch 端核心 session 管理。负责 session 生命周期、extended runtime、motion sampler、heart-rate sampler、rule engine、epoch 生成、本地日志和 WatchConnectivity 发送。
- `MotionSampler.swift`：使用 `CMMotionManager` 采集加速度，每个 epoch 聚合 mean/std/magnitude/motionScore/motionBurstCount。当前 `motionScore = accelMagnitudeStd`。
- `HeartRateSampler.swift`：默认使用 HealthKit read authorization，并在每个 epoch 结束时被动查询该分钟内 watchOS 已保存的 heart-rate samples。它不会强制光学心率传感器每分钟测量一次；不可用时不崩溃，epoch 中记录 `heartRateAvailable=false`。文件中仍保留 `HKWorkoutSession` + `HKLiveWorkoutBuilder` 实验路径，后续如需对比 workout 级 HR 可重新接入。
- `WatchConnectivitySender.swift`：Watch -> iPhone 低频 summary 同步。实时 reachable 时用 `sendMessage`，同时用 `transferUserInfo` 保底。
- `WatchLocalLogStore.swift`：Watch 本地 JSONL 日志。不能只依赖 iPhone 实时同步。
- `WatchApp.entitlements`：Watch HealthKit entitlement。

### Shared Phase 2 Logic

```text
Shared/
  Phase2Models.swift
  SleepRuleEngine.swift
  Phase2CSVEncoder.swift
```

- `Phase2Models.swift`：`SleepState`、`ProbeSessionState`、`SleepRuleConfig`、`EpochSummary`、`WatchEpoch`、`WatchEventRecord` 等共享模型。
- `SleepRuleEngine.swift`：第一版可解释 motion-first 规则模型。默认 settling 10 分钟，连续低 motion 才判定 asleep，高 motion/burst 判定 awake/restless。只累计 `predictedState == asleep` 的 epoch。
- `Phase2CSVEncoder.swift`：导出 Watch epoch summary 和 Watch event CSV。

### iPhone Phase 2 UI / Sync

```text
SleepKitProbe/
  ContentView.swift
  Views/
    WatchProbeView.swift
  WatchSync/
    PhoneWatchConnectivityManager.swift
    WatchEpochStore.swift
```

- `ContentView.swift`：主 TabView 现在包含 `Dashboard` / `Samples` / `Logs` / `Watch` / `Export`。
- `WatchProbeView.swift`：iPhone 端 Watch 调试页。显示 connection、latest epoch、estimated sleep、state、heart rate、motion score、battery、epoch count，并支持 `Send Goal to Watch`、`Request Watch Sync`、`Export Epoch CSV`、`Export Watch Event CSV`。
- `PhoneWatchConnectivityManager.swift`：iPhone 端 WatchConnectivity 接收与配置下发。
- `WatchEpochStore.swift`：iPhone 本地保存收到的 `EpochSummary` / `WatchEventRecord`，并导出 `watch_epoch_summaries.csv` / `watch_events.csv`。

### Phase 1 保留用途

```text
SleepKitProbe/HealthKit/
SleepKitProbe/Logging/
SleepKitProbe/Models/
```

Phase 1 的 HealthKit sleepAnalysis 读取、observer、anchored query、CSV/JSONL 导出仍保留，但语义已经变为：

- 不再用于实时叫醒触发。
- 第二天读取 Apple 官方 sleepAnalysis。
- 与 Watch-side estimated sleep/wake 结果做 post-hoc comparison。
- 继续导出 `sleep_samples.csv` / `observer_events.csv` / `sleepkit_probe_log.jsonl`。

### Phase 2 文档

```text
README.md
README_PHASE1.md
README_PHASE2.md
Docs/
  phase1_healthkit_findings.md
  phase2_watch_probe_protocol.md
  sensor_permissions.md
  license_notes.md
```

- `README.md`：项目入口，说明当前 Phase 2 怎么安装、preview、白天短测、夜间测试。
- `README_PHASE2.md`：Phase 2 详细使用说明。
- `Docs/phase1_healthkit_findings.md`：Phase 1 实验结论和 HealthKit 非实时判断。
- `Docs/phase2_watch_probe_protocol.md`：白天短测和夜间测试协议。
- `Docs/sensor_permissions.md`：iOS / Watch 权限说明。
- `Docs/license_notes.md`：外部算法参考和许可证注意事项。

### Phase 2 Tests

```text
SleepKitProbeTests/
  SleepRuleEngineTests.swift
  Phase2CSVEncoderTests.swift
```

- `SleepRuleEngineTests.swift`：验证 settling period、连续低 motion、high motion wake、manual override。
- `Phase2CSVEncoderTests.swift`：验证 Watch epoch/event CSV header、日期、数值和 escaping。

### 当前验证命令

```bash
xcodebuild build \
  -project SleepKitProbe.xcodeproj \
  -scheme SleepKitProbe \
  -destination generic/platform=iOS \
  -derivedDataPath /tmp/SleepKitProbeDerivedData \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project SleepKitProbe.xcodeproj \
  -scheme "SleepKitProbe Watch App" \
  -destination generic/platform=watchOS \
  -derivedDataPath /tmp/SleepKitProbeDerivedData \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build-for-testing \
  -project SleepKitProbe.xcodeproj \
  -scheme SleepKitProbe \
  -destination generic/platform=iOS \
  -derivedDataPath /tmp/SleepKitProbeDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

注意：Codex 当前环境可能没有可用 CoreSimulatorService，因此真跑 simulator tests / previews 可能需要用户在本机 Xcode 中执行。

---

## Archived Phase 1 Original Spec

以下内容是 Phase 1 原始实现说明，保留用于历史背景和维护 Phase 1 HealthKit 读取/导出功能。当前开发入口以上面的 Phase 2 状态、`README.md`、`README_PHASE2.md` 和 `AGENTS_v2.md` 为准；不要把本节中的 “Phase 2/3 暂不实现” 视为当前状态。

## 0. 项目背景

我们要验证并逐步实现一个 iPhone + Apple Watch 场景下的“睡够再叫”闹钟产品：用户不是设置固定起床时间，而是设置“真实睡眠累计目标”，例如真实睡满 7 小时后再唤醒。

当前最重要的不确定性不是 UI，而是：

1. Apple Watch 原生写入 HealthKit 的 `sleepAnalysis` 睡眠数据是否会在用户睡眠过程中近实时更新；
2. 第三方 iOS App 是否能通过 HealthKit 后台监听及时拿到这些数据；
3. 如果 HealthKit 不够实时，后续是否必须开发 watchOS 端自研 awake/asleep 检测算法。

因此本项目先只做 **Phase 1：HealthKit 睡眠数据实时性验证工具**，不要一开始做完整闹钟产品。

---

## 1. 公开 API 事实依据

实现前请以 Apple 官方文档为准，尤其是：

- HealthKit 的睡眠数据类型是 `HKCategoryTypeIdentifier.sleepAnalysis` / `HKCategoryTypeIdentifierSleepAnalysis`。
- Apple Watch / App 保存的睡眠数据在 HealthKit 中表示为 `sleepAnalysis` category samples。
- HealthKit 睡眠阶段包括 `awake`、`asleepCore`、`asleepDeep`、`asleepREM`、`asleepUnspecified` 等。
- HealthKit 需要用户显式授权，每种健康数据类型需要单独授权。
- `HKObserverQuery` 可用于观察 HealthKit store 的变化；`HKAnchoredObjectQuery` 可用于增量读取自上次 anchor 后新增或删除的 samples。
- 不要假设 Apple 提供了公开 API 可以实时调用“Apple Watch 官方睡眠识别模型”。目前 Phase 1 只验证 HealthKit 样本更新时间，不调用不存在的 `getCurrentSleepStage()` 类接口。

参考链接：

- https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/sleepanalysis
- https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis
- https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- https://developer.apple.com/documentation/healthkit/protecting-user-privacy
- https://developer.apple.com/documentation/healthkit/hkobserverquery
- https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery
- https://developer.apple.com/videos/play/wwdc2022/10005/

---

## 2. Phase 1 总目标：SleepKit Probe

请实现一个极简 iOS App，暂名：`SleepKitProbe`。

它的唯一目标是：

> 验证 Apple Watch / Apple Health 的 `sleepAnalysis` 数据是否会在夜间睡眠过程中持续写入，并记录 App 实际收到更新的时间。

Phase 1 完成后，我们要能回答：

1. 睡眠样本是在夜间陆续写入，还是醒来后一次性写入？
2. `HKObserverQuery` 是否会在锁屏 / 夜间 / 后台状态下触发？
3. 触发后 `HKAnchoredObjectQuery` 是否能读到新增 sleep samples？
4. `sample.startDate` / `sample.endDate` 与 `receivedAt` 之间的延迟大概是多少？
5. 如果数据延迟过大，是否需要 Phase 2/3 自研 watchOS 端睡眠识别？

---

## 3. Phase 1 严格范围

### 必须做

- iOS SwiftUI App。
- HealthKit 授权。
- 读取 `sleepAnalysis` 历史样本。
- 使用 `HKObserverQuery` 监听 `sleepAnalysis` 更新。
- 使用 `HKAnchoredObjectQuery` 做增量读取。
- 本地记录每次 observer 触发和每条样本的接收时间。
- 导出 CSV / JSONL 日志。
- 提供一个简单 UI 显示授权状态、监听状态、最近样本、日志条数、导出按钮。
- 写一个 `README_PHASE1.md`，说明如何在真机 + Apple Watch 上跑一晚实验。

### 不要做

- 不要做完整闹钟产品。
- 不要做付费、登录、云同步。
- 不要接入第三方后端。
- 不要做复杂睡眠评分。
- 不要做 REM/deep/core 预测模型。
- 不要做自研 watchOS 睡眠识别。
- 不要调用不存在的 Apple 睡眠实时识别接口。
- 不要假设 HealthKit 数据一定实时；本阶段就是为了验证这一点。
- 不要直接控制系统 Clock App 闹钟。
- 不要在 Phase 1 引入 AlarmKit，除非项目已有最低系统版本和 SDK 已经明确支持；Phase 1 不依赖闹钟能力。

---

## 4. 推荐项目结构

如果仓库为空，请创建如下结构。若仓库已有 iOS 项目，请在不破坏原结构的基础上适配。

```text
SleepKitProbe/
  SleepKitProbe.xcodeproj 或 SleepKitProbe.xcworkspace
  SleepKitProbe/
    SleepKitProbeApp.swift
    ContentView.swift
    HealthKit/
      HealthKitManager.swift
      SleepSampleMapper.swift
      SleepObserverService.swift
      SleepAnchoredQueryService.swift
    Logging/
      ProbeLogger.swift
      ProbeLogModels.swift
      CSVExporter.swift
      JSONLExporter.swift
    Models/
      SleepSampleRecord.swift
      ObserverEventRecord.swift
      ProbeSession.swift
    Views/
      PermissionView.swift
      DashboardView.swift
      SampleListView.swift
      LogListView.swift
      ExportView.swift
    Utilities/
      DateFormatters.swift
      FileStore.swift
  SleepKitProbeTests/
    SleepSampleMapperTests.swift
    CSVExporterTests.swift
    DurationAggregationTests.swift
README_PHASE1.md
AGENTS.md
```

如果无法自动创建 Xcode project，可以先创建 Swift Package 或给出清晰说明。但优先创建可直接在 Xcode 打开的 iOS SwiftUI App。

---

## 5. 关键数据模型

### 5.1 `SleepSampleRecord`

每条 HealthKit sleep sample 转换为本地记录，建议字段：

```swift
struct SleepSampleRecord: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID?
    let sampleUUID: UUID
    let receivedAt: Date
    let queryTriggeredAt: Date?
    let sampleStartDate: Date
    let sampleEndDate: Date
    let durationSeconds: TimeInterval
    let valueRaw: Int
    let valueName: String
    let sourceName: String
    let sourceBundleIdentifier: String?
    let deviceName: String?
    let metadataDescription: String?
    let syncSource: String // manualInitialQuery / observerAnchoredQuery / manualRefresh
}
```

### 5.2 `ObserverEventRecord`

每次 observer 触发都要记录，即使没有读到新样本也要记录。

```swift
struct ObserverEventRecord: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID?
    let triggeredAt: Date
    let anchoredQueryStartedAt: Date?
    let anchoredQueryFinishedAt: Date?
    let addedSampleCount: Int
    let deletedObjectCount: Int
    let errorDescription: String?
    let appStateDescription: String?
}
```

### 5.3 `ProbeSession`

用户点击“Start Night Probe”时创建 session。

```swift
struct ProbeSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var note: String?
}
```

---

## 6. HealthKit 实现要求

### 6.1 授权

实现 `HealthKitManager`：

- 检查 `HKHealthStore.isHealthDataAvailable()`。
- 请求读取 `HKCategoryTypeIdentifier.sleepAnalysis`。
- Phase 1 只需要 read permission，不需要写入 HealthKit。
- UI 要清楚提示用户：健康数据只保存在本地，不上传。

伪代码方向：

```swift
let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
healthStore.requestAuthorization(toShare: [], read: [sleepType]) { success, error in
    // update state on main actor
}
```

### 6.2 历史查询

实现最近 24 小时 / 最近 7 天 sleep samples 查询：

- 用 `HKSampleQuery` 或新的 descriptor API 均可，但优先保持兼容和清晰。
- 按 `startDate` 升序排序。
- 显示 valueName、start、end、duration、source。

### 6.3 Observer Query

实现 `HKObserverQuery`：

- 监听 `sleepAnalysis`。
- 每次 observer callback 发生时，先记录 `ObserverEventRecord.triggeredAt`。
- 然后立即运行 anchored query。
- 必须调用 observer 的 completion handler。
- 不要在 callback 中执行过重任务。

### 6.4 Anchored Object Query

实现 `HKAnchoredObjectQuery`：

- 保存 `HKQueryAnchor` 到本地，确保 App 重启后仍能做增量读取。
- 每次读取新增 samples 和 deleted objects。
- 记录 `queryTriggeredAt`、`receivedAt`、样本内容。
- deleted objects 也要记录数量，至少在 observer event 中记录。

### 6.5 Background Delivery

尝试启用：

```swift
healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { success, error in
    // log result
}
```

注意：

- `.immediate` 不代表系统保证实时；日志里要记录是否启用成功。
- 如果模拟器不支持或真机权限不足，要在 UI 和 README 里说明。

---

## 7. UI 要求

Phase 1 UI 简单即可，但必须能帮助实验。

### Dashboard

显示：

- HealthKit 是否可用。
- Sleep Analysis 权限状态或授权提示。
- Observer 是否已启动。
- Background Delivery 是否启用成功。
- 当前 active probe session。
- 最近一次 observer 触发时间。
- 最近一次 anchored query 读取到的样本数。
- 当前本地日志文件大小 / 记录数。

按钮：

- `Request HealthKit Permission`
- `Start Observer`
- `Manual Refresh Last 24h`
- `Start Night Probe`
- `End Night Probe`
- `Export CSV`
- `Export JSONL`
- `Clear Local Logs`

### Sample List

列表展示最近 sleep samples：

- valueName
- startDate
- endDate
- duration
- sourceName
- receivedAt
- latency：`receivedAt - sampleEndDate`

### Log List

展示 observer events：

- triggeredAt
- addedSampleCount
- deletedObjectCount
- errorDescription

---

## 8. 导出文件格式

### 8.1 CSV

至少导出两个 CSV：

```text
sleep_samples.csv
observer_events.csv
```

`sleep_samples.csv` 字段：

```text
session_id,sample_uuid,received_at,query_triggered_at,sample_start,sample_end,duration_seconds,value_raw,value_name,source_name,source_bundle_identifier,device_name,sync_source,metadata_description
```

`observer_events.csv` 字段：

```text
session_id,event_id,triggered_at,anchored_query_started_at,anchored_query_finished_at,added_sample_count,deleted_object_count,error_description,app_state_description
```

### 8.2 JSONL

每行一个 JSON 对象，便于后续 Python 分析。

推荐对象类型：

```json
{"type":"sleep_sample", ...}
{"type":"observer_event", ...}
{"type":"app_event", ...}
```

---

## 9. Phase 1 实验协议，写入 README_PHASE1.md

请生成 `README_PHASE1.md`，面向完全不熟 iOS 的用户，内容包括：

### 9.1 前置条件

- Mac + Xcode。
- iPhone 真机。
- Apple Watch 已配对。
- iPhone Health App 中开启睡眠追踪。
- Apple Watch 夜间佩戴并有足够电量。
- App 已授予 HealthKit sleepAnalysis 读取权限。

### 9.2 一晚实验流程

```text
1. 睡前打开 SleepKitProbe。
2. 点击 Request HealthKit Permission。
3. 点击 Start Observer。
4. 点击 Manual Refresh Last 24h，确认能读到历史睡眠数据。
5. 点击 Start Night Probe。
6. 保持 Apple Watch 佩戴入睡。
7. 第二天醒来后打开 App。
8. 点击 Manual Refresh Last 24h。
9. 点击 Export CSV / Export JSONL。
10. 检查 observer_events.csv 和 sleep_samples.csv。
```

### 9.3 判断标准

用导出的日志判断：

#### 情况 A：HealthKit 可能足够实时

如果夜间多次出现：

```text
observer_event.triggered_at 接近 sleep_sample.sample_end
received_at 接近 sample_end
```

例如延迟在几分钟到几十分钟内，则 HealthKit-based MVP 可能可行。

#### 情况 B：HealthKit 不够实时

如果大多数样本都是醒来后、解锁后、手动刷新后才出现，例如：

```text
sample_end = 03:10
received_at = 08:40
```

说明 HealthKit 更适合复盘，不适合“睡满 7 小时立即叫醒”。后续需要做 watchOS 端自研 awake/asleep 检测。

### 9.4 注意事项

- iOS 模拟器不能验证真实 Apple Watch 睡眠数据。
- HealthKit 权限被拒绝时，App 不应崩溃。
- 锁屏状态下 HealthKit 读取行为可能受系统隐私和数据保护影响。
- 这不是医疗软件，不提供诊断。

---

## 10. 测试要求

至少写以下单元测试：

1. `SleepSampleMapperTests`
   - raw value 能正确映射为 readable name。
   - 未知 raw value 不崩溃，显示 `unknown(<raw>)`。

2. `CSVExporterTests`
   - CSV header 正确。
   - 日期格式稳定。
   - 字段里有逗号、换行、引号时能正确 escape。

3. `DurationAggregationTests`
   - 能统计 asleep-like values 的总时长。
   - `awake` 不计入有效睡眠。
   - overlapping samples 至少不要重复计算，或在 README 中明确当前策略。

4. `ProbeLoggerTests`
   - 能写入 JSONL。
   - App 重启后能读取已有日志。

如果 Xcode 项目测试暂时无法自动配置，至少把纯 Swift 逻辑写成可测试结构，并说明如何在 Xcode 中运行。

---

## 11. 有效睡眠值定义

Phase 1 的统计只用于粗略展示，不用于医学判断。

建议把以下值视作 asleep-like：

- `asleepUnspecified`
- `asleepCore`
- `asleepDeep`
- `asleepREM`

以下值不计入有效睡眠：

- `awake`
- `inBed`

注意：

- `inBed` 不是 asleep。
- `inBed` 和 asleep samples 可能重叠，统计时不要简单相加。
- Phase 1 重点不是精确算睡眠时长，而是观察 HealthKit 数据何时写入和何时被 App 收到。

---

## 12. 隐私与安全要求

- 不要上传任何 HealthKit 数据。
- 不要接入 Firebase、服务器、Analytics、广告 SDK。
- 本地日志只存储在 App sandbox。
- 导出前提示用户导出文件包含健康相关时间线数据。
- 不要在控制台长期打印过多敏感数据；debug log 可以有，但本地文件是主记录。
- README 中明确：这是研发验证工具，不是医疗诊断软件。

---

## 13. Codex 执行顺序

请按以下顺序实现，不要跳阶段。

### Step 1：检查仓库

- 先查看当前目录结构。
- 如果已有 iOS 项目，复用现有项目。
- 如果没有项目，创建 `SleepKitProbe` SwiftUI iOS App。
- 不要删除用户已有文件。

### Step 2：HealthKit 权限最小闭环

- 添加 HealthKit capability / entitlement。
- 实现授权请求。
- UI 显示授权结果。
- 能查询最近 24h sleep samples。

验收：真机运行后，用户能看到 HealthKit 授权弹窗；授权后可读历史睡眠样本。

### Step 3：Observer + Anchored Query

- 实现 observer。
- 实现 anchored query。
- 本地持久化 anchor。
- 记录 observer events 和 sleep sample records。

验收：新增或变化的 sleep samples 能被记录；手动刷新和 observer 触发路径都能区分。

### Step 4：日志导出

- 实现 CSV 导出。
- 实现 JSONL 导出。
- iOS share sheet 导出文件。

验收：用户能把日志 AirDrop / 保存到 Files。

### Step 5：实验 README

- 写 `README_PHASE1.md`。
- 包含真机测试步骤。
- 包含一晚实验协议。
- 包含如何解读 CSV。

### Step 6：测试和清理

- 添加单元测试。
- 修复明显 SwiftLint / compiler warnings。
- 确保项目可以 build。
- 在最后输出变更摘要和如何运行。

---

## 14. 最终交付标准

Phase 1 完成时，仓库应该满足：

- 可以在 Xcode 打开并部署到 iPhone 真机。
- 能请求 HealthKit sleepAnalysis read permission。
- 能读取最近 24h / 7d sleep samples。
- 能启动 observer。
- 能用 anchored query 增量读取。
- 能记录 observer 触发时间和 sample 接收时间。
- 能导出 CSV / JSONL。
- 有 `README_PHASE1.md` 指导用户跑一晚实验。
- 有基本单元测试。
- 没有云上传，没有登录，没有广告，没有复杂闹钟逻辑。

---

## 15. 不确定性和后续决策

Codex 在实现时不要替我们假设结论。Phase 1 的目的就是收集证据。

实验后根据数据决定：

```text
如果 HealthKit sleepAnalysis 夜间近实时更新：
    Phase 2 可以做 HealthKit-based dynamic alarm MVP。

如果 HealthKit sleepAnalysis 主要醒后/解锁后才更新：
    Phase 2 应转向 watchOS companion app，自研 awake/asleep 检测。
```

后续 Phase 2/3 暂不实现，只在 README 中简短说明可能方向即可。

---

## 16. 给 Codex 的工作风格要求

- 每次修改前先理解现有结构。
- 优先实现能运行的最小闭环，不要过度设计。
- 不要引入大型依赖。
- 不要写伪代码冒充完成。
- 所有新文件命名清晰。
- 遇到 Apple capability / signing 无法自动完成时，写清楚用户需要在 Xcode 里手动打开哪些开关。
- 代码里关键地方加注释，尤其是 HealthKit observer、anchored query、anchor persistence、background delivery。
- 最终回答必须包含：
  - 修改了哪些文件；
  - 如何在 Xcode 中运行；
  - 如何进行一晚实验；
  - 目前还有哪些限制。

---

## 17. 当前实现结构速查

本节记录当前 Phase 1 已实现代码入口和职责，方便后续继续开发时快速定位。

### 17.1 App 入口与主 UI

```text
SleepKitProbe/
  SleepKitProbeApp.swift
  ContentView.swift
  Views/
    DashboardView.swift
    SampleListView.swift
    LogListView.swift
    ExportView.swift
    ShareSheet.swift
```

- `SleepKitProbeApp.swift`：SwiftUI App 入口，启动后加载 `ContentView`。
- `ContentView.swift`：主 TabView，包含 Dashboard / Samples / Logs / Export 四个页面，并创建共享的 `HealthKitManager`。
- `DashboardView.swift`：实验控制台。显示 HealthKit 可用性、权限请求状态、observer 状态、background delivery 状态、active session、最近 observer 触发时间、日志数量、最近 24h asleep-like 粗略时长。按钮包括请求权限、启动 observer、手动刷新 24h/7d、开始/结束夜间实验、清空本地日志。
- `SampleListView.swift`：展示最近 7 天 sleep samples。显示 `valueName`、样本开始/结束时间、duration、source、receivedAt、latency、sync source。
- `LogListView.swift`：展示 observer events 和 app events。用于看 observer 是否触发、触发时读到多少新增样本、是否有错误。
- `ExportView.swift`：导出 CSV / JSONL，并提示导出文件包含健康相关时间线数据。
- `ShareSheet.swift`：UIKit `UIActivityViewController` 包装，用于 AirDrop / 保存到 Files。

### 17.2 HealthKit 入口

```text
SleepKitProbe/HealthKit/
  HealthKitManager.swift
  SleepObserverService.swift
  SleepAnchoredQueryService.swift
  SleepSampleMapper.swift
```

- `HealthKitManager.swift`：核心状态管理入口，也是 UI 调用的主要 facade。
  - `requestHealthKitPermission()`：请求 `sleepAnalysis` 读取权限。
  - `enableBackgroundDelivery()`：调用 HealthKit background delivery，频率请求为 `.immediate`，但不假设系统保证实时。
  - `startObserver()`：启动 observer。当前实现会先 bootstrap anchored-query anchor，第一次启动时跳过历史样本，避免把用户买表以来的所有睡眠记录当作新样本写入日志。
  - `manualRefreshLast24Hours()` / `manualRefreshLast7Days()`：用 `HKSampleQuery` 主动读取最近 24h / 7d 样本，写入本地日志，`syncSource` 分别标记为 `manualRefresh` / `manualRefresh7d`。
  - `startNightProbe()` / `endNightProbe()`：创建或结束本地 `ProbeSession`，给后续日志打 `sessionId`。它不启动睡眠识别，也不改变 HealthKit。
  - `exportCSV()` / `exportJSONL()`：生成导出文件并触发分享。
  - `clearLocalLogs()`：清空本地日志、active session 和 saved anchor。
- `SleepObserverService.swift`：薄封装 `HKObserverQuery`。observer callback 只记录触发时间并交给 anchored query 做实际读取，最后必须调用 HealthKit completion handler。
- `SleepAnchoredQueryService.swift`：薄封装 `HKAnchoredObjectQuery`。
  - `fetchUpdates(...)`：从 saved anchor 开始读取新增/删除对象，并保存新 anchor。
  - `bootstrapAnchorIfNeeded(...)`：如果还没有 anchor，先读取一次历史返回值但只保存 anchor、不记录历史 samples，用来让后续 observer 真正只看“从现在以后”的增量。
  - `resetAnchor()`：清空 saved anchor，通常和 Clear Local Logs 一起使用。
- `SleepSampleMapper.swift`：把 `HKCategorySample` 转换成本地 `SleepSampleRecord`，并把 raw value 映射为 `inBed`、`awake`、`asleepCore`、`asleepDeep`、`asleepREM`、`asleepUnspecified` 或 `unknown(raw)`。

### 17.3 本地模型

```text
SleepKitProbe/Models/
  SleepSampleRecord.swift
  ObserverEventRecord.swift
  ProbeSession.swift
  AppEventRecord.swift
  DurationAggregation.swift
```

- `SleepSampleRecord.swift`：每条 HealthKit sleep sample 的本地记录。关键字段：
  - `sampleUUID`：HealthKit sample UUID。
  - `receivedAt`：App 实际读到并写入日志的时间。
  - `queryTriggeredAt`：手动刷新或 observer 触发时间。
  - `sampleStartDate` / `sampleEndDate`：HealthKit 样本自身覆盖的时间段。
  - `valueRaw` / `valueName`：HealthKit sleep value。
  - `sourceName` / `sourceBundleIdentifier` / `deviceName`：数据来源。
  - `syncSource`：`manualRefresh`、`manualRefresh7d` 或 `observerAnchoredQuery`。
  - `latencySeconds`：`receivedAt - sampleEndDate`，用于判断数据延迟。
- `ObserverEventRecord.swift`：每次 observer callback 的本地记录，即使没有读到新增样本也记录。
- `ProbeSession.swift`：一次夜间实验 session，用户点击 `Start Night Probe` 创建。
- `AppEventRecord.swift`：记录 app 级事件，例如启动、请求权限、导出、清空日志。
- `DurationAggregation.swift`：粗略统计 asleep-like duration。当前 Dashboard 显示最近 24h，且会 union overlapping intervals 避免重复计算；`awake` 和 `inBed` 不计入有效睡眠。

### 17.4 日志和导出

```text
SleepKitProbe/Logging/
  ProbeLogger.swift
  ProbeLogModels.swift
  CSVExporter.swift
  JSONLExporter.swift
```

- `ProbeLogger.swift`：本地日志入口。日志文件位于 App sandbox 的 Application Support 目录，文件名为 `probe_log.jsonl`。负责 append、加载已有日志、清空日志、生成导出文件。
- `ProbeLogModels.swift`：JSONL 每行的 typed envelope，类型包括 `sleep_sample`、`observer_event`、`app_event`。
- `CSVExporter.swift`：生成 `sleep_samples.csv` 和 `observer_events.csv`，包含 CSV escaping。
- `JSONLExporter.swift`：生成 `sleepkit_probe_log.jsonl`，每行一个 JSON 对象。

### 17.5 工具和工程配置

```text
SleepKitProbe/Utilities/
  DateFormatters.swift
  FileStore.swift

SleepKitProbe/
  SleepKitProbe.entitlements

README_PHASE1.md
```

- `DateFormatters.swift`：统一 ISO8601 导出格式和 UI 展示格式。
- `FileStore.swift`：Application Support 和 temporary export directory 的路径管理。
- `SleepKitProbe.entitlements`：HealthKit capability。包含 `com.apple.developer.healthkit` 和 `com.apple.developer.healthkit.background-delivery`。
- `README_PHASE1.md`：面向使用者的一晚实验说明、导出字段解读、判断标准和注意事项。

### 17.6 测试

```text
SleepKitProbeTests/
  SleepSampleMapperTests.swift
  CSVExporterTests.swift
  DurationAggregationTests.swift
  ProbeLoggerTests.swift
  TestRecords.swift
```

- `SleepSampleMapperTests.swift`：验证 raw value 到 readable name 的映射，未知 raw value 不崩溃。
- `CSVExporterTests.swift`：验证 CSV header、日期格式、逗号/换行/引号 escaping。
- `DurationAggregationTests.swift`：验证 asleep-like duration、awake/inBed 不计入、overlapping samples 不重复计算、长样本会按展示窗口裁剪。
- `ProbeLoggerTests.swift`：验证 JSONL 写入和 App 重启后读取已有日志。
- `TestRecords.swift`：测试用 sample fixture。

### 17.7 当前使用语义

```text
Start Observer
```

启动 HealthKit observer 和 background delivery，并建立 anchored-query anchor。第一次启动如果没有 saved anchor，会跳过历史样本，只记录从 anchor 之后出现的新增/删除对象。

```text
Manual Refresh Last 24h / Last 7d
```

主动查询最近 24h / 7d HealthKit sleep samples，主要用于确认权限、补抓早上才出现的数据、和 observer 路径做对照。

```text
Start Night Probe
```

开始一次本地实验 session，只负责给后续日志打同一个 `sessionId`。它不启动 HealthKit observer，也不启动任何自研睡眠识别算法。

```text
End Night Probe
```

结束当前实验 session。后续日志不再带这个 session id。

```text
Clear Local Logs
```

删除本地 JSONL 日志、active session、saved anchor，并停止当前 observer。清空后再次 `Start Observer` 会重新 bootstrap anchor。
