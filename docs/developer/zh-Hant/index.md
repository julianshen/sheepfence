# 掌握位置，也掌握定位的不確定性。

SheepFence 是用於前景多邊形地理圍欄的 Swift SDK。匯入自己的 GeoJSON 區域，即可離線查詢位置，並接收已確認的進入與離開事件；GPS 無法使用時，不會被誤判為「區域外」。

**Swift 6 · iOS 16+ · Swift Package Manager · SDK 無第三方相依套件**

## 建立圍欄資料

使用 [Fence Studio](editor.html)，在 OpenStreetMap 上繪製、編輯區域，或連按兩下已標示的地點以取得邊界，再匯出 SheepFence GeoJSON 快照。不需要帳號或 API 金鑰。

## 開始開發

- [快速開始](quick-start.md)：安裝套件並評估第一筆位置。
- [位置查詢與距離](queries.md)：找出符合的區域並計算至邊界的距離。
- [監測與 GPS](monitoring.md)：整合前景定位來源、事件與 GPS 中斷處理。
- [Fence Studio 指南](fence-editor.md)：繪製、匯入與匯出多邊形。
- [資料集指南](datasets.md)：建立及更新 GeoJSON 快照。
- [API 指南](api.md)：選擇正確的方法與設定。
- [疑難排解](troubleshooting.md)：診斷定位、匯入及訂閱問題。
- [參與開發](contributing.md)：建置、測試與維護文件。

## 選擇操作

| 需求 | API |
|---|---|
| 這筆 GPS 定位在哪些區域內？ | `evaluate(location:)` |
| 座標是否位於指定區域？ | `query(coordinate:in:)` |
| 座標距離區域有多遠？ | `distance(from:to:)` |
| 使用自己的定位來源追蹤跨界 | `.hostProvided` 搭配 `submit(location:)` |
| 使用 SDK 的定位來源 | `startMonitoring(mode: .sdkManaged)` |
| 讀取目前狀態 | `state()` |
| 接收觀測與跨界事件 | `events()` |

## 明確區分目前觀測與歷史

同一位置可以位於多個重疊區域。觀測會區分已確認、邊界不確定及位置不可用；結果也標示所用的資料集修訂版。定位中斷時，最後確認狀態只作為歷史保留，不會產生虛構的離開事件。

快照採交易式更新。遭拒的更新不會破壞已提交資料；幾何替換會重新建立基準，而不是當成使用者移動。

## 目前狀態

目前從 `main` 分支提供 SDK，尚未發佈版本標籤。已記錄的檢查點通過 25 個測試套件的 139 項測試、模擬器測試，以及 iPhone 冒煙測試與 100 區域合成效能測試，並經 Codex、OpenCode、pi 交叉審查。這些是特定檢查點的結果，不是效能保證。

目前支援前景整合。真實路線精度、耗電校準及權限變更的實機驗收仍須另行完成。版本化發行前也須選定授權條款。

[驗證紀錄（英文）](https://github.com/julianshen/sheepfence/blob/main/docs/implementation/sdk-progress.md) · [原始碼](https://github.com/julianshen/sheepfence)
