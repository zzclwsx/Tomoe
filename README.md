# 同映 Tomoe

<img src="assets/images/logo/logo_rounded.png" width="112" alt="同映双画面标识">

**基于 [Predidit/Kazumi](https://github.com/Predidit/Kazumi) 的非官方个人衍生版。**

首先感谢 **Predidit** 与 **Kazumi 的所有贡献者** 开放和维护这个项目。
本应用的基础架构、主要功能与绝大部分实现来自原项目；同映是在这些工作之上，
为个人与朋友的使用需求做的少量调整。请优先了解和支持原作：

- [Kazumi 原项目与完整介绍](https://github.com/Predidit/Kazumi)
- [Kazumi 官方网站](https://kazumi.app/)
- [原项目贡献者](https://github.com/Predidit/Kazumi/graphs/contributors)
- [上游公开规则仓库](https://github.com/Predidit/KazumiRules)

同映由本仓库维护者独立维护，**不是 Kazumi 官方版本，也不代表得到原作者的认可、合作或支持承诺**。
本分支的更新、使用问题和新增功能请在这里反馈，便于我们先行排查，避免给原项目增加维护负担。

## 本分支的调整

- 一起看房间贯穿应用运行期间，可在开始播放前创建或加入。
- 提供房主控制、全员控制两种模式；实际选片、选源、选集、播放和跳转操作参与同步。
- 普通心跳不再自动跳进度；可手动同步房间，或在房主控制模式下仅对齐自己的播放器。
- 个人退出播放不会退出房间，也不会暂停其他人的播放。
- 沿用上游规则 API 定义，目前支持 **API 9**，包含 API 搜索结果的详情地址模板。
- 应用使用同映自己的版本和 GitHub Releases；规则默认直接跟踪原作公开仓库。
- 房间会话期间暂缓远程规则更新，退出房间后可以重试。

我们没有维护独立规则仓库，也不承诺所有上游新规则能立即使用。
遇到需要更高 API 的规则时，会保留已有规则；收到反馈后再按需迁移上游能力、测试并发布新版。
API 检查通过也可能因站点变化而失败，欢迎附上规则名称、版本与复现步骤反馈。

### 搜索与规则

搜索页从 Bangumi 获取番剧条目；播放源规则用于进入详情后查找观看来源。
未配置镜像服务凭据的版本默认通过 ECH 访问 Bangumi 官方接口，也可在
“访问加速 → 番剧条目加速”中选择直连。旧版保存的默认/镜像设置会自动兼容，
无需重装规则；请求失败会显示重试入口，与真正没有匹配条目的情况区分。

在线弹幕需要本分支自己的弹弹play服务凭据。尚未配置的构建会明确提示原因；
缓存和本地弹幕导入仍可使用。维护者接入方式见[在线弹幕配置](static/doc/FORK_MAINTENANCE.md#在线弹幕配置可选)。

## 下载与更新

[同映 Releases](https://github.com/zzclwsx/Tomoe/releases) · [问题反馈](https://github.com/zzclwsx/Tomoe/issues)

- Windows：提供 x64 便携 ZIP，首次解压到自选目录后运行 `tomoe.exe`。从 1.0.4 起，内置更新器支持校验后原地替换并重启。
- Android：发布工作流支持 APK，在配置本仓库自己的固定签名后启用。
- 其他平台工程继承自上游，尚未完成本分支的发布验证。

应用名称、安装标识和 Windows 数据目录与原作区分。已有 Kazumi 数据请先在原应用导出，再按需导入同映。
本分支不会自动移动原作的数据。开发测试仍支持 `KAZUMI_TEST_INSTANCE` 隔离实例。

**1.0.2 / 1.0.3 用户需要先退出软件并手动解压覆盖到 1.0.4**，以后才能使用修复后的原地更新流程。1.0.0 / 1.0.1 用户请解压到空目录，避免旧素材残留。
程序原来放在 D 盘，后续仍更新到原目录；当前目录不可写时可选择空目录或已有同映目录。
设置与历史保留在原应用数据目录，番剧下载路径也不会因更新而改变。
详见 [Windows 更新说明](static/doc/WINDOWS_UPDATE.md)。

## 从源码运行

使用 `pubspec.yaml` 指定的 Flutter 版本（目前为 **3.47.6**）：

```sh
flutter pub get
flutter run -d windows
```

Windows 需要 Visual Studio 的“使用 C++ 的桌面开发”组件、Windows SDK、CMake 3.22 或更新版本及 Ninja。
请确保终端实际使用正确的工具链。Android 需要 JDK 17 与 Android SDK，NDK 版本见 Gradle 配置。

```sh
flutter analyze --no-fatal-infos --fatal-warnings
flutter test
flutter build windows --release
```

仍保留上游 Dart 包名 `kazumi` 与部分内部协议、类名，方便追踪和迁移原项目的改动。
部分服务可通过本地 `--dart-define` 配置；请勿提交访问凭据或签名文件。

## 维护与发布

- [本分支的更新与上游迁移说明](static/doc/FORK_MAINTENANCE.md)
- [一起看设计与测试说明](static/doc/WATCH_ROOM.md)
- 本仓库同时托管开发源码与软件发布，不另建分发仓库。
- 每个 Release 对应一个源码标签，可从该版本的 Source code 下载完整项目源码。

## 致谢与许可证

再次感谢 Predidit、Kazumi 贡献者及其依赖项目的作者。
从 1.0.2 起，本分支使用独立绘制的薄荷绿“双画面”标识（MIT）、Material Icons（Apache 2.0）
及 Noto Sans SC（SIL OFL 1.1）。不再打包 Kazumi 的人物图标及其平台衍生图片，
对原项目图标作者的历史致谢保留，并明确区分于本分支现用素材。
来源、许可、替换范围及可复现生成方式见[素材清单](static/doc/ASSET_PROVENANCE.md)。

本项目继续使用 [GNU GPL v3](LICENSE)。分发本分支时，请保留原有署名、许可证与变更说明，
提供对应版本的完整源码，并尊重接收者在许可证下修改和再分发的权利。
