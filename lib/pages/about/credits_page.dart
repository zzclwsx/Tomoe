import 'package:flutter/material.dart';

import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/content_section.dart';
import 'package:kazumi/pages/about/about_widgets.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/config/app_distribution.dart';

class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('致谢'),
    body: AboutContent(
      children: [
        ContentSection.group(
          title: '原作与贡献',
          children: const [
            AboutLinkTile(
              icon: Icons.favorite_outline_rounded,
              title: 'Predidit · Kazumi 原作者',
              subtitle: '感谢原作者开放源码，以及所有贡献者的工作',
              url: AppDistribution.upstreamSourceUrl,
            ),
            AboutLinkTile(
              icon: Icons.people_outline_rounded,
              title: 'Kazumi 原项目贡献者',
              url: '${AppDistribution.upstreamSourceUrl}/graphs/contributors',
            ),
            AboutLinkTile(
              icon: Icons.brush_rounded,
              title: 'Yuquanaaa · 原项目图标作者',
              subtitle: '本分支已替换该素材；此处仅保留对原项目贡献的致谢',
              url: ApiEndpoints.iconUrl,
            ),
          ],
        ),
        const SizedBox(height: 24),
        ContentSection.group(
          title: '视觉素材',
          children: const [
            AboutLinkTile(
              icon: Icons.filter_frames_rounded,
              title: '同映 · 双画面标识',
              subtitle: '本分支独立绘制的几何 SVG 与平台图标，MIT 许可',
              url:
                  '${AppDistribution.sourceUrl}/blob/main/static/doc/ASSET_PROVENANCE.md',
            ),
            AboutLinkTile(
              icon: Icons.font_download_outlined,
              title: 'Noto Sans SC',
              subtitle: 'Google Fonts · SIL Open Font License 1.1',
              url: 'https://github.com/google/fonts/tree/main/ofl/notosanssc',
            ),
            AboutLinkTile(
              icon: Icons.interests_outlined,
              title: 'Material Icons',
              subtitle: 'Google · Apache 2.0',
              url: 'https://github.com/google/material-design-icons',
            ),
          ],
        ),
        const SizedBox(height: 24),
        ContentSection.group(
          title: '服务',
          children: const [
            AboutLinkTile(
              icon: Icons.menu_book_rounded,
              title: 'Bangumi',
              subtitle: '番剧信息',
              url: ApiEndpoints.bangumiIndex,
            ),
            AboutLinkTile(
              icon: Icons.subtitles_rounded,
              title: '弹弹play',
              subtitle: '弹幕',
              url: ApiEndpoints.dandanIndex,
            ),
            AboutLinkTile(
              icon: Icons.image_search_rounded,
              title: 'trace.moe',
              subtitle: '以图搜番',
              url: 'https://trace.moe',
            ),
          ],
        ),
        const SizedBox(height: 24),
        ContentSection.group(
          title: '开源项目',
          children: const [
            AboutLinkTile(
              icon: Icons.flutter_dash_rounded,
              title: 'Flutter',
              subtitle: '应用框架',
              url: 'https://flutter.dev',
            ),
            AboutLinkTile(
              icon: Icons.play_circle_outline_rounded,
              title: 'media-kit',
              subtitle: '视频播放',
              url: 'https://github.com/media-kit/media-kit',
            ),
            AboutLinkTile(
              icon: Icons.auto_awesome_rounded,
              title: 'Anime4K',
              subtitle: '实时超分辨率',
              url: 'https://github.com/bloc97/Anime4K',
            ),
            AboutLinkTile(
              icon: Icons.sync_rounded,
              title: 'Syncplay',
              subtitle: '播放同步',
              url: 'https://github.com/Syncplay/syncplay',
            ),
            AboutLinkTile(
              icon: Icons.account_tree_rounded,
              title: 'XpathSelector',
              subtitle: 'XPath 解析',
              url: 'https://github.com/simonkimi/xpath_selector',
            ),
            AboutLinkTile(
              icon: Icons.video_settings_rounded,
              title: 'avbuild',
              subtitle: '非标准视频流支持',
              url: 'https://github.com/wang-bin/avbuild',
            ),
            AboutLinkTile(
              icon: Icons.storage_rounded,
              title: 'Hive CE',
              subtitle: '本地存储',
              url: 'https://github.com/IO-Design-Team/hive_ce',
            ),
          ],
        ),
      ],
    ),
  );
}
