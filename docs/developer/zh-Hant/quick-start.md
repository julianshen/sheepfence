# 快速開始

開啟持久化用戶端、安裝快照，再評估位置。單次查詢不會啟動 GPS，也不會修改監測歷史。

## 1. 加入 Swift 套件

在 Xcode 選擇 **File → Add Package Dependencies**，輸入 `https://github.com/julianshen/sheepfence`，選擇 `main` 分支，並將 `SheepFence` 產品加入 App target。Swift 套件可使用：

```swift
.package(url: "https://github.com/julianshen/sheepfence", branch: "main")
```

在 target 相依項目加入 `.product(name: "SheepFence", package: "sheepfence")`。需要 Swift 6 與 iOS 16+。macOS 13+ 用於套件及引擎測試，不代表承諾支援 macOS 定位監測。需要可重現的預發佈整合時，請固定使用特定 commit。

## 2. 開啟並保留一個用戶端

將有效的 `campus.geojson` 加入 App bundle；[資料集指南](datasets.md) 提供範例。以下完整函式會建立 Application Support 儲存路徑並匯入快照：

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

在主 actor 的應用程式模型中保留用戶端。開啟時會還原已提交的資料集並建立缺少的父目錄。同一處理程序中，每個正規化 SQLite 路徑只能由一個存活用戶端持有。請跨畫面共用，並在 App 離開前景時停止監測。

60 秒只是定位有效期限的範例，請依產品需求設定。開啟用戶端不會顯示定位權限提示。

## 3. 評估定位

以下假設 `client` 已保留，且 `currentLocation` 是 App 提供的 `CLLocation`：

```swift
let batch = try await client.evaluate(location: currentLocation)
let matches = batch.results.filter {
    $0.observation == .confirmed(.inside)
}
for match in matches {
    print(match.regionID.datasetID, match.regionID.featureID)
}
```

可能同時符合多個區域。請分別處理 `.boundaryUncertain` 和 `.unavailable`，不要將它們顯示為區域外。可使用下列合成定位進行整合檢查：

```swift
let sample = LocationSample(
    coordinate: Coordinate(longitude: 10.003, latitude: 20.002),
    timestamp: Date(),
    horizontalAccuracy: 5
)
let batch = try await client.evaluate(location: sample)
```

這個手動樣本不是即時裝置定位的替代品。

## 4. 按需加入監測

需要持續觀測或進出事件時，請參閱[監測與 GPS](monitoring.md)。反覆呼叫純查詢 `evaluate` 不會產生跨界事件；請使用 `.hostProvided` 搭配 `submit`，或使用 `.sdkManaged`。

[前景範例 App（英文）](https://github.com/julianshen/sheepfence/tree/main/Examples/ForegroundHost) 提供模擬器、實機與效能測試的設定方式。
