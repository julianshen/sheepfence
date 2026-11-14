# 位置照会と距離

指定した座標や GPS 測位について問い合わせます。照会は監視状態を変更せず、イベントも発行しません。現在の監視モードにかかわらず使用できます。

## どの領域にいるか

```swift
let batch = try await client.evaluate(location: currentLocation)
for result in batch.results {
    switch result.observation {
    case .confirmed(.inside):
        print("Inside", result.regionID)
    case .confirmed(.outside):
        print("Outside", result.regionID)
    case .boundaryUncertain:
        print("Too close to the boundary for a confirmed answer")
    case .unavailable(let reason):
        print("Location unavailable:", reason)
    }
}
```

`evaluate` は `CLLocation` または `LocationSample` を受け取り、有効な領域について座標、測位時刻、水平精度を確認します。`batch.datasets` と各結果の `revision` で使用したスナップショットを確認できます。純粋な照会結果には監視の `lastConfirmed` 履歴は含まれません。

古い測位、未来の時刻、無効な座標では所属を確認できません。座標自体が内側でも、精度の範囲が境界をまたぐ場合があります。空の結果だけで全領域の外にいると判断せず、データセットの準備状態も確認してください。

## 座標だけの幾何判定

```swift
let region = RegionID(datasetID: "com.example.campus", featureID: "campus")
let coordinate = Coordinate(longitude: 10.003, latitude: 20.002)
let result = try await client.query(coordinate: coordinate, in: region)
let inside = try await client.contains(coordinate: coordinate, in: region)
```

`query` は内外判定とリビジョンを返し、`contains` は Boolean の便利メソッドです。GPS 精度や時刻は考慮しないため、確認済みの位置を判定する API とは異なります。ID で指定すれば無効化された領域も照会できます。領域の識別子はデータセット ID と feature ID の組み合わせであり、表示名ではありません。

## 領域・境界までの距離

```swift
let result = try await client.distance(from: coordinate, to: region)
let toRegion: Double? = result.distanceToRegionMeters
let toBoundary: Double? = result.distanceToBoundaryMeters

switch result.boundaryDistance {
case .approximateMeters(let meters):
    print("Nearest boundary:", meters, "m")
case .unsupported(let reason):
    print("No supported boundary estimate:", reason)
}
```

| 位置と推定の可否 | 領域までの距離 | 境界までの距離 |
|---|---|---|
| 内側、推定可能 | `0` | 最も近い境界までの概算距離 |
| 外側、推定可能 | 最も近い境界までの概算距離 | 同じ値 |
| 内側、推定非対応 | `0` | `nil` |
| 外側、推定非対応 | `nil` | `nil` |

有効なゼロ距離と推定非対応は異なります。外側の距離が取得できない場合にゼロを表示しないでください。各結果は一つのコミット済みスナップショットを使用し、そのリビジョンを返します。

距離はメートル単位の概算直線距離です。徒歩・自動車の経路距離ではなく、GPS 精度の半径も含みません。局所モデルは緯度 ±80° 以内で、全頂点の緯度と展開済み経度が照会点から一度以内であることを要求します。MultiPolygon の離れた部分によって推定非対応になることがありますが、幾何的な内外判定は引き続き利用できます。

## evaluate と submit

検索、プレビュー、単発の確認には `evaluate` を使います。実際の監視入力には、`.hostProvided` を開始した後で `submit` を使います。後者は履歴を更新し、サンプルの順序を検査して、基準や境界通過のイベントを発生させます。
