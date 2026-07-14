# Codex Fast 一键配置（Windows 中转站版）

这个工具把 Codex 复制到用户可写目录，对副本中的 `app.asar` 应用等长补丁，并把桌面 `Codex` 快捷方式指向补丁后的真正主程序。原始 `WindowsApps` 安装不会被修改。

这是社区维护的非官方开源项目，与 OpenAI 无隶属或背书关系。仓库只包含脚本和文档，不分发 Codex Desktop 或 `app.asar`。

## 说明

本项目是非官方社区开源工具，与 OpenAI 不存在隶属、合作、授权或背书关系。使用者应自行判断并承担运行风险，遵守 OpenAI、API 中转服务及其他相关服务的条款和计费规则。

本项目只提供本地自动化脚本和说明文档，不提供、镜像、打包或分发 OpenAI Codex Desktop、`app.asar`、模型、API 服务、账户凭据或其他专有资源。脚本从使用者本人已安装的 Microsoft Store Codex 中读取文件，并只修改复制到用户目录的本地副本。

`OpenAI`、`Codex`、`ChatGPT` 及相关名称、商标、应用程序和资源的权利归其各自权利人所有。本仓库的 MIT License 只覆盖本项目原创脚本和文档，不授予任何 OpenAI 或第三方专有内容的权利。

- 社区：[LINUX DO](https://linux.do/)
- 原理参考：[Windows 端的 Codex Desktop 开启 Fast 模式](https://linux.do/t/topic/2305472)
- 原理参考：[Codex App 开启 Fast 模式（使用中转站的方案）](https://linux.do/t/topic/1782436)
- 相关开源项目：[Veath/codexfast](https://github.com/Veath/codexfast)（MIT，macOS 运行时补丁方案；与本项目实现路径不同）
- 维护、兼容适配和发布要求：[贡献指南](CONTRIBUTING.md)

如果权利人认为本项目中的内容存在署名遗漏、许可证不兼容、商标误用或其他侵权问题，请通过 GitHub Issue 或 Security Advisory 联系维护者，并提供可核验的权利说明和具体位置。维护者会及时核查，并视情况补充署名、修正文档或移除相关内容。本声明不构成法律意见，也不免除任何参与者依法合规使用软件和服务的责任。

## 使用方法

1. 解压整个 ZIP，不要只单独拖出一个文件。
2. 双击 `Install-CodexFast.cmd`。
3. 等待复制和补丁完成。首次安装需要约 2 GB 可用空间。
4. 如果 Codex 正在运行，按窗口提示完全退出 Codex；补丁版会自动打开。
5. 打开 Codex 设置，确认 `Speed` 中可以选择 `Standard / Fast`。

后续请使用桌面的 `Codex` 图标。开始菜单或旧任务栏固定项仍可能指向未修改的商店版；确认补丁版正常后，可以取消固定旧图标，再固定当前运行的 Codex。

## 工具做了什么

- 自动检测当前用户安装的 `OpenAI.Codex` 商店包。
- 复制完整应用到 `%LOCALAPPDATA%\OpenAI\Codex-Fast\<版本>\app`。
- 保留 `app.asar.original` 原始备份。
- 等长修改 hidden models、模型 allowlist、Fast UI gate、请求层 service tier gate。
- 把 `~/.codex/config.toml` 根级 `service_tier` 设置为 `"fast"`，修改前会备份配置。
- 把桌面 `Codex.lnk` 指向副本中的 `ChatGPT.exe`，而不是会跳回商店版的 `Codex.exe` 小型启动器。

脚本不联网，不读取或输出 API Key，也不需要管理员权限。

## 支持范围

补丁包内置了以下两套代码签名：

- 帖子中 `26.601.2237.0` 使用的旧签名。
- 已实际验证的 `26.707.9981.0` 签名。

同一套压缩代码签名可能覆盖相邻版本，但这不是保证。遇到新版 Codex 改变 bundle 结构时，安装器会报告 `not supported safely` 并停止，不会猜测位置或写入半套补丁。

Microsoft Store 更新后会产生新的版本目录，需要重新运行安装器。若新版本不受支持，应先分析新版四个 gate，再更新脚本签名。

## 恢复

双击 `Restore-CodexStore.cmd`：

- 恢复安装前保存的桌面商店版快捷方式。
- 把根级 `service_tier` 改回 `"default"`。
- 不自动删除约 2 GB 的副本，避免误删正在使用的文件；完全退出 Codex 后可手动删除 `%LOCALAPPDATA%\OpenAI\Codex-Fast`。

## 注意事项

- Fast 是否真正生效还取决于中转站是否接受并转发 Fast service tier。
- Fast 通常会增加额度消耗或计费，请自行确认中转站规则。
- 这是对 Codex Desktop 前端和请求 gate 的本地修改，并非 OpenAI 官方功能开关工具。
- 不建议直接改 `C:\Program Files\WindowsApps`：MSIX 权限、签名和完整性校验可能导致应用无法启动或被商店修复。

## 开源许可

本项目原创脚本和文档采用 [MIT License](LICENSE)。该许可证不适用于 OpenAI Codex Desktop、`app.asar`、模型服务或任何第三方专有组件。提交补丁前请阅读 [贡献指南](CONTRIBUTING.md)、[安全说明](SECURITY.md) 和 [项目声明](NOTICE.md)。

本项目参考了上方列出的社区文章和相关开源项目。除非具体文件另有明确说明，本仓库没有复制或重新分发 `Veath/codexfast` 的源代码；双方均采用 MIT License，但分别保留各自代码和文档的版权及署名。

参考文章：

- <https://linux.do/t/topic/2305472>
- <https://linux.do/t/topic/1782436>
