# 修復 OpenCV Stitching 模組衝突

## 錯誤信息
```
blenders - Expected identifier
exposure_compensate - Expected identifier
seam_finders - Expected identifier
```

這些錯誤是因為 OpenCV 的 stitching 模組使用了與 Objective-C 衝突的關鍵字。

## 解決方案：在 Build Settings 中添加預處理器宏

### 步驟：

1. **打開 Xcode**
2. **選擇項目**（藍色圖標）→ **Build Settings**
3. **確保選擇 "All" 和 "Combined"**
4. **搜索** `Preprocessor Macros` 或 `GCC_PREPROCESSOR_DEFINITIONS`
5. **展開該設置**
6. **在 Debug 和 Release 配置中都添加**：
   ```
   HAVE_OPENCV_STITCHING=0
   ```
   或者：
   ```
   OPENCV_DISABLE_STITCHING=1
   ```

### 具體操作：

1. 找到 `Preprocessor Macros` 或 `GCC_PREPROCESSOR_DEFINITIONS`
2. 雙擊右側的值（可能是 `$(inherited)`）
3. 點擊 `+` 添加新值
4. 輸入：`HAVE_OPENCV_STITCHING=0`
5. 對 Debug 和 Release 都執行相同操作

### 替代方法：在代碼中定義（已實現）

代碼中已經在導入 OpenCV 之前定義了：
```cpp
#define HAVE_OPENCV_STITCHING 0
```

但如果還是有問題，請在 Build Settings 中也添加。

## 驗證

添加後，清理並重新編譯：
1. **Product** → **Clean Build Folder** (Shift + Cmd + K)
2. 重新編譯 (Cmd + B)

錯誤應該會消失。

