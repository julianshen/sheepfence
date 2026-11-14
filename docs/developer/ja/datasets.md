# データセット

データセットは、固定 ID と単調増加するリビジョンを持つ完全な GeoJSON スナップショットです。SDK 自体のバージョンとは独立しています。

## 地図でスナップショットを作る

[Fence Studio](editor.html) はポリゴン、穴、MultiPolygon に対応します。場所をダブルクリックして登録済み境界を取得するか、手動で描画・編集できます。[エディタガイド](fence-editor.md) も参照してください。

## 最小のスナップショット

以下を `campus.geojson` として保存し、アプリの bundle に追加します。

```json
{
  "type": "FeatureCollection",
  "geofenceSchema": 1,
  "dataset": {
    "id": "com.example.campus",
    "revision": 1,
    "generatedAt": "2026-11-14T00:00:00Z"
  },
  "features": [{
    "type": "Feature",
    "id": "campus",
    "properties": { "name": "Campus", "enabled": true, "priority": 0 },
    "geometry": {
      "type": "Polygon",
      "coordinates": [[
        [10.000, 20.000], [10.006, 20.000], [10.006, 20.004],
        [10.000, 20.004], [10.000, 20.000]
      ]]
    }
  }]
}
```

座標は**経度、緯度**の順です。リングは閉じており、有効な形状でなければなりません。Polygon、MultiPolygon、穴に対応しますが、任意の GeoJSON 形状を受け付けるわけではありません。データセットと feature の ID は空でない文字列で、同一データセット内の feature ID は一意にします。リビジョンは正の整数、`generatedAt` は `Z` で終わる RFC3339 UTC 時刻です。

`properties` はオブジェクトである必要があります。省略時の既定値は `enabled` が true、`priority` がゼロ、`name` が feature ID です。トポロジーと境界の規則は[仕様書（英語）](https://github.com/julianshen/sheepfence/blob/main/geofence-sdk-spec-v0.3.md) を参照してください。

## ファイル、HTTPS、Data から読み込む

```swift
let result = try await client.installSnapshot(from: snapshotURL)
print(result.outcome, result.activeRevision)

// If your app handles authenticated networking itself:
let imported = try await client.installSnapshot(data: downloadedData)
```

SDK のネットワーク取得は HTTPS を使用し、リダイレクトは追跡前に拒否します。標準上限は 5,000,000 bytes、通信タイムアウトは 30 秒です。ローカルファイルと Data にもサイズ上限があります。独自認証が必要ならアプリ側で取得して Data を渡します。情報源エラーには URL、認証情報、生の通信エラーを含めません。

## リビジョンと全体置換

| 入力 | 結果 |
|---|---|
| 新しいリビジョン | 検証後、データセット全体を原子的に置換 |
| 同じリビジョン、同一 bytes | `.unchanged` |
| 同じリビジョン、異なる bytes | `revisionConflict` |
| 古いリビジョン | `.olderVersionSkipped` |
| 無効な更新・失敗 | 既存のコミット済みデータを保持 |

同一 bytes は形状が等価という意味ではありません。公開済み JSON の整形を変える場合もリビジョンを増やしてください。置換から省略した feature は削除されます。部分更新 API ではなく、別のデータセット ID は互いに独立しています。

コミット開始前のキャンセルでは新しいスナップショットを公開しません。永続化のコミットが始まった後は、キャンセルを受けても完了して実際の結果を返します。キャンセルを常にロールバックと解釈しないでください。

## 一覧と削除

```swift
let datasets = await client.datasets()
let regions = try await client.regions(in: "com.example.campus")
let removal = try await client.removeDataset(id: "com.example.campus")
print(removal.wasPresent, removal.removedRegionIDs)
```

削除は永続化され、インストールと直列に実行されます。存在しない ID の削除は何も変更しません。`.datasetRemoved` は退出イベントを生成しません。再オープン時はコミット済みデータを復元しますが、位置履歴は復元しません。

## 必須データセット

評価前に必要な ID を `expectedDatasetIDs` に指定します。`state().readiness` の `.noDatasets`、`.missingRequired(...)`、`.ready` を確認してください。必須データの欠落は準備未完了であり、領域外を意味しません。
