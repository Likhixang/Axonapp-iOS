# AxonHub Web 图标来源

- 官方部署版本：`v1.0.0-beta10`
- 上游 revision：`939b2bc07cc05bdf7750d7ec872290d67784d13d`
- 源路径：`frontend/public/logo.jpg`
- 官方引用：`frontend/src/features/auth/auth-layout.tsx` 的 `/logo.jpg`
- 本机实际资源：`http://127.0.0.1:8090/logo.jpg`
- SHA256：`0a2ab4a2bf6b0c028ba15f16be4dca90c9217a142ba1d101abf75812da54fc61`

上游与实际 Web 资源字节一致。AppIcon 仅进行 1024×1024 缩放；深色版本保留青绿色 AH 和圆环轮廓，把黑色圆弧换成白色并保留透明背景。不使用 unstable 分支的新四节点标志。

重新生成：安装 Pillow 后执行 `python3 scripts/generate-app-icons.py`。
