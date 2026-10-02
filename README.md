# Axonhub App iOS

**English** | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md) | [한국어](README.ko.md) | [日本語](README.ja.md)

A native [AxonHub](https://github.com/looplj/axonhub) management app for iPhone and iPad. Check gateway usage, manage channels and models, and control access from your device.

Built with SwiftUI. Supports iOS 16 and later, with Liquid Glass on iOS 26.

## Preview

<p align="center">
  <img src="docs/screenshots/en-preview.png" width="900" alt="Dashboard, channels, and models">
</p>

## Features

- **Dashboard** — Requests, tokens, costs, success rates, daily trends, and channel performance.
- **Channels & models** — Configure providers, fetch upstream models, test connectivity, and manage model routing.
- **API keys** — Create and rotate keys; configure model access, channel restrictions, policies, and quotas.
- **Requests & usage** — Browse requests, traces, conversations, and usage records; inspect latency and token consumption.
- **Administration** — Manage projects, members, users, roles, prompt protection, storage, and system settings.
- **Personalization** — Multiple instances, light and dark appearance, and custom accent colors.
- **Multilingual** — Simplified Chinese, Traditional Chinese, English, Japanese, and Korean.
- **Direct connections** — Credentials stored in the iOS Keychain. HTTPS by default, with no relay service or analytics SDK.

## Installation

Requires **iOS / iPadOS 16.0 or later**.

1. Download `Axonhub-App-iOS-unsigned.ipa` from [Releases](https://github.com/Likhixang/Axonhub-App-iOS/releases/latest).
2. Sign and install it with SideStore, AltStore, or your own signing certificate.
3. Open **Settings → Add instance**, enter your AxonHub address, and sign in with an administrator account. Ordinary API keys only provide access to the available model list.

## Build

Requires **macOS, Xcode 26, and XcodeGen**. No third-party runtime dependencies.

```sh
brew install xcodegen
xcodegen generate
open Axonhub.xcodeproj
```

To install a local build on a device, select your signing team and enable code signing in Xcode.
