# トラブルシューティング

まず `await client.state()` でモード、データセットの準備状態、位置の利用可否を確認してから領域の結果を解釈します。

| 症状 | 対処 |
|---|---|
| `storeAlreadyOpen` | 既存クライアントを再利用します。シンボリックリンクも同じストアを指し、保留中の操作がリースを保持する場合があります。 |
| `datasetNotReady` | 必須データセットをすべてインストールし、`state().readiness` を確認します。 |
| `evaluate` で進入イベントがない | 状態を変更しない API です。起動済みの `.hostProvided` と `submit`、または `.sdkManaged` を使用します。 |
| `monitoringNotStarted` | 位置を送信する前にホスト提供モードを開始します。 |
| `sourceModeConflict` | モード切り替え前に停止します。SDK 管理モードにホスト位置を送信しないでください。 |
| `regionNotFound` | `RegionID` の両方の ID と、置き換えで削除されていないかを確認します。 |
| `boundaryUncertain` | 精度とバッファーでは境界のどちら側か確定できません。外側と決めつけないでください。 |
| `.unavailable(.staleLocation)` | 新しいタイムスタンプの位置を渡し、最大経過時間を確認します。 |
| `.unavailable(.outOfOrderLocation)` | 時刻順に位置を送信します。 |
| 境界距離がない | `.unsupported` を確認します。局所距離モデルの範囲外の可能性があります。 |
| `eventBufferOverflow` | 再購読で現在の状態を取得し、イベント処理を軽くするかバッファーを適切に増やします。欠落イベントは再生されません。 |

## ソースとインポートのエラー

`GeofenceError.sourceFailed` の `SourceFailure` に応じて処理します。種類は `unsupportedScheme`、`httpStatus`、`timeout`、`byteLimitExceeded`、`redirectRejected`、`network`、`fileRead` です。一時的な障害はアプリの方針に従って再試行し、無効な形状や未対応スキームを繰り返し試さないでください。エラーには元の URL、認証情報、通信エラーの詳細を含めません。

```swift
do {
    _ = try await client.installSnapshot(from: snapshotURL)
} catch GeofenceError.sourceFailed(let failure) {
    print("Snapshot source failed:", failure)
} catch GeofenceError.invalidSnapshot(let regionID, let path, let reason) {
    print("Invalid snapshot:", regionID ?? "dataset", path, reason)
} catch {
    print("Install failed:", error)
}
```

診断のパスと領域 ID を使って生成側を修正します。同一リビジョンの競合は、確定済みの版に異なるバイト列が届いたことを意味します。置き換え時は版を増やし、サーバーと公開手順の両方で動作する旧版を保持してください。

## 権限と GPS

SDK はアプリの認可を回避できません。利用目的の説明、許可フロー、端末の位置情報サービスを確認します。権限拒否、サービス停止、一時的な位置欠落は利用不可であり、領域からの退出ではありません。精度の低下は別途通知され、境界の不確実性が広がる場合があります。

バックグラウンド動作や自動の権限要求は保証しません。合成サンプルや性能測定では実際の GPS 経路を検証できません。前景への移行、認可変更、精度低下は実機で確認してください。

## 問題の報告

SDK のコミット、OS・端末、モード、機密情報を除いた設定、期待する動作、最小の合成スナップショットと位置を添えて [GitHub Issues](https://github.com/julianshen/sheepfence/issues) に報告してください。実際の移動履歴や認証付き URL は共有しないでください。
