# OpenCV 頭文件找不到 - 詳細排查步驟

## 你已經確認：
✅ Headers 裡有這些 hpp 文件
✅ 已經添加了 Header Search Paths

但仍然找不到頭文件。以下是詳細的排查步驟：

## 步驟 1：檢查 Framework Search Paths（最重要！）

1. 打開 Xcode
2. 選擇項目（藍色圖標）→ **Build Settings**
3. 確保 **All** 和 **Combined** 都選中（不是 Basic）
4. 搜索 `Framework Search Paths`
5. **必須包含**：`$(PROJECT_DIR)` 或框架的實際路徑
6. 確保設置為 **recursive**（雙擊路徑，確認有 `/**` 或勾選 recursive）

## 步驟 2：檢查 Header Search Paths 格式

1. 在 Build Settings 中搜索 `Header Search Paths`
2. 應該包含：`$(PROJECT_DIR)/opencv2.framework/Headers`
3. **注意**：路徑末尾**不要**有 `/opencv2`，因為導入時已經有 `<opencv2/core.hpp>`
4. 確保設置為 **recursive**

## 步驟 3：確認框架在項目中

1. 在 Xcode 左側項目導航器中，應該能看到 `opencv2.framework`
2. 如果看不到，需要重新添加：
   - 右鍵項目 → **Add Files to "testMeasure"...**
   - 選擇 `opencv2.framework`
   - ✅ 勾選 **Copy items if needed**
   - ✅ 選擇 target: **testMeasure**

## 步驟 4：檢查 Build Phases

1. 選擇項目 → **Build Phases**
2. 展開 **Link Binary With Libraries**
3. 確認 `opencv2.framework` 在列表中
4. 如果沒有，點擊 `+` 添加

## 步驟 5：檢查框架的實際位置

在終端中執行（替換為你的實際路徑）：

```bash
# 檢查框架是否存在
ls -la /path/to/opencv2.framework/Headers/opencv2/core.hpp

# 檢查完整結構
find /path/to/opencv2.framework/Headers -name "*.hpp" | head -5
```

## 步驟 6：嘗試使用絕對路徑（臨時測試）

如果相對路徑不工作，可以臨時使用絕對路徑測試：

1. 在 Build Settings → `Header Search Paths`
2. 添加框架的**完整絕對路徑**，例如：
   - `/Users/YourName/Downloads/opencv2.framework/Headers`
   - 或 `C:\Users\YourName\Downloads\opencv2.framework\Headers`（Windows）

如果絕對路徑可以工作，說明相對路徑設置有問題。

## 步驟 7：清理並重建

1. **Product** → **Clean Build Folder** (Shift + Cmd + K)
2. 關閉 Xcode
3. 刪除 DerivedData：
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/testMeasure-*
   ```
4. 重新打開 Xcode
5. 重新編譯

## 步驟 8：檢查導入語句

確認 `OpenCVWrapper.mm` 中的導入語句是：
```cpp
#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>
#import <opencv2/imgcodecs.hpp>
```

**不是**：
- `#import "opencv2/core.hpp"`（不要用引號）
- `#import <opencv2/opencv2/core.hpp>`（不要重複 opencv2）

## 常見錯誤原因

1. **Framework Search Paths 沒有設置** - 這是最常見的原因
2. **路徑格式錯誤** - 應該用 `$(PROJECT_DIR)` 而不是硬編碼路徑
3. **沒有設置為 recursive** - 必須勾選 recursive
4. **框架沒有添加到項目** - 只在文件系統中存在是不夠的
5. **使用了錯誤的導入語法** - 應該用 `<>` 而不是 `""`

## 如果還是不行

請提供以下信息：
1. 錯誤的完整信息（截圖最好）
2. Framework Search Paths 的實際值
3. Header Search Paths 的實際值
4. 框架在項目中的位置（截圖）

