# クイックスタート

永続ストアを持つクライアントを開き、スナップショットをインストールして位置を評価します。単発の照会では GPS を起動せず、監視履歴も変更しません。

## 1. Swift パッケージを追加する

Xcode の **File → Add Package Dependencies** で `https://github.com/julianshen/sheepfence` を入力し、**Up to Next Major Version** で **1.0.0** を指定し、 `SheepFence` 製品をアプリの target に追加します。Swift パッケージでは次のように指定します。

```swift
.package(url: "https://github.com/julianshen/sheepfence", from: "1.0.0")
```

target の依存関係には `.product(name: "SheepFence", package: "sheepfence")` を追加します。Swift 6 と iOS 16+ が必要です。macOS 13+ はパッケージ・エンジンのテスト用であり、macOS での位置監視を保証するものではありません。依存関係の解決結果を再現できるよう、アプリの `Package.resolved` をコミットしてください。

## 2. クライアントを開いて保持する

有効な `campus.geojson` をアプリの bundle に追加します。[データセットガイド](datasets.md) にサンプルがあります。以下の関数は Application Support にストアを作り、スナップショットを読み込みます。

```swift
import Foundation
import SheepFence

@MainActor
func openGeofences(snapshotURL: URL) async throws -> SheepFenceClient {
    let support = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let storeURL = support.appendingPathComponent("SheepFence/regions.sqlite")
    let configuration = try GeofenceConfiguration(maximumLocationAge: 60)
    let client = try await SheepFenceClient.open(
        storeURL: storeURL,
        configuration: configuration
    )
    _ = try await client.installSnapshot(from: snapshotURL)
    return client
}
```

返されたクライアントは、メイン actor のアプリケーションモデルで保持します。オープン時にコミット済みデータセットを復元し、不足する親ディレクトリを作成します。同一プロセス内では、正規化された SQLite パスごとに存続するクライアントは一つだけです。画面間で共有し、アプリがフォアグラウンドを離れるときに監視を停止してください。

60 秒の有効期間は例です。製品の要件に合わせて設定してください。クライアントを開くだけでは位置情報の権限を要求しません。

## 3. 測位を評価する

保持済みの `client` と、アプリから渡された `CLLocation` を使用します。

```swift
let batch = try await client.evaluate(location: currentLocation)
let matches = batch.results.filter {
    $0.observation == .confirmed(.inside)
}
for match in matches {
    print(match.regionID.datasetID, match.regionID.featureID)
}
```

複数の領域が一致する場合があります。`.boundaryUncertain` と `.unavailable` は領域外として扱わず、それぞれ処理してください。統合確認用の合成サンプルは次のように作れます。

```swift
let sample = LocationSample(
    coordinate: Coordinate(longitude: 10.003, latitude: 20.002),
    timestamp: Date(),
    horizontalAccuracy: 5
)
let batch = try await client.evaluate(location: sample)
```

この手動サンプルは実際の端末の位置情報を代替するものではありません。

## 4. 必要に応じて監視を追加する

継続的な観測や進入・退出イベントが必要なら、[監視と GPS](monitoring.md) を参照してください。純粋な照会である `evaluate` を繰り返しても境界通過イベントは発生しません。`.hostProvided` と `submit`、または `.sdkManaged` を使用します。

[フォアグラウンドのサンプルアプリ（英語）](https://github.com/julianshen/sheepfence/tree/main/Examples/ForegroundHost) にシミュレータ、実機、ベンチマークの設定手順があります。
