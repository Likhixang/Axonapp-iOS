# Axonhub App iOS

[English](README.md) | [简体中文](README.zh-CN.md) | **繁體中文** | [한국어](README.ko.md) | [日本語](README.ja.md)

面向 iPhone 和 iPad 的原生 [AxonHub](https://github.com/looplj/axonhub) 管理應用程式。在手機上查看閘道用量、管理渠道與模型、設定存取權限。

以 SwiftUI 打造，支援 iOS 16 以上系統，在 iOS 26 上呈現 Liquid Glass 介面。

## 介面預覽

<p align="center">
  <img src="docs/screenshots/zh-Hans-preview.png" width="900" alt="儀表板、渠道與模型">
</p>

## 核心功能

- **儀表板** — 請求、詞元、費用、成功率、每日趨勢與渠道效能。
- **渠道與模型** — 設定供應商、取得上游模型、測試連線、管理模型路由。
- **金鑰管理** — 建立與輪換金鑰，設定模型權限、渠道限制、策略與額度。
- **請求與用量** — 瀏覽請求、追蹤、對話及用量紀錄，查看延遲與詞元消耗。
- **管理功能** — 專案、成員、使用者、角色、提示詞防護、儲存與系統設定。
- **個人化設定** — 多實例切換、淺色與深色外觀、自訂強調色。
- **多語言介面** — 簡體中文、繁體中文、English、日本語、한국어。
- **直接連線與隱私** — 憑證儲存在本機 Keychain，預設使用 HTTPS，無中繼服務或分析 SDK。

## 下載與安裝

需要 **iOS / iPadOS 16.0 或更新版本**。

1. 從 [Releases](https://github.com/Likhixang/Axonhub-App-iOS/releases/latest) 下載 `Axonhub-App-iOS-unsigned.ipa`。
2. 使用 SideStore、AltStore 或自己的簽署憑證進行簽署安裝。
3. 開啟 **設定 → 新增實例**，填寫 AxonHub 位址並使用管理員帳號登入。一般 API Key 僅可查看可用模型清單。

## 本機建置

需要 **macOS、Xcode 26 和 XcodeGen**，無第三方執行階段相依套件。

```sh
brew install xcodegen
xcodegen generate
open Axonhub.xcodeproj
```

若要安裝至裝置，請在 Xcode 中選擇自己的簽署團隊並啟用程式碼簽署。
