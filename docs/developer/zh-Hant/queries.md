# 位置查詢與距離

查詢針對指定座標或 GPS 定位提供答案，不會修改監測狀態或發送事件，也不受目前監測模式影響。

## 我位於哪個區域？

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

`evaluate` 接受 `CLLocation` 或 `LocationSample`，評估已啟用區域，並檢查座標有效性、時間與水平精度。`batch.datasets` 和結果的 `revision` 表示使用的快照版本。純查詢結果不包含監測的 `lastConfirmed` 歷史。

過期、未來時間或無效定位無法確認所在區域。即使座標位於多邊形內，精度範圍仍可能跨越邊界。空結果不代表一定在所有區域外，也要檢查資料集是否就緒。

## 只查詢座標幾何

```swift
let region = RegionID(datasetID: "com.example.campus", featureID: "campus")
let coordinate = Coordinate(longitude: 10.003, latitude: 20.002)
let result = try await client.query(coordinate: coordinate, in: region)
let inside = try await client.contains(coordinate: coordinate, in: region)
```

`query` 回傳內外判定與修訂版；`contains` 則是布林值便利方法。它們不考慮 GPS 精度及時間，因此不是已確認的定位判定。明確指定 ID 時，也可查詢停用的區域。區域識別由資料集 ID 與 feature ID 組成，不是顯示名稱。

## 距離區域或邊界多遠？

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

| 位置與支援狀態 | 至區域距離 | 至邊界距離 |
|---|---|---|
| 區域內，支援估算 | `0` | 最近邊界的近似距離 |
| 區域外，支援估算 | 最近邊界的近似距離 | 相同值 |
| 區域內，不支援估算 | `0` | `nil` |
| 區域外，不支援估算 | `nil` | `nil` |

有效的零距離不同於不支援估算。不要把缺少的區域外距離換成零。每個結果使用單一已提交快照，並附帶修訂版。

距離是以公尺表示的近似直線距離，不是步行或行車路線，也不包含 GPS 精度半徑。本地模型要求查詢緯度在 ±80° 內，所有頂點的緯度及展開經度與查詢點相差不超過一度。MultiPolygon 的遠端部分也可能讓估算不受支援；幾何內外判定仍可使用。

## evaluate 與 submit

搜尋、預覽與單點檢查使用 `evaluate`。實際監測輸入則須先啟動 `.hostProvided` 再呼叫 `submit`。後者會更新歷史、檢查樣本順序，並可能產生基準或跨界事件。
