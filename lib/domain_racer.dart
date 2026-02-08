import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'app_storage.dart';
import 'config_manager.dart';

class DomainRacerResult {
  final RemoteConfigData config;
  final String baseUrl; // 最终选中的域名（不含 apiPrefix）
  DomainRacerResult({required this.config, required this.baseUrl});
}

class DomainRacer {
  static final DomainRacer I = DomainRacer._();
  DomainRacer._();

  // 保守值（你要改也只改这里）
  static const int maxConcurrency = 4;
  static const Duration probeTimeout = Duration(milliseconds: 1500);
  static const Duration fetchRemoteTimeout = Duration(seconds: 6);

  Future<DomainRacerResult> resolve() async {
    // 1) 优先加载远程 config；失败则用缓存 config
    RemoteConfigData cfg;
    try {
      cfg = await ConfigManager.I.fetchRemoteConfig(timeout: fetchRemoteTimeout);
      await AppStorage.I.setJson(AppStorage.kRemoteConfigCache, cfg.toJson());
    } catch (_) {
      final cached = AppStorage.I.getJson(AppStorage.kRemoteConfigCache);
      if (cached == null) rethrow;
      cfg = RemoteConfigData.fromJson(cached);
    }

    if (cfg.domains.isEmpty) throw Exception('config.domains empty');

    // 2) 优先尝试 bestDomain（避免每次都竞速）
    final best = AppStorage.I.getString(AppStorage.kBestDomain).trim();
    if (best.isNotEmpty && cfg.domains.contains(best)) {
      final ok = await _probe(best, cfg.apiPrefix);
      if (ok) return DomainRacerResult(config: cfg, baseUrl: best);
    }

    // 3) 竞速（并发最多4）
    final domains = cfg.domains.toList();
    final winner = await _race(domains, cfg.apiPrefix);
    if (winner == null) throw Exception('all domains probe failed');

    await AppStorage.I.setString(AppStorage.kBestDomain, winner);
    await AppStorage.I.setInt(AppStorage.kBestDomainTs, DateTime.now().millisecondsSinceEpoch);

    return DomainRacerResult(config: cfg, baseUrl: winner);
  }

  Future<bool> _probe(String domain, String apiPrefix) async {
    try {
      final u = Uri.parse('$domain$apiPrefix/guest/comm/config');
      final resp = await http.get(u, headers: const {'Accept': 'application/json'}).timeout(probeTimeout);
      if (resp.statusCode != 200) return false;
      final j = jsonDecode(resp.body);
      return (j is Map) && (j['status']?.toString() == 'success');
    } catch (_) {
      return false;
    }
  }

  Future<String?> _race(List<String> domains, String apiPrefix) async {
    final queue = List<String>.from(domains);
    final completer = Completer<String?>();
    int running = 0;
    bool decided = false;

    Future<void> runNext() async {
      if (decided) return;
      if (queue.isEmpty) {
        if (running == 0 && !completer.isCompleted) completer.complete(null);
        return;
      }
      final d = queue.removeAt(0);
      running++;

      () async {
        final ok = await _probe(d, apiPrefix);
        if (!decided && ok) {
          decided = true;
          if (!completer.isCompleted) completer.complete(d);
        }
      }().whenComplete(() {
        running--;
        if (!decided) {
          runNext();
          if (queue.isEmpty && running == 0 && !completer.isCompleted) completer.complete(null);
        }
      });
    }

    final start = (domains.length < maxConcurrency) ? domains.length : maxConcurrency;
    for (int i = 0; i < start; i++) {
      await runNext();
    }

    return completer.future;
  }
}
