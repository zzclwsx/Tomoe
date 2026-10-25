# 同映维护说明

同映基于 Predidit/Kazumi 独立维护，感谢原作者和所有贡献者。
本仓库不是上游的官方发布渠道。本说明只描述本分支的维护方式。

## 三种版本分别管理

- 应用：`pubspec.yaml`，初始为 `1.0.0+10000`。Release 标签为 `v1.0.0`。
- 上游规则 API：`ApiEndpoints.apiLevel`，目前为 9；必须实现对应能力并测试后才能提高。
- 规则内容：保留上游单条规则的版本，客户端应用版本不参与规则兼容比较。

应用更新用 SemVer 比较，支持 `v` 前缀及预发布号；`+` 后的构建元数据不影响更新优先级。
每次希望客户端提示更新时，需要提高应用语义版本；Android 构建号也应递增。

## 发行配置

`lib/request/config/app_distribution.dart` 是本分支名称、仓库与更新地址的配置入口。
应用只检查本仓库 Releases，不回退到原作的软件更新源。
规则默认从 `Predidit/KazumiRules/main` 获取；GitHub 规则镜像为可选项，默认关闭。
若镜像内容滞后，先关闭规则加速后再确认规则版本。

Bangumi 条目接口与规则仓库是两套服务。缺少 `KAZUMI_APPID` / `KAZUMI_KEY` 时，
不能使用原镜像的受保护搜索与评论接口；本分支默认通过 ECH 访问官方公开接口。
旧版默认/镜像设置也会解析为 ECH，明确选择直连的设置则保留。

下载包保留 SHA-256 校验，使用 GitHub Release 资产返回的 `sha256:` digest。
工作流额外生成 `SHA256SUMS.txt` 供人工核对。不要通过跳过校验解决下载问题。

## 发布 Windows 便携版

1. 更新 `pubspec.yaml` 的应用版本与构建号。
2. 通过静态分析、测试及 Windows 构建，并在两台客户端验证一起看。
3. 提交源码，创建同名标签，例如 `v1.0.1`，推送到自己的 `origin`。
4. Release 工作流核对标签、构建 Windows ZIP、生成校验清单并发布至本仓库。

发布的是同映，原项目版权和历史应当保留。完整源码由同一仓库的版本标签提供。
Windows ZIP 首次仍需解压运行；从 1.0.2 起，客户端内置独立的更新助手，校验后原地替换并重启。
1.0.0 / 1.0.1 用户需先手动覆盖一次才能启用该流程。设计与验证见 [Windows 更新说明](WINDOWS_UPDATE.md)。
不要沿用上游 SignPath 身份或向其提交签名请求；本工作流不使用上游签名服务。

## 可选 Android 发布

正式 APK 必须使用自己长期保存的固定签名。配置仓库 Actions secrets：

- `ANDROID_KEYSTORE_BASE64`：JKS 文件的 Base64。
- `ANDROID_KEYSTORE_PASSWORD`：密钥库密码。
- `ANDROID_KEY_ALIAS`：密钥别名。
- `ANDROID_KEY_PASSWORD`：密钥密码。

设置仓库 Actions variable `ENABLE_ANDROID_RELEASE=true` 后，标签发布会额外生成通用 APK。
签名文件与 `android/key.properties` 已忽略；本地没有该配置时仍允许调试签名用于开发，
但工作流不会把缺少固定签名的 APK 当成正式版本发布。
本分支 applicationId 为 `io.github.zzclwsx.tomoe`，不能覆盖安装原作者签名的应用。
若配置弹幕等服务参数，应使用自己的服务配置；不要复制上游未公开的密钥。

## 在线弹幕配置（可选）

弹弹play 的搜索、自动匹配与在线弹幕需要本应用自己的 AppId/AppSecret，
申请入口和要求见[官方接入文档](https://doc.dandanplay.com/open/)。
在本仓库 Settings → Secrets and variables → Actions 中添加
`DANDANAPI_APPID`、`DANDANAPI_KEY`，后续标签构建会将它们传入 Windows 与 Android 应用。
没有配置时仍可构建，客户端会明确提示在线弹幕尚未配置；缓存及本地导入不受影响。
认证被拒绝时会提示维护者检查配置，不会误报成没有搜索结果。

本地开发可复制 `.kazumi_build_defines.example.env` 为被忽略的 `.kazumi_build_defines.env`，
填写自己的值，然后运行 `flutter run --dart-define-from-file=.kazumi_build_defines.env`。
不要把实际凭据提交到源码、日志或聊天。构建参数会进入客户端，不能视为服务端保密存储。
配置完需要重新构建应用，已安装的旧包不会自动获得凭据。

## 手动迁移上游

Git 约定：`origin` 指向本分支仓库，`upstream` 指向 `https://github.com/Predidit/Kazumi.git`。
保留原作提交历史；不要重写上游署名。
GitHub 上以公开 fork 标记来源；创建仓库时的原作主分支保存为 `upstream-main`，本分支的默认分支为 `main`。

本次规则引擎对照提交：`55e317e5f0c346d4318327ae0e5614eb8ee9097f`。
API 9 对应上游 `ff859472`：搜索结果可用 `sourceTemplate` 将裸 ID 转成详情地址。
模型、解析、编辑器、序列化已迁移；保留原有 API 8 及 XPath 行为。

朋友反馈后先区分：规则 API 高于客户端、站点/规则失效、本地解析缺陷或网络问题。
需要迁移时拉取 `upstream/main`，选择相关提交连同必要依赖一起核对；无需同步上游应用版本号。
测试通过后更新兼容级别与基线记录，再发布我们的客户端版本。

至少检查：旧 XPath、API 搜索与选集、模板编码、导入导出、不支持 API 时保留旧规则、
一起看选片/源/集/进度同步、两种控制模式、重连与个人退出播放。
房间内规则自动更新暂缓；退出房间后由使用者重试，不自动在后台替换规则。

## 问题反馈

请先在本仓库报告本分支的问题，并提供应用版本和规则 API、规则名称/版本、系统、复现步骤及必要日志。
房间密码、认证凭据等信息请从日志中移除。确认属于上游且有通用价值的修复，再整理为独立贡献。
