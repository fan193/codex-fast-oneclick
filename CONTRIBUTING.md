# 贡献指南

欢迎提交 Issue 和 Pull Request，尤其是新版 Codex Desktop 更新后出现 `not supported safely` 时的新签名适配。

## 提交新版签名

请提供以下信息，但不要提交 API Key、完整 `config.toml`、账户信息或整个 `app.asar`：

- Codex Desktop 完整版本号。
- 四个 gate 所在 bundle 文件名。
- 每个原始目标字符串及其 UTF-8 字节长度。
- 等长替换字符串及其 UTF-8 字节长度。
- 原始字符串在该版本中唯一命中的验证结果。
- 修改后相关 JavaScript 文件的语法检查结果。

## 开发要求

- 不直接修改 `C:\Program Files\WindowsApps`。
- 所有补丁必须先验证唯一命中和等长，再统一写入副本。
- 未识别的新版本必须停止，不得使用模糊替换强行写入。
- 保持 Windows PowerShell 5.1 兼容，不引入 Node.js 等外部运行依赖。
- 不记录或输出用户的 API Key、中转地址和完整 Codex 配置。

## Pull Request

PR 请说明测试过的 Codex 版本、安装/恢复测试结果及可能的兼容性风险。只提交脚本、文档和测试信息，不提交 Codex 程序文件或其他专有资源。
