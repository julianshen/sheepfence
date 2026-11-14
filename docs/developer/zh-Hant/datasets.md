# 資料集指南

資料集是具有固定 ID 與單調遞增修訂版的完整 GeoJSON 快照，與 SDK 自身版本無關。

## 用地圖建立快照

[Fence Studio](editor.html) 支援多邊形、孔洞及 MultiPolygon。可連按兩下地點取得已標示的邊界，也可手動繪製及編輯。請參閱[編輯器指南](fence-editor.md)。

## 最小快照

將以下內容存為 `campus.geojson` 並加入 App bundle：

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

座標順序是**經度、緯度**。環必須閉合且幾何有效。支援 Polygon、MultiPolygon 與孔洞，不接受任意 GeoJSON 幾何。資料集及 feature ID 須為非空字串，同一資料集中的 feature ID 不可重複。修訂版須為正整數，`generatedAt` 須為以 `Z` 結尾的 RFC3339 UTC 時間。

`properties` 必須是物件。省略 `enabled` 時預設為 true，`priority` 為零，`name` 為 feature ID。[完整規格（英文）](https://github.com/julianshen/sheepfence/blob/main/geofence-sdk-spec-v0.3.md) 說明拓樸與邊界規則。

## 從檔案、HTTPS 或 Data 安裝

```swift
let result = try await client.installSnapshot(from: snapshotURL)
print(result.outcome, result.activeRevision)

// If your app handles authenticated networking itself:
let imported = try await client.installSnapshot(data: downloadedData)
```

SDK 的網路來源須為 HTTPS，重新導向會在跟隨前遭拒。標準限制為 5,000,000 bytes 與 30 秒傳輸逾時。本機檔案及 Data 也有大小上限。需要自訂驗證時，請由 App 下載後提供 Data。來源錯誤不會暴露 URL、憑證或原始網路錯誤。

## 修訂版與整體替換

| 輸入 | 結果 |
|---|---|
| 較新的修訂版 | 驗證後以交易方式替換整個資料集 |
| 相同修訂版、完全相同 bytes | `.unchanged` |
| 相同修訂版、不同 bytes | `revisionConflict` |
| 較舊修訂版 | `.olderVersionSkipped` |
| 無效或失敗更新 | 保留先前已提交資料 |

相同 bytes 不只是幾何等價。重新排版已發佈 JSON 也應遞增修訂版。替換時省略的 feature 會被移除；這不是局部更新 API。不同資料集 ID 互不取代。

提交開始前取消，不會發佈新快照。耐久提交開始後，即使收到取消，操作仍會完成並回傳實際結果。不要將所有取消都視為已回復原狀。

## 查詢目錄與刪除

```swift
let datasets = await client.datasets()
let regions = try await client.regions(in: "com.example.campus")
let removal = try await client.removeDataset(id: "com.example.campus")
print(removal.wasPresent, removal.removedRegionIDs)
```

刪除是持久化操作，並與安裝依序執行。刪除不存在的資料集不會造成變更。`.datasetRemoved` 不會產生退出事件。重新開啟用戶端會還原已提交資料，但不會還原位置歷史。

## 必要資料集

透過 `expectedDatasetIDs` 指定評估前必須存在的資料集。檢查 `state().readiness` 的 `.noDatasets`、`.missingRequired(...)` 或 `.ready`。必要資料缺少代表尚未就緒，不代表位於區域外。
