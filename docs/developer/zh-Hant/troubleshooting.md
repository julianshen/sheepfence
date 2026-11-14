# 疑難排解

先呼叫 `await client.state()`，確認模式、資料集就緒狀態與位置可用性，再解讀區域結果。

| 狀況 | 處理方式 |
|---|---|
| `storeAlreadyOpen` | 重用既有客戶端。符號連結仍指向同一儲存區；待完成作業可能持有租用權。 |
| `datasetNotReady` | 安裝所有必要資料集並檢查 `state().readiness`。 |
| `evaluate` 沒有進入事件 | 此 API 不改變狀態。使用已啟動的 `.hostProvided` 加 `submit`，或 `.sdkManaged`。 |
| `monitoringNotStarted` | 提交定位前先啟動主程式提供位置的監控。 |
| `sourceModeConflict` | 切換模式前先停止；SDK 管理模式不可提交主程式定位。 |
| `regionNotFound` | 檢查 `RegionID` 的兩個識別碼，以及區域是否已被新版快照移除。 |
| `boundaryUncertain` | 精度加緩衝距離不足以確認位於哪一側；不可視為在外部。 |
| `.unavailable(.staleLocation)` | 提供時間戳記新鮮的位置，並檢查最大位置年齡。 |
| `.unavailable(.outOfOrderLocation)` | 依時間順序提交位置。 |
| 沒有邊界距離 | 檢查 `.unsupported`；幾何可能超出局部距離模型。 |
| `eventBufferOverflow` | 重新訂閱取得目前狀態、減少事件處理工作，或適度增加緩衝區。遺漏事件不會重播。 |

## 來源與匯入錯誤

依 `GeofenceError.sourceFailed` 的 `SourceFailure` 處理：`unsupportedScheme`、`httpStatus`、`timeout`、`byteLimitExceeded`、`redirectRejected`、`network` 或 `fileRead`。只依應用程式策略重試暫時性錯誤，不要反覆重試無效幾何或不支援的通訊協定。SDK 錯誤不包含原始 URL、憑證或傳輸錯誤。

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

利用診斷中的路徑與區域 ID 修正資料產生端。同修訂版衝突表示該版號收到不同位元組；發布替換資料時應增加版號，並在伺服器與發布流程保留可用的舊快照。

## 權限與 GPS

SDK 無法繞過主程式授權。檢查用途說明、權限流程與裝置定位服務。拒絕權限、停用服務或暫時沒有定位代表位置不可用，不是離開區域。降低精度另行回報，可能擴大邊界不確定範圍。

不保證背景執行或自動要求權限。合成定位與效能測試不能驗證真實 GPS 路線；請在實機測試前景切換、授權變更及降低精度。

## 回報問題

請提供 SDK 提交版本、系統／裝置、模式、去識別化設定、預期行為及最小合成快照與定位。避免提供真實移動軌跡或含驗證資訊的 URL。使用 [GitHub Issues](https://github.com/julianshen/sheepfence/issues)。
