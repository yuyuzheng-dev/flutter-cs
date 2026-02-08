import 'package:flutter/material.dart';

import 'app_storage.dart';
import 'auth_page.dart';
import 'home_page.dart';
import 'session_service.dart';
import 'xboard_api.dart';

class BootPage extends StatefulWidget {
  const BootPage({super.key});

  @override
  State<BootPage> createState() => _BootPageState();
}

class _BootPageState extends State<BootPage> {
  String status = '初始化…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 1) 立即决定去哪（不等网络）
    final loggedIn = SessionService.I.isLoggedIn;

    // 2) 先拿缓存订阅（主页秒展示）
    final cachedSub = AppStorage.I.getJson(AppStorage.kSubscribeCache);

    // 3) 立刻跳转 UI（减少“黑屏等待感”）
    if (!mounted) return;
    if (loggedIn) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomePage(initialSubscribeCache: cachedSub)),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthPage(force: true)),
      );
    }

    // 4) 后台刷新（不阻塞首屏）
    try {
      await XBoardApi.I.initResolveDomain();
      // 预热 guest config（认证页用）
      final gc = await XBoardApi.I.fetchGuestConfig();
      await AppStorage.I.setJson(AppStorage.kGuestConfigCache, gc.toJson());
    } catch (_) {
      // 后台失败不影响首屏
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F17),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flash_on, size: 56, color: Colors.white),
                const SizedBox(height: 12),
                const Text('King', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(status, style: TextStyle(color: Colors.white.withOpacity(0.7))),
                const SizedBox(height: 14),
                const SizedBox(width: 140, child: LinearProgressIndicator(minHeight: 3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
