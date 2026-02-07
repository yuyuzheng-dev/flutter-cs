import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_dialog.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'XBoard App',
      theme: ThemeData(useMaterial3: true),
      home: const Home(),
    );
  }
}

enum HttpMethod { get, post, put, delete }

String _normBaseUrl(String s) {
  s = s.trim();
  while (s.endsWith('/')) s = s.substring(0, s.length - 1);
  return s;
}

Uri _api(String baseUrl, String pathWithApiV1) {
  baseUrl = _normBaseUrl(baseUrl);
  if (!pathWithApiV1.startsWith('/')) pathWithApiV1 = '/$pathWithApiV1';
  return Uri.parse('$baseUrl$pathWithApiV1');
}

String _prettyJsonIfPossible(String body) {
  try {
    final j = jsonDecode(body);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(j);
  } catch (_) {
    return body;
  }
}

String _extractSubscribeUrl(dynamic j) {
  if (j is Map) {
    final data = j['data'];
    if (data is Map && data['subscribe_url'] != null) return '${data['subscribe_url']}';
  }
  return '';
}

String _extractSessionCookie(String? setCookie) {
  if (setCookie == null || setCookie.isEmpty) return '';
  final m = RegExp(r'(server_name_session=[^;]+)').firstMatch(setCookie);
  return m?.group(1) ?? '';
}

class Store {
  static const _kBaseUrl = 'base_url'; // 不带 /api/v1
  static const _kEmail = 'email';
  static const _kPassword = 'password'; // 你要求默认保存
  static const _kAuthData = 'auth_data'; // Bearer ...
  static const _kCookie = 'cookie'; // server_name_session=...
  static const _kSubscribeUrl = 'subscribe_url';

  static Future<SharedPreferences> _sp() => SharedPreferences.getInstance();

  static Future<void> saveAll({
    required String baseUrl,
    required String email,
    required String password,
    required String authData,
    required String cookie,
    required String subscribeUrl,
  }) async {
    final sp = await _sp();
    await sp.setString(_kBaseUrl, baseUrl);
    await sp.setString(_kEmail, email);
    await sp.setString(_kPassword, password);
    await sp.setString(_kAuthData, authData);
    await sp.setString(_kCookie, cookie);
    await sp.setString(_kSubscribeUrl, subscribeUrl);
  }

  static Future<String> baseUrl() async => (await _sp()).getString(_kBaseUrl) ?? '';
  static Future<String> email() async => (await _sp()).getString(_kEmail) ?? '';
  static Future<String> password() async => (await _sp()).getString(_kPassword) ?? '';
  static Future<String> authData() async => (await _sp()).getString(_kAuthData) ?? '';
  static Future<String> cookie() async => (await _sp()).getString(_kCookie) ?? '';
  static Future<String> subscribeUrl() async => (await _sp()).getString(_kSubscribeUrl) ?? '';

  static Future<void> clear() async {
    final sp = await _sp();
    await sp.remove(_kBaseUrl);
    await sp.remove(_kEmail);
    await sp.remove(_kPassword);
    await sp.remove(_kAuthData);
    await sp.remove(_kCookie);
    await sp.remove(_kSubscribeUrl);
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String baseUrl = '';
  String email = '';
  String password = '';
  String authData = '';
  String cookie = '';
  String subscribeUrl = '';

  bool loading = false;
  int? respStatus;
  String? respText;
  int lastFetchedAtMs = 0;

  // 自定义请求（默认不带 /api/v1）
  HttpMethod method = HttpMethod.get;
  final pathCtrl = TextEditingController(text: '/user/getSubscribe'); // 你说默认不带 api/v1
  final bodyCtrl = TextEditingController(text: '{\n  \n}');

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    pathCtrl.dispose();
    bodyCtrl.dispose();
    super.dispose();
  }

  String _fmtTime(int ms) {
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Future<void> _boot() async {
    baseUrl = await Store.baseUrl();
    email = await Store.email();
    password = await Store.password();
    authData = await Store.authData();
    cookie = await Store.cookie();
    subscribeUrl = await Store.subscribeUrl();
    setState(() {});

    // ✅ 自动登录：用保存的账号密码重新 login，然后拉最新订阅
    if (baseUrl.isNotEmpty && email.isNotEmpty && password.isNotEmpty) {
      await _autoLoginAndFetch();
    }
  }

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    if (authData.isNotEmpty) h['Authorization'] = authData;
    if (cookie.isNotEmpty) h['Cookie'] = cookie;
    return h;
  }

