# API 指南

`SheepFenceClient` 是主 actor 的具體用戶端；`GeofenceClient` 是供依賴注入與 App mock 使用的公開 Sendable protocol。公開結果型別提供初始化方法。

## 用戶端操作

| API | 用途 |
|---|---|
| `open(storeURL:configuration:)` | 開啟並還原持久化用戶端 |
| `installSnapshot(from:)` / `installSnapshot(data:)` | 安裝快照並回傳 `InstallResult` |
| `datasets()` | 取得 `[DatasetSummary]` |
| `regions(in:)` / `regions()` | 取得 `[RegionSummary]` |
| `removeDataset(id:)` | 刪除資料集並回傳 `DatasetRemovalResult` |
| `query(coordinate:in:)` / `contains(coordinate:in:)` | 幾何內外判定 |
| `distance(from:to:)` | 取得 `RegionDistanceResult` |
| `evaluate(location:)` | 純查詢，回傳 `EvaluationBatch` |
| `submit(location:)` | 有狀態的定位輸入，回傳 `EvaluationBatch` |
| `state()` | 取得一致的 `MonitoringState` |
| `events(bufferCapacity:)` / `events()` | 有界、可拋錯的非同步事件串流 |
| `startMonitoring(mode:)` / `stopMonitoring()` | 啟動或停止監測 |
| `updateAvailability(_:)` | 回報 host 定位來源狀態 |

所有操作都是非同步的。`datasets`、`state`、`stopMonitoring` 不拋錯，其餘可能拋錯。`evaluate` 與 `submit` 支援 `LocationSample` 和 `CLLocation`。純查詢不更新監測；`submit` 限於已啟動的 host-provided 模式。安裝與刪除可能重新設定或移除觀測。

[Protocol 原始碼](https://github.com/julianshen/sheepfence/blob/main/Sources/SheepFence/GeofenceClient.swift) · [DocC 概覽（英文）](https://github.com/julianshen/sheepfence/blob/main/Sources/SheepFence/SheepFence.docc/SheepFence.md)

## 設定

```swift
let configuration = try GeofenceConfiguration(
    maximumLocationAge: 30,
    boundaryBufferMeters: 5,
    maximumFutureSkew: 1,
    expectedDatasetIDs: ["com.example.campus"],
    downloadPolicy: DownloadPolicy(maximumBytes: 5_000_000, timeout: 30),
    sampling: .fixed(LocationSamplingConfiguration(
        distanceFilterMeters: 10,
        desiredAccuracyMeters: 10
    ))
)
```

數值僅供示範，尚未經實地校準。外層 `try` 也涵蓋內層會拋錯的初始化。

| 設定 | 預設與限制 |
|---|---|
| `maximumLocationAge` | 必填，有限且大於零秒 |
| `boundaryBufferMeters` | 0，有限且非負 |
| `maximumFutureSkew` | 0，有限且非負秒數 |
| `expectedDatasetIDs` | 空集合；ID 不可為空 |
| `downloadPolicy` | `.standard`：5,000,000 bytes／30 秒 |
| `sampling` | `.fixed(.standard)`：10 m 篩選／10 m 精度 |

固定精度要求須為有限正值。距離篩選須為有限非負值，零表示關閉距離篩選。以負值表示的 Core Location 精度常數不適用於此以公尺為單位的 API。

## 結果與遷移

`EvaluationBatch` 包含評估與樣本時間、資料集及區域結果。`RegionEvaluation` 包含 ID、修訂版、觀測和歷史確認。`MonitoringState` 包含模式、就緒狀態、可用性與目前評估。`RegionDistanceResult` 明確區分可估算與不支援的距離。`DatasetChange` 表示受影響及移除的 ID。

舊版有狀態的 `evaluate` 已拆分為純 `evaluate` 與有狀態的 `submit`。僅補上 `.results` 不會保留舊行為。事件串流現在會拋錯，並包含初始快照及評估批次。舊四參數 factory 已棄用，下載與取樣政策移入 configuration。請參閱[遷移指南（英文）](https://github.com/julianshen/sheepfence/blob/main/docs/sdk-migration.md)。
