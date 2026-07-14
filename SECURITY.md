# 安全说明

## 报告问题

如果发现脚本可能泄露 API Key、破坏 `config.toml`、修改错误文件、绕过唯一性检查或造成不可恢复的数据损坏，请不要公开敏感复现数据。请通过 GitHub Security Advisory 私下报告，并仅提供经过脱敏的日志和最小复现信息。

## 安全边界

- 工具不联网，也不会上传配置或文件。
- 工具只读取商店版 Codex，并修改 `%LOCALAPPDATA%\OpenAI\Codex-Fast` 中的副本。
- 工具会修改 `~/.codex/config.toml` 的根级 `service_tier`，修改前保存备份。
- 工具不会强制终止 Codex 进程，也不会自动删除补丁副本。
- 未支持版本的补丁目标不唯一或不存在时，安装会停止。

请勿在 Issue 中粘贴 API Key、完整配置、Cookie、令牌或账户信息。
