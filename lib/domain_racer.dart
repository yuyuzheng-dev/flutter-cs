import 'dart:convert';
import 'package:http/http.dart' as http;

import 'app_storage.dart';
import 'config_manager.dart';

class ResolvedDomain {
  final String baseUrl; // https://fastest.com
  final RemoteConfig config;
  final int latencyMs;

  const ResolvedDomain({required this.baseUrl, required this.config, required this.latencyMs});
}

class DomainRacer {
  static final DomainRacer I = DomainRacer._();
  DomainRacer._();

  static const Duration cacheTtl = Duration(minutes: 30);
  static const Duration testTimeout = Duration(seconds: 3);

  Future<ResolvedDomain> resolve(RemoteConfig config, {bool forceRefresh = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cachedAt = AppStorage.I.getInt(AppStorage.kResolvedDomainCachedAt);
    final cachedBase = AppStorage.I.getString(AppStorage.kResolvedDomainBase);

    if (!forceRefresh && cachedAt > 0 && cachedBase.isNotEmpty && (now - cachedAt) < cacheTtl.inMilliseconds) {
      return ResolvedDomain(baseUrl: cachedBase, config: config, latencyMs: AppStorage.I.getInt(AppStorage.kResolvedDomainLatency));
    }

    final domains = config.domains.map(_normalizeBase).toList();
    final futures = domains.map((d) => _testOne(d, config.apiPrefix)).toList();

    // 并发竞速：取最快成功
    ResolvedDomain? best;
    for (final f in futures) {
      // 不 await 单个，会影响并发。这里用 Future.any + 手动收集更复杂
      // 简化：全部 await 完再选最小（域名少时足够稳）
    }
    final results = await Future.wait(futures);

    for (final r in results) {
      if (r == null) continue;
      if (best == null || r.latencyMs < best.latencyMs) best = r;
    }

    if (best == null) {
      throw Exception('所有域名联通测试失败');
    }

    await AppStorage.I.setString(AppStorage.kResolvedDomainBase, best.baseUrl);
    await AppStorage.I.setInt(AppStorage.kResolvedDomainLatency, best.latencyMs);
    await AppStorage.I.setInt(AppStorage.kResolvedDomainCachedAt, now);
    return best;
  }

  String _normalizeBase(String s) {
    var u = s.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  Future<ResolvedDomain?> _testOne(String baseUrl, String apiPrefix) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse('$baseUrl$apiPrefix/guest/comm/config');
      final resp = await http.get(uri).timeout(testTimeout);
      if (resp.statusCode != 200) return null;

      final j = jsonDecode(resp.body);
      if (j is! Map) return null;

      sw.stop();
      return ResolvedDomain(baseUrl: baseUrl, config: RemoteConfig(apiPrefix: apiPrefix, domains: [], supportUrl: '', websiteUrl: ''), latencyMs: sw.elapsedMilliseconds);
    } catch (_) {
      return null;
    }
  }
}
