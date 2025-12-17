# 修復 OpenCV 鏈接錯誤

## 錯誤信息
```
Undefined symbol: MatToUIImage
Undefined symbol: UIImageToMat
Undefined symbol: cv::createLineSegmentDetector
Undefined symbol: cv::Mat::Mat()
... 等等
```

這些是**鏈接錯誤**，表示 OpenCV 框架沒有正確鏈接到項目。

## 解決步驟

### 步驟 1：確認 opencv2.framework 已添加到項目

1. 在 Xcode 左側項目導航器中，應該能看到 `opencv2.framework`
2. 如果看不到，需要添加：
   - 右鍵項目 → **Add Files to "testMeasure"...**
   - 選擇 `opencv2.framework`
   - ✅ 勾選 **Copy items if needed**
   - ✅ 選擇 target: **testMeasure**
   - 點擊 **Finish**

### 步驟 2：添加到 Link Binary With Libraries（最重要！）

1. 選擇項目（藍色圖標）→ **Build Phases**
2. 展開 **Link Binary With Libraries**
3. 檢查是否有 `opencv2.framework`
4. 如果沒有，點擊 `+` 按鈕
5. 搜索並添加 `opencv2.framework`
6. 確保狀態是 **Required**（不是 Optional）

### 步驟 3：添加 OpenCV 依賴的系統框架

OpenCV 需要以下系統框架，確保它們都在 "Link Binary With Libraries" 中：

1. **Accelerate.framework** - 用於高性能計算
2. **CoreMedia.framework** - 用於媒體處理
3. **AssetsLibrary.framework** - 用於資源庫（iOS 13+ 可能不需要）
4. **AVFoundation.framework** - 用於音視頻處理

添加方法：
- 在 **Link Binary With Libraries** 中點擊 `+`
- 搜索框架名稱
- 添加並確保狀態是 **Required**

### 步驟 4：檢查 Framework Search Paths

1. 選擇項目 → **Build Settings**
2. 搜索 `Framework Search Paths`
3. 確保包含：`$(PROJECT_DIR)` 或框架所在路徑
4. 確保設置為 **recursive**

### 步驟 5：檢查 Other Linker Flags（如果需要）

1. 在 Build Settings 中搜索 `Other Linker Flags` 或 `OTHER_LDFLAGS`
2. 通常不需要額外設置，但如果還有問題，可以嘗試添加：
   - `-framework opencv2`
   - `-lc++`（C++ 標準庫）

### 步驟 6：清理並重新編譯

1. **Product** → **Clean Build Folder** (Shift + Cmd + K)
2. 關閉 Xcode
3. 刪除 DerivedData：
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/testMeasure-*
   ```
4. 重新打開 Xcode
5. 重新編譯 (Cmd + B)

## 驗證

編譯成功後，鏈接錯誤應該消失。

## 常見問題

**Q: 框架已經在項目中，但還是鏈接錯誤**
- 確認框架已添加到 **Link Binary With Libraries**
- 確認 Framework Search Paths 設置正確
- 確認使用的是 iOS 版本的框架（不是 macOS）

**Q: 添加框架後編譯錯誤**
- 確認框架文件完整
- 確認框架版本與代碼兼容（OpenCV 4.12）

