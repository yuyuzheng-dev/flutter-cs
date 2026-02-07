import 'dart:convert';
import 'package:http/http.dart' as http;

/// 远程 config.json：可明文 JSON，也可 base64(JSON)
///
/// JSON 示例：
/// {
///   "api_prefix": "/api/v1",
///   "domains": ["https://a.com", "https://b.com"],
///   "support_url": "https://t.me/xxx",
///   "website_url": "https://example.com"
/// }
class ConfigManager {
  static final ConfigManager I = ConfigManager._();
  ConfigManager._();

  // ===== 只改这里：你的远程 config 地址 =====
  static const String remoteConfigUrl = 'https://raw.githubusercontent.com/fockau/flutter-cs/refs/heads/main/config.json';
  // =======================================

  String apiPrefix = '/api/v1';
  String apiBaseUrl = '';
  String supportUrl = '';
  String websiteUrl = '';
  bool ready = false;

  Uri api(String pathUnderApiV1) {
    var p = pathUnderApiV1.trim();
    if (!p.startsWith('/')) p = '/$p';
    return Uri.parse('$apiBaseUrl$apiPrefix$p');
  }

  Future<Map<String, dynamic>> _loadRemoteConfig() async {
    final resp = await http.get(Uri.parse(remoteConfigUrl)).timeout(const Duration(seconds: 12));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('远程 config HTTP ${resp.statusCode}');
    }

    final body = resp.body.trim();

    // JSON 明文
    if (body.startsWith('{') && body.endsWith('}')) {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic>) return j;
      throw Exception('config.json 不是对象');
    }

    // base64(JSON)
    final decoded = utf8.decode(base64Decode(body));
    final j = jsonDecode(decoded);
    if (j is Map<String, dynamic>) return j;
    throw Exception('base64 config 不是对象');
  }

  Future<void> refreshRemoteConfigAndRace() async {
    final cfg = await _loadRemoteConfig();

    apiPrefix = (cfg['api_prefix'] ?? '/api/v1').toString().trim();
    if (apiPrefix.isEmpty) apiPrefix = '/api/v1';

    supportUrl = (cfg['support_url'] ?? '').toString().trim();
    websiteUrl = (cfg['website_url'] ?? '').toString().trim();

    final rawDomains = cfg['domains'];
    if (rawDomains is! List) throw Exception('config.domains 必须是数组');

    var domains = rawDomains.map((e) => e.toString().trim()).where((e) => e.startsWith('http')).toList();
    domains = domains.toSet().toList();
    if (domains.isEmpty) throw Exception('config.domains 为空');

    final results = await Future.wait(domains.map(_probe), eagerError: false);
    final ok = results.where((r) => r.ok).toList()..sort((a, b) => a.ms.compareTo(b.ms));
    if (ok.isEmpty) throw Exception('所有域名探测失败');

    apiBaseUrl = ok.first.domain;
    ready = true;
  }

  Future<_ProbeResult> _probe(String domain) async {
    final sw = Stopwatch()..start();
    try {
      final u = Uri.parse('$domain$apiPrefix/guest/comm/config');
      final resp = await http.get(u, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 5));
      sw.stop();

      if (resp.statusCode != 200) return _ProbeResult(domain: domain, ok: false, ms: sw.elapsedMilliseconds);

      final j = jsonDecode(resp.body);
      if (j is Map && j['status']?.toString() == 'success') {
        return _ProbeResult(domain: domain, ok: true, ms: sw.elapsedMilliseconds);
      }
      return _ProbeResult(domain: domain, ok: false, ms: sw.elapsedMilliseconds);
    } catch (_) {
      sw.stop();
      return _ProbeResult(domain: domain, ok: false, ms: sw.elapsedMilliseconds);
    }
  }
}

class _ProbeResult {
  final String domain;
  final bool ok;
  final int ms;
  _ProbeResult({required this.domain, required this.ok, required this.ms});
}
