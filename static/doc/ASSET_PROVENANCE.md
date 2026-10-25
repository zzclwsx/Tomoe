# 同映视觉素材与来源

## 为什么替换

[Kazumi 的美术资源说明](https://github.com/Predidit/Kazumi#美术资源)明确区分了代码许可和人物图标授权。
人物图标属于 Yuquanaaa；上游获得的项目内使用授权，不能当作本分支已获得再分发许可。
本分支没有取得该人物图标的额外授权，因此从 1.0.2 起不再在当前源码树和新发行包中打包该素材。
对原作者、贡献者及图标作者的致谢保留，不以更换素材为由删除原项目署名。

## 现用资源

| 资源 | 来源与许可 | 当前处理 |
| --- | --- | --- |
| 应用、托盘、各平台图标与启动图 | 本分支独立绘制的几何 SVG；MIT | `assets/brand/tomoe-mark.svg` 为源文件，由脚本统一导出 |
| 头像、封面占位和播放器按钮 | Google Material Icons；Apache 2.0 | 使用 Flutter 自带 Material 字形，保留动态主题色 |
| Android 画中画按钮 | 本分支独立绘制的简单几何矢量；MIT | `android/app/src/main/res/drawable/ic_pip_*.xml` |
| 字体 | Google Fonts 的 Noto Sans SC；SIL OFL 1.1 | 使用未经修改的完整字体，随包提供许可证 |
| Anime4K 着色器 | bloc97；MIT | 保留 `assets/shaders/LICENSE` 和原有署名 |
| 原人物图标及其衍生平台图片 | Yuquanaaa，未获本分支额外授权 | 替换，不将项目 GPL 解释成其图标授权 |
| 原头像、封面占位和自定义播放器图片 | 当前仓库缺少独立来源／许可凭据 | 移除；不据此断言原作者没有使用许可 |
| MiSans | Xiaomi 独立字体许可 | 改用许可路径更明确的 OFL 字体，不再打包此文件 |
| 上游演示截图、未使用的下载徽章 | 可能含第三方作品或另有许可 | 从当前分支移除，原项目仍可通过上游链接了解 |

界面布局、圆角、间距、动画和主题机制继续沿用并致谢上游代码；不照搬人物形象、描摹其轮廓或仅为原图换色。
标识使用浅薄荷背景、两层画面与播放符号，保持与现有 Material 界面的关系。

## 固定来源

- Noto Sans SC 来自 [`google/fonts`](https://github.com/google/fonts/tree/e7db6ca603fd4862010383ff17ffd6cc4ffac1c0/ofl/notosanssc)，提交 `e7db6ca603fd4862010383ff17ffd6cc4ffac1c0`。
- 原文件 `NotoSansSC[wght].ttf` 保存为 `assets/fonts/NotoSansSC.ttf`，仅修改文件名，未修改字形或字体内部名称。
- 字体 SHA-256：`a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da`。
- OFL 原文保存在 `licenses/fonts/OFL-NotoSansSC.txt`。[官方许可](https://github.com/google/fonts/blob/e7db6ca603fd4862010383ff17ffd6cc4ffac1c0/ofl/notosanssc/OFL.txt)允许随软件嵌入及再分发，须保留版权和许可等条件。
- Material 图标许可来自 [`google/material-design-icons`](https://github.com/google/material-design-icons/blob/10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7/LICENSE)，提交 `10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7`，原文保存在 `licenses/material-icons/LICENSE`。
- 独立 SVG、平台导出图标和画中画矢量的 MIT 许可在 `licenses/tomoe-art/LICENSE`。
- 上述许可随应用资源打包，在“关于 → 许可证”可查看；“关于 → 致谢”区分本分支现用资源和原项目历史贡献。

## 生成与迁移

使用项目指定的 Flutter SDK：

```sh
flutter test tool/generate_brand_assets.dart
python tool/audit_visual_assets.py
```

生成器只从本分支 SVG 源文件生成图片，不读取或变换旧人物图像。Windows ICO 包含 16 至 256 像素多个尺寸；
iOS 图标使用不透明背景，Android 自适应前景留出安全区域。未发布平台的生成资源不代表完成这些平台的发行验证。
迁移上游时保留此边界检查，避免旧图标、字体或占位图被重新带回。

## 历史版本与范围

1.0.0 / 1.0.1 的二进制包包含旧素材；在 1.0.2 发布并验证后下架这些二进制及校验附件，保留原因说明。
源码标签、Git 历史及上游历史保留，其中仍能找到过去版本的素材；这不构成对其重新授权。
若需彻底处理历史源码中的素材，应另行取得授权或规划历史归档，不能把删除当前文件等同于已清除所有历史副本。

番剧封面、用户头像、弹幕等运行时联网内容来自各自服务，未转为本分支自有素材；不将应用代码许可扩大到这些内容。
