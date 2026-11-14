# API ガイド

`SheepFenceClient` はメイン actor 上の具体的なクライアントです。`GeofenceClient` は依存性注入やアプリの mock に使う公開 Sendable protocol です。公開結果型にはイニシャライザがあります。

## クライアント操作

| API | 用途 |
|---|---|
| `open(storeURL:configuration:)` | 永続クライアントを開いて復元 |
| `installSnapshot(from:)` / `installSnapshot(data:)` | スナップショットを導入し `InstallResult` を取得 |
| `datasets()` | `[DatasetSummary]` を取得 |
| `regions(in:)` / `regions()` | `[RegionSummary]` を取得 |
| `removeDataset(id:)` | データセットを削除し `DatasetRemovalResult` を取得 |
| `query(coordinate:in:)` / `contains(coordinate:in:)` | 幾何的な内外判定 |
| `distance(from:to:)` | `RegionDistanceResult` を取得 |
| `evaluate(location:)` | 純粋な照会で `EvaluationBatch` を取得 |
| `submit(location:)` | 状態を更新する入力で `EvaluationBatch` を取得 |
| `state()` | 一貫した `MonitoringState` を取得 |
| `events(bufferCapacity:)` / `events()` | 上限付きの throwing 非同期イベントストリーム |
| `startMonitoring(mode:)` / `stopMonitoring()` | 監視を開始・停止 |
| `updateAvailability(_:)` | host の位置情報源の状態を通知 |

すべて非同期です。`datasets`、`state`、`stopMonitoring` はエラーを投げず、他は投げる可能性があります。`evaluate` と `submit` は `LocationSample` と `CLLocation` に対応します。純粋な照会は監視を更新せず、`submit` は開始済みの host-provided モード専用です。導入や削除は観測の再設定・削除を伴う場合があります。

[Protocol ソース](https://github.com/julianshen/sheepfence/blob/main/Sources/SheepFence/GeofenceClient.swift) · [DocC 概要（英語）](https://github.com/julianshen/sheepfence/blob/main/Sources/SheepFence/SheepFence.docc/SheepFence.md)

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

数値は例であり、実地校正済みの推奨値ではありません。外側の `try` は内側の throwing イニシャライザにも適用されます。

| 設定 | 既定値と制約 |
|---|---|
| `maximumLocationAge` | 必須。有限かつゼロより大きい秒数 |
| `boundaryBufferMeters` | 0。有限で非負 |
| `maximumFutureSkew` | 0。有限で非負の秒数 |
| `expectedDatasetIDs` | 空集合。ID は空にできない |
| `downloadPolicy` | `.standard`：5,000,000 bytes／30 秒 |
| `sampling` | `.fixed(.standard)`：10 m フィルタ／10 m 精度 |

固定の要求精度は有限の正数、距離フィルタは有限の非負値です。ゼロは距離フィルタを無効にします。負数で表す Core Location の精度定数は、このメートル単位の API では使用できません。

## 結果と移行

`EvaluationBatch` は評価・サンプル時刻、データセット、領域結果を含みます。`RegionEvaluation` は ID、リビジョン、観測、過去の確認状態を持ちます。`MonitoringState` はモード、準備状態、利用可否、現在の評価です。`RegionDistanceResult` は推定可能・非対応を区別します。`DatasetChange` は影響を受けた ID と削除された ID を示します。

従来の状態付き `evaluate` は純粋な `evaluate` と状態付き `submit` に分かれました。`.results` を付けるだけでは旧動作は維持されません。イベントは throwing になり、初期スナップショットと評価バッチを含みます。旧 4 引数 factory は非推奨となり、取得とサンプリングのポリシーは configuration に移りました。[移行ガイド（英語）](https://github.com/julianshen/sheepfence/blob/main/docs/sdk-migration.md) を参照してください。
