/// This derivative's release channel is independent of the upstream rule API.
abstract final class AppDistribution {
  static const String appName = '同映';
  static const String productName = 'Tomoe';
  static const String repository = 'zzclwsx/Tomoe';
  static const String sourceUrl = 'https://github.com/$repository';
  static const String releasesUrl = '$sourceUrl/releases';
  static const String latestReleaseApi =
      'https://api.github.com/repos/$repository/releases/latest';

  static const String upstreamSourceUrl = 'https://github.com/Predidit/Kazumi';
  static const String upstreamProjectUrl = 'https://kazumi.app/';
  static const String upstreamRuleEngineCommit =
      '55e317e5f0c346d4318327ae0e5614eb8ee9097f';
}
