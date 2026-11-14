# 監視と GPS

位置情報の権限要求とフォアグラウンドのライフサイクルはアプリが管理します。SheepFence は情報源の利用可否、現在の観測、過去の確認結果を分けて扱います。

## 位置情報源を選ぶ

| モード | 位置の提供元 | アプリの責任 |
|---|---|---|
| `.sdkManaged` | SDK の Core Location provider | 権限要求とフォアグラウンドに連動した開始・停止 |
| `.hostProvided` | アプリの既存の測位処理 | 測位の送信と利用可否の通知 |

必要なデータセットを先にインストールしてください。同じモードでの再開始は冪等です。モード変更の前には停止が必要です。`submit` は開始済みの host-provided モードでのみ使用できます。

SDK 管理モードでは、Info.plist に明確な `NSLocationWhenInUseUsageDescription` を追加し、アプリ自身で Core Location の権限を要求してください。SDK の開始だけでは権限ダイアログは表示されません。

## 開始前に購読する

次の関数が返す Task をアプリケーションモデルで保持し、所有者の破棄時にキャンセルしてください。

```swift
import SheepFence

@MainActor
func watch(_ client: SheepFenceClient) async throws -> Task<Void, Never> {
    let stream = try await client.events(bufferCapacity: 256)
    return Task { @MainActor in
        do {
            for try await event in stream {
                switch event {
                case .stateSnapshot(let state):
                    print("Initial state:", state)
                case .entered(let evaluation):
                    print("Entered:", evaluation.regionID)
                case .exited(let evaluation):
                    print("Exited:", evaluation.regionID)
                case .evaluated(let batch):
                    print("Current observations:", batch.results)
                default:
                    print("State or dataset change:", event)
                }
            }
        } catch {
            print("Subscription ended:", error)
        }
    }
}
```

メイン actor のモデルで開始・停止します。

```swift
let eventTask = try await watch(client)
try await client.startMonitoring(mode: .sdkManaged)

// In your app's foreground lifecycle handler, when leaving the foreground:
await client.stopMonitoring()

// When the subscriber's owner is disposed:
eventTask.cancel()
```

これはライフサイクル処理の断片です。本番のアプリで開始直後に停止するという意味ではありません。処理を直列化し、単一の所有者を維持してください。[サンプルアプリ（英語）](https://github.com/julianshen/sheepfence/tree/main/Examples/ForegroundHost) に実装例があります。停止してもデータセットや購読は削除しませんが、セッションの観測を消去し、架空の退出を生成せず `monitoringStopped` を通知します。

## アプリから GPS を提供する

```swift
try await client.startMonitoring(mode: .hostProvided)
let batch = try await client.submit(location: currentLocation)

// When your source cannot supply a fix:
try await client.updateAvailability(LocationAvailability(reason: .noLocation))

// When source availability returns, report it and submit a fresh fix:
try await client.updateAvailability(LocationAvailability())
let recovered = try await client.submit(location: nextLocation)
```

権限拒否やサービス無効を、対応する `LocationUnavailableReason` で通知します。`reducedAccuracy` は独立したフラグであり、領域外を意味しません。情報源が利用可能になっても、新しい有効な測位が得られたとは限りません。

## 中断と復帰

中断時には観測が利用不可になり、`lastConfirmed` に最後の確認状態と時刻が残ります。現在位置ではなく過去の情報として表示してください。復帰後の最初の確認結果は新しい基準となり、中断期間中の移動を推測しません。

`state()` は測位の鮮度を含む、一貫した現在状態を返します。測位の期限切れ時にタイマーイベントが発生する保証はありません。UI は状態を再取得するか、時刻を使って古い結果を判別してください。

## イベントとバッファ

購読は原子的な `stateSnapshot` で始まり、その後は順序付きでイベントを受け取ります。`.evaluated` は状態を伴う入力結果、`.baseline` は基準、`.entered` と `.exited` は確認済みの境界通過です。`.datasetChanged` は形状変更による基準の再設定、`.datasetRemoved` は削除を通知します。置換や削除は架空の退出を生成しません。`.evaluationFailed` は provider 経由の評価エラーで、インポート呼び出しが直接投げるエラーとは別です。

各購読のバッファは独立しており、既定の上限は 256 です。処理が遅い購読は `eventBufferOverflow` で終了し、他の購読は継続します。再購読で現在の状態を取得できますが、欠落イベントは再生しません。イベント処理は軽く保ち、永続ログはアプリ側で管理してください。

## サンプリング

固定設定は精度 10 m、距離フィルタ 10 m を要求します。これは Core Location への要求であり、保証ではありません。適応型は `.adaptive(SamplingPolicyConfiguration(...))` で明示的に有効化し、既定値は未校正です。実経路で電力と検出遅延を検証してください。バックグラウンド監視は保証されません。
