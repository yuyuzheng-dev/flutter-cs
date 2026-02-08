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
    final cachedLatency = AppStorage.I.getInt(AppStorage.kResolvedDomainLatency);

    if (!forceRefresh && cachedAt > 0 && cachedBase.isNotEmpty && (now - cachedAt) < cacheTtl.inMilliseconds) {
      return ResolvedDomain(baseUrl: cachedBase, config: config, latencyMs: cachedLatency);
    }

    final domains = config.domains.map(_normalizeBase).toList();
    final futures = domains.map((d) => _testLatencyMs(d, config.apiPrefix)).toList();
    final results = await Future.wait(futures);

    int bestIdx = -1;
    int bestLatency = 1 << 30;

    for (int i = 0; i < results.length; i++) {
      final ms = results[i];
      if (ms == null) continue;
      if (ms < bestLatency) {
        bestLatency = ms;
        bestIdx = i;
      }
    }

    if (bestIdx < 0) {
      throw Exception('所有域名联通测试失败');
    }

    final bestBase = domains[bestIdx];
    await AppStorage.I.setString(AppStorage.kResolvedDomainBase, bestBase);
    await AppStorage.I.setInt(AppStorage.kResolvedDomainLatency, bestLatency);
    await AppStorage.I.setInt(AppStorage.kResolvedDomainCachedAt, now);

    return ResolvedDomain(baseUrl: bestBase, config: config, latencyMs: bestLatency);
  }

  String _normalizeBase(String s) {
    var u = s.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  Future<int?> _testLatencyMs(String baseUrl, String apiPrefix) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse('$baseUrl$apiPrefix/guest/comm/config');
      final resp = await http.get(uri).timeout(testTimeout);
      if (resp.statusCode != 200) return null;

      final j = jsonDecode(resp.body);
      if (j is! Map) return null;

      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }
}
