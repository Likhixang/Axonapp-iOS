# AxonHub for iOS

一个原生 SwiftUI 客户端，用来管理自建的 [AxonHub](https://github.com/looplj/axonhub) AI 网关。
所有接口都按上游源码实现：`/admin/auth/*`、`/admin/graphql`、`/admin/playground/chat`、`/health`。

## 功能

- **登录**：邮箱 + 密码（`POST /admin/auth/signin`），JWT 存在钥匙串，401 时自动调用 `/admin/auth/refresh` 续期；输入地址时实时检测服务器是否可达、是否已初始化。
- **概览**：请求数、Token、费用、成功率，按今天 / 本周 / 本月 / 全部切换；近期趋势图（请求 / Token / 费用）、热门模型、渠道成功率、吞吐最快的模型。
- **请求日志**：分页、按状态 / 来源 / 模型筛选、每 5 秒自动刷新；详情页有耗时、首 Token、用量与费用、每次上游重试（execution）的渠道和错误、请求 / 响应的头和体（可拷贝、分享）。
- **渠道**：列表、搜索、状态筛选；启用 / 停用 / 归档 / 删除；一键测试连通性；同步模型；恢复被自动停用的密钥；新建 / 编辑 API Key 类渠道（内置 60+ 供应商默认地址，可从上游拉取模型列表多选）。
- **模型**：搜索、启用 / 停用 / 删除，查看上下文、价格、能力。
- **API 密钥**：创建、拷贝、显示 / 隐藏、重命名、轮换、启用 / 停用 / 归档。
- **对话测试**：通过 `/admin/playground/chat` 流式对话，支持系统提示词、温度、最大输出、指定渠道，显示思考过程。
- **管理（所有者）**：用户启用 / 停用，项目创建 / 归档。
- **其他**：项目切换（`X-Project-ID`）、修改密码、服务器版本与健康状态、接入指南。

需要 iOS 17 或更新。

## 目录

```
Axon/
  App/          入口、会话状态
  Core/         HTTP / GraphQL 客户端、JSON、格式化、钥匙串
  Models/       与上游 schema 对应的数据类型
  Services/     GraphQL 查询与流式对话
  Features/     各个页面
  UI/           通用组件
Tests/          核心层单元测试（swift test）
project.yml     XcodeGen 工程定义
```

## 构建

GitHub Actions（`.github/workflows/build.yml`）在每次推送到 `main`、PR 和手动触发时运行：

1. `swift test` 跑核心层单元测试；
2. XcodeGen 生成工程，`xcodebuild` 以 Release 构建（不签名）；
3. 打包成 `AxonHub-<版本>-<构建号>-unsigned.ipa`，作为 artifact 上传；推送 `v*` 标签时同时发布到 Release。

本地构建：

```sh
brew install xcodegen
xcodegen generate
open Axon.xcodeproj
```

## 安装

CI 产出的 IPA **未签名**，需要用 AltStore / SideStore / Sideloadly / 全能签等工具用你自己的 Apple ID 或证书重签后安装。Bundle ID 为 `com.khixang.axon`，签名工具一般会自动改成你账号下可用的 ID。

应用允许 HTTP 连接，方便访问局域网或 Tailscale 内的服务器；公网部署建议使用 HTTPS。
