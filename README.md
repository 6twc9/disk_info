# DiskInfo — macOS 磁碟空間視覺化分析工具 (DaisyDisk 風格)

一款專為 macOS 打造的原生 SwiftUI 磁碟空間分析與清理工具，參考 **DaisyDisk** 的互動式太陽爆發圖 (Sunburst Chart) 與收集籃 (Collector) 設計，幫助您快速找出 Mac 上哪個資料夾佔據最多空間。

## ✨ 核心特色

1. **多線程極速 POSIX 掃描引擎 ([`FastDiskScanner`](Sources/DiskInfo/DiskScanner.swift))**
   - 直接採用底層 Darwin `opendir` / `readdir` / `lstat` 與 GCD 多核平行佇列，避開高層級物件開銷。
   - 採用實際磁碟配置區塊 (`st_blocks * 512`) 計算空間，避免雲端佔位檔或稀疏檔案 (Sparse Files) 誤報容量。
   - 掃描根目錄 (`/`) 時自動過濾虛擬掛載與重複的 Firmlink (`/System/Volumes/Data`、`/Volumes` 等)，不重複計算外接硬碟。
2. **雙模式互動視覺化圖表**
   - **太陽爆發圖 ([`SunburstChartView`](Sources/DiskInfo/SunburstChartView.swift))**：支援 5 層同心圓環色彩家族渲染、滑鼠懸停即時預覽、點擊扇形向下鑽取 (Drill-down)、點擊中心圓盤返回上層。
   - **樹狀矩形圖 ([`TreemapChartView`](Sources/DiskInfo/TreemapChartView.swift))**：以面積比例分割方塊，直觀對比大型資料夾與單一巨型檔案。
3. **清理收集籃 (Collector)**
   - 支援將多個不同路徑的肥大資料夾或快取先加入底部「收集籃」，即時統計預計可釋放的總空間，確認無誤後一鍵安全移至 macOS 垃圾桶，並即時更新圖表。
4. **Finder 與終端機深度整合**
   - 右鍵選單與快捷按鈕支援「在 Finder 中顯示 (Reveal in Finder)」、「在終端機開啟 (Open in Terminal)」、「複製完整路徑」以及「完整磁碟取用權限 (Full Disk Access)」快速引導。

---

## 🚀 編譯與執行方式

在終端機進入 `/Volumes/owc/develop/disk_info` 目錄後：

### 方式一：一鍵打包成 `.app` 並啟動（推薦）
```bash
cd /Volumes/owc/develop/disk_info
chmod +x build_app.sh
./build_app.sh --run
```
執行後會在目錄下產生 **`DiskInfo.app`**，可直接拖入 `/Applications` 或雙擊開啟。

### 方式二：使用 Swift Package Manager 直接執行
```bash
cd /Volumes/owc/develop/disk_info
swift run -c release
```
