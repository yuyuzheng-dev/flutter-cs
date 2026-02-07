class BootstrapConfig {
  /// 远程配置地址：内容可以是 JSON 或 base64(JSON)
  /// 例如：https://your-cdn.com/xboard/config.txt
  static const String remoteConfigUrl = 'https://raw.githubusercontent.com/fockau/flutter-cs/refs/heads/main/config.json';

  /// API 前缀（你要的 /api/v1）
  static const String apiPrefix = '/api/v1';

  /// 竞速探测超时（秒）
  static const int raceTimeoutSeconds = 6;

  /// 远程配置不可用时的兜底域名（可空）
  /// 注意：这里域名不要带 /api/v1
  static const List<String> fallbackDomains = <String>[
    // 'https://com.android22.com',
  ];
}