  Future<void> _autoLoginAndFetch() async {
    try {
      // 直接复用 auth_dialog 逻辑：走 login API
      await _loginWithSavedCreds(silent: true);
      await fetchSubscribe(showToast: false);
    } catch (_) {
      // 自动登录失败不弹，避免吵
    }
  }

  Future<void> _loginWithSavedCreds({required bool silent}) async {
    setState(() {
      loading = true;
      respStatus = null;
      respText = null;
    });
    try {
      final uri = _api(baseUrl, '/api/v1/passport/auth/login');
      final resp = await http
          .post(
            uri,
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 20));

      respStatus = resp.statusCode;
      respText = _prettyJsonIfPossible(resp.body);

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('登录失败：HTTP ${resp.statusCode}');
      }

      final j = jsonDecode(resp.body);
      final a = (j is Map) ? (j['data']?['auth_data']?.toString() ?? '') : '';
      if (a.isEmpty) throw Exception('登录成功但未返回 data.auth_data');

      authData = a;

      final c = _extractSessionCookie(resp.headers['set-cookie']);
      if (c.isNotEmpty) cookie = c;

      await Store.saveAll(
        baseUrl: baseUrl,
        email: email,
        password: password,
        authData: authData,
        cookie: cookie,
        subscribeUrl: subscribeUrl,
      );

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已自动登录')));
      }
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> openAuthDialog() async {
    final res = await XBoardAuthDialog.show(
      context,
      initialBaseUrl: baseUrl.isNotEmpty ? baseUrl : 'https://example.com',
      initialEmail: email,
      initialPassword: password,
    );

    if (res == null) return;

    baseUrl = res.baseUrl;
    email = res.email;
    password = res.password;
    authData = res.authData;
    cookie = res.cookie;

    // 保存（订阅先保留旧值，拉完再更新）
    await Store.saveAll(
      baseUrl: baseUrl,
      email: email,
      password: password,
      authData: authData,
      cookie: cookie,
      subscribeUrl: subscribeUrl,
    );

    setState(() {});
    await fetchSubscribe(showToast: true);
  }

  Future<void> fetchSubscribe({required bool showToast}) async {
    if (baseUrl.isEmpty || authData.isEmpty) return;

    setState(() {
      loading = true;
      respStatus = null;
      respText = null;
    });

    try {
      final resp = await http
          .get(_api(baseUrl, '/api/v1/user/getSubscribe'), headers: _headers())
          .timeout(const Duration(seconds: 15));

      respStatus = resp.statusCode;
      respText = _prettyJsonIfPossible(resp.body);

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('获取订阅失败：HTTP ${resp.statusCode}');
      }

      final j = jsonDecode(resp.body);
      final sub = _extractSubscribeUrl(j);
      if (sub.isNotEmpty) subscribeUrl = sub;

      final c = _extractSessionCookie(resp.headers['set-cookie']);
      if (c.isNotEmpty) cookie = c;

      lastFetchedAtMs = DateTime.now().millisecondsSinceEpoch;

      await Store.saveAll(
        baseUrl: baseUrl,
        email: email,
        password: password,
        authData: authData,
        cookie: cookie,
        subscribeUrl: subscribeUrl,
      );

      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已获取最新订阅')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('错误：$e')));
      }
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> callApi() async {
    if (baseUrl.isEmpty || authData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录')));
      return;
    }

    final path = pathCtrl.text.trim();
    if (path.isEmpty) return;

    // ✅ 你要求：自定义请求默认不带 /api/v1，所以这里自动补上
    final fullPath = path.startsWith('/api/v1') ? path : '/api/v1$path';

    setState(() {
      loading = true;
      respStatus = null;
      respText = null;
    });

    try {
      final uri = _api(baseUrl, fullPath);

      http.Response resp;
      switch (method) {
        case HttpMethod.get:
          resp = await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 20));
          break;
        case HttpMethod.delete:
          resp = await http.delete(uri, headers: _headers()).timeout(const Duration(seconds: 20));
          break;
        case HttpMethod.post:
          resp = await http
              .post(uri, headers: _headers(json: true), body: bodyCtrl.text.isEmpty ? '{}' : bodyCtrl.text)
              .timeout(const Duration(seconds: 20));
          break;
        case HttpMethod.put:
          resp = await http
              .put(uri, headers: _headers(json: true), body: bodyCtrl.text.isEmpty ? '{}' : bodyCtrl.text)
              .timeout(const Duration(seconds: 20));
          break;
      }

      respStatus = resp.statusCode;
      respText = _prettyJsonIfPossible(resp.body);

      // ✅ 如果请求的是 /user/getSubscribe（不带 api/v1）也同步订阅链接显示
      if (path.contains('/user/getSubscribe') && resp.statusCode >= 200 && resp.statusCode < 300) {
        try {
          final j = jsonDecode(resp.body);
          final sub = _extractSubscribeUrl(j);
          if (sub.isNotEmpty) {
            subscribeUrl = sub;
            lastFetchedAtMs = DateTime.now().millisecondsSinceEpoch;
            await Store.saveAll(
              baseUrl: baseUrl,
              email: email,
              password: password,
              authData: authData,
              cookie: cookie,
              subscribeUrl: subscribeUrl,
            );
          }
        } catch (_) {}
      }

      setState(() {});
    } catch (e) {
      setState(() => respText = 'Exception: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> copySubscribe() async {
    if (subscribeUrl.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: subscribeUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制订阅链接')));
  }

  Future<void> clearAll() async {
    await Store.clear();
    baseUrl = '';
    email = '';
    password = '';
    authData = '';
    cookie = '';
    subscribeUrl = '';
    respStatus = null;
    respText = null;
    lastFetchedAtMs = 0;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = authData.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('XBoard App'),
        actions: [
          IconButton(
            tooltip: '刷新订阅',
            onPressed: (!loggedIn || loading) ? null : () => fetchSubscribe(showToast: true),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'auth') await openAuthDialog();
              if (v == 'clear') await clearAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'auth', child: Text('登录/注册/忘记密码')),
              PopupMenuItem(value: 'clear', child: Text('清空本地数据')),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: ListTile(
                title: Text(loggedIn ? '已登录：$email' : '未登录'),
                subtitle: Text(baseUrl.isEmpty ? '面板域名未设置' : '面板域名：$baseUrl'),
                trailing: ElevatedButton(
                  onPressed: loading ? null : openAuthDialog,
                  child: const Text('认证'),
                ),
              ),
            ),
            const SizedBox(height: 12),

            const Text('订阅链接', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (subscribeUrl.isNotEmpty) ...[
              SelectableText(subscribeUrl),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: copySubscribe, child: const Text('复制订阅链接'))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (!loggedIn || loading) ? null : () => fetchSubscribe(showToast: true),
                      child: Text(loading ? '刷新中…' : '刷新订阅'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('最后刷新：${_fmtTime(lastFetchedAtMs)}', style: const TextStyle(color: Colors.black54)),
            ] else ...[
              const Text('暂无（登录后会自动获取最新 /api/v1/user/getSubscribe）'),
            ],

            const Divider(height: 28),

            const Text('自定义 API 请求', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                DropdownButton<HttpMethod>(
                  value: method,
                  onChanged: loading ? null : (v) => setState(() => method = v ?? HttpMethod.get),
                  items: const [
                    DropdownMenuItem(value: HttpMethod.get, child: Text('GET')),
                    DropdownMenuItem(value: HttpMethod.post, child: Text('POST')),
                    DropdownMenuItem(value: HttpMethod.put, child: Text('PUT')),
                    DropdownMenuItem(value: HttpMethod.delete, child: Text('DELETE')),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: pathCtrl,
                    decoration: const InputDecoration(
                      labelText: '路径（默认不写 /api/v1）',
                      hintText: '/user/getSubscribe',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (method == HttpMethod.post || method == HttpMethod.put) ...[
              TextField(
                controller: bodyCtrl,
                decoration: const InputDecoration(
                  labelText: 'JSON Body（POST/PUT 用）',
                  alignLabelWithHint: true,
                ),
                minLines: 6,
                maxLines: 12,
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: (!loggedIn || loading) ? null : callApi,
                child: Text(loading ? '请求中…' : '发送请求并输出返回'),
              ),
            ),

            const SizedBox(height: 16),
            if (respStatus != null) Text('HTTP Status: $respStatus', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (respText != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(respText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
