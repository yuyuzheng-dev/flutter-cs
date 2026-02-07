import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'XBoard API 工具',
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

String _prettyJsonIfPossible(String body) {
  try {
    final j = jsonDecode(body);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(j);
  } catch (_) {
    return body;
  }
}

/// 从登录返回里提取 auth_data：{data:{auth_data:"Bearer ..."}}
String _extractAuthData(dynamic loginJson) {
  if (loginJson is Map) {
    final data = loginJson['data'];
    if (data is Map && data['auth_data'] != null) return '${data['auth_data']}';
  }
  return '';
}

/// 从 getSubscribe 返回里提取 subscribe_url：{data:{subscribe_url:"..."}}
String _extractSubscribeUrl(dynamic j) {
  if (j is Map) {
    final data = j['data'];
    if (data is Map && data['subscribe_url'] != null) return '${data['subscribe_url']}';
  }
  return '';
}

/// 从 set-cookie 提取 server_name_session=...
String _extractSessionCookie(String? setCookie) {
  if (setCookie == null || setCookie.isEmpty) return '';
  final m = RegExp(r'(server_name_session=[^;]+)').firstMatch(setCookie);
  return m?.group(1) ?? '';
}

/// ==================== 历史登录数据模型 ====================
class LoginProfile {
  final String id; // baseUrl|email hash
  final String baseUrl;
  final String email;
  final String authData; // "Bearer xxxx"
  final String cookie; // server_name_session=...
  final String lastSubscribeUrl;
  final int savedAtMs;

  const LoginProfile({
    required this.id,
    required this.baseUrl,
    required this.email,
    required this.authData,
    required this.cookie,
    required this.lastSubscribeUrl,
    required this.savedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'baseUrl': baseUrl,
        'email': email,
        'authData': authData,
        'cookie': cookie,
        'lastSubscribeUrl': lastSubscribeUrl,
        'savedAtMs': savedAtMs,
      };

  static LoginProfile? fromJson(dynamic j) {
    if (j is! Map) return null;
    final id = (j['id'] ?? '').toString();
    final baseUrl = (j['baseUrl'] ?? '').toString();
    final email = (j['email'] ?? '').toString();
    final authData = (j['authData'] ?? '').toString();
    if (id.isEmpty || baseUrl.isEmpty || authData.isEmpty) return null;
    return LoginProfile(
      id: id,
      baseUrl: baseUrl,
      email: email,
      authData: authData,
      cookie: (j['cookie'] ?? '').toString(),
      lastSubscribeUrl: (j['lastSubscribeUrl'] ?? '').toString(),
      savedAtMs: int.tryParse((j['savedAtMs'] ?? '0').toString()) ?? 0,
    );
  }

  LoginProfile copyWith({
    String? cookie,
    String? lastSubscribeUrl,
    int? savedAtMs,
    String? authData,
  }) {
    return LoginProfile(
      id: id,
      baseUrl: baseUrl,
      email: email,
      authData: authData ?? this.authData,
      cookie: cookie ?? this.cookie,
      lastSubscribeUrl: lastSubscribeUrl ?? this.lastSubscribeUrl,
      savedAtMs: savedAtMs ?? this.savedAtMs,
    );
  }
}

String _makeProfileId(String baseUrl, String email) {
  final s = '${baseUrl.toLowerCase()}|${email.toLowerCase()}';
  return s.codeUnits.fold<int>(0, (a, b) => (a * 131 + b) & 0x7fffffff).toString();
}

/// ==================== 本地存储 ====================
class Store {
  static const _kCurrentBaseUrl = 'current_baseUrl';
  static const _kCurrentAuthData = 'current_authData';
  static const _kCurrentCookie = 'current_cookie';
  static const _kCurrentLastSubscribeUrl = 'current_lastSubscribeUrl';

  // ✅ 当前正在使用的历史 profile id（用于精准同步历史）
  static const _kCurrentProfileId = 'current_profile_id';

  static const _kProfiles = 'profiles_json'; // List<LoginProfile>

  static Future<SharedPreferences> _sp() => SharedPreferences.getInstance();

  static Future<void> saveCurrent({
    required String baseUrl,
    required String authData,
    required String cookie,
    required String lastSubscribeUrl,
  }) async {
    final sp = await _sp();
    await sp.setString(_kCurrentBaseUrl, baseUrl);
    await sp.setString(_kCurrentAuthData, authData);
    await sp.setString(_kCurrentCookie, cookie);
    await sp.setString(_kCurrentLastSubscribeUrl, lastSubscribeUrl);
  }

  static Future<String> getCurrentBaseUrl() async => (await _sp()).getString(_kCurrentBaseUrl) ?? '';
  static Future<String> getCurrentAuthData() async => (await _sp()).getString(_kCurrentAuthData) ?? '';
  static Future<String> getCurrentCookie() async => (await _sp()).getString(_kCurrentCookie) ?? '';
  static Future<String> getCurrentLastSubscribeUrl() async =>
      (await _sp()).getString(_kCurrentLastSubscribeUrl) ?? '';

  static Future<void> saveCurrentProfileId(String v) async => (await _sp()).setString(_kCurrentProfileId, v);
  static Future<String> getCurrentProfileId() async => (await _sp()).getString(_kCurrentProfileId) ?? '';

  static Future<List<LoginProfile>> loadProfiles() async {
    final sp = await _sp();
    final s = sp.getString(_kProfiles);
    if (s == null || s.isEmpty) return [];
    try {
      final j = jsonDecode(s);
      if (j is List) {
        final out = <LoginProfile>[];
        for (final it in j) {
          final p = LoginProfile.fromJson(it);
          if (p != null) out.add(p);
        }
        out.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
        return out;
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveProfiles(List<LoginProfile> profiles) async {
    final sp = await _sp();
    final list = profiles.map((e) => e.toJson()).toList();
    await sp.setString(_kProfiles, jsonEncode(list));
  }

  static Future<void> upsertProfile(LoginProfile p) async {
    final profiles = await loadProfiles();
    final idx = profiles.indexWhere((x) => x.id == p.id);
    if (idx >= 0) {
      profiles[idx] = p;
    } else {
      profiles.add(p);
    }
    profiles.sort((a, b) => b.savedAtMs.compareTo(a.savedAtMs));
    await saveProfiles(profiles);
  }

  static Future<void> deleteProfile(String id) async {
    final profiles = await loadProfiles();
    profiles.removeWhere((x) => x.id == id);
    await saveProfiles(profiles);

    final cur = await getCurrentProfileId();
    if (cur == id) {
      await saveCurrentProfileId('');
    }
  }

  static Future<void> clearProfiles() async {
    final sp = await _sp();
    await sp.remove(_kProfiles);
    await sp.remove(_kCurrentProfileId);
  }

  static Future<void> clearAll() async {
    final sp = await _sp();
    await sp.remove(_kCurrentBaseUrl);
    await sp.remove(_kCurrentAuthData);
    await sp.remove(_kCurrentCookie);
    await sp.remove(_kCurrentLastSubscribeUrl);
    await sp.remove(_kCurrentProfileId);
    await sp.remove(_kProfiles);
  }
}

/// ==================== UI 主页 ====================
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  // 登录区
  final baseUrlCtrl = TextEditingController(text: 'https://example.com');
  final emailCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();

  // 自定义请求区
  HttpMethod method = HttpMethod.get;
  final pathCtrl = TextEditingController(text: '/api/v1/user/getSubscribe');
  final bodyCtrl = TextEditingController(text: '{\n  \n}');

  bool loading = false;

  String? authData; // "Bearer xxx"
  String? cookie; // server_name_session=...
  String? lastSubscribeUrl;

  int? respStatus;
  String? respText;

  List<LoginProfile> profiles = [];

  int lastFetchedAtMs = 0;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  @override
  void dispose() {
    baseUrlCtrl.dispose();
    emailCtrl.dispose();
    pwdCtrl.dispose();
    pathCtrl.dispose();
    bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocal() async {
    final base = await Store.getCurrentBaseUrl();
    final a = await Store.getCurrentAuthData();
    final c = await Store.getCurrentCookie();
    final sub = await Store.getCurrentLastSubscribeUrl();
    final ps = await Store.loadProfiles();

    if (base.isNotEmpty) baseUrlCtrl.text = base;

    setState(() {
      authData = a.isEmpty ? null : a;
      cookie = c.isEmpty ? null : c;
      lastSubscribeUrl = sub.isEmpty ? null : sub;
      profiles = ps;
    });

    // 有 authData 就自动刷新一次订阅（确保是“最新”）
    if (a.isNotEmpty && base.isNotEmpty) {
      await fetchSubscribe(showToast: false);
    }
  }

  Future<void> _reloadProfiles() async {
    final ps = await Store.loadProfiles();
    setState(() => profiles = ps);
  }

  String _fmtTime(int ms) {
    if (ms <= 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Future<void> _updateCurrentAndHistorySubscribe({
    required String subUrl,
    String? newCookie,
  }) async {
    final base = _normBaseUrl(baseUrlCtrl.text);
    final a = authData ?? await Store.getCurrentAuthData();
    final c = (newCookie != null && newCookie.isNotEmpty) ? newCookie : (cookie ?? await Store.getCurrentCookie());

    // 更新 UI
    setState(() {
      lastSubscribeUrl = subUrl;
      if (c.isNotEmpty) cookie = c;
      lastFetchedAtMs = DateTime.now().millisecondsSinceEpoch;
    });

    // 更新 current
    await Store.saveCurrent(baseUrl: base, authData: a, cookie: c, lastSubscribeUrl: subUrl);

    // 更新历史（用 current_profile_id 精准更新）
    final currentPid = await Store.getCurrentProfileId();
    if (currentPid.isNotEmpty) {
      final ps = await Store.loadProfiles();
      final idx = ps.indexWhere((x) => x.id == currentPid);
      if (idx >= 0) {
        ps[idx] = ps[idx].copyWith(
          lastSubscribeUrl: subUrl,
          cookie: c,
          savedAtMs: DateTime.now().millisecondsSinceEpoch,
          authData: a,
        );
        await Store.saveProfiles(ps);
        await _reloadProfiles();
      }
    }
  }

  /// ✅ 关键：从任意响应里（比如 callApi）同步 subscribe_url 到“订阅链接”区域
  Future<void> _trySyncSubscribeFromResponse({
    required String requestPath,
    required int statusCode,
    required String responseBody,
    String? setCookieHeader,
  }) async {
    if (statusCode < 200 || statusCode >= 300) return;

    // 只对 getSubscribe 做同步（包含可能的 query/参数）
    if (!requestPath.contains('/api/v1/user/getSubscribe')) return;

    try {
      final j = jsonDecode(responseBody);
      final sub = _extractSubscribeUrl(j);
      if (sub.isEmpty) return;

      final c = _extractSessionCookie(setCookieHeader);
      await _updateCurrentAndHistorySubscribe(subUrl: sub, newCookie: c.isNotEmpty ? c : null);
    } catch (_) {
      // ignore
    }
  }

  Future<void> loginAndPersist() async {
    setState(() {
      loading = true;
      respStatus = null;
      respText = null;
    });

    try {
      final base = _normBaseUrl(baseUrlCtrl.text);
      final email = emailCtrl.text.trim();
      final pwd = pwdCtrl.text;

      if (!base.startsWith('http://') && !base.startsWith('https://')) {
        throw Exception('面板域名必须以 http:// 或 https:// 开头');
      }
      if (email.isEmpty || pwd.isEmpty) {
        throw Exception('请输入邮箱和密码');
      }

      final uri = Uri.parse('$base/api/v1/passport/auth/login');
      final resp = await http
          .post(
            uri,
            headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': pwd}),
          )
          .timeout(const Duration(seconds: 15));

      setState(() {
        respStatus = resp.statusCode;
        respText = _prettyJsonIfPossible(resp.body);
      });

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('登录失败：HTTP ${resp.statusCode}');
      }

      final j = jsonDecode(resp.body);
      final a = _extractAuthData(j);
      if (a.isEmpty) {
        throw Exception('登录成功但未找到 data.auth_data（后端返回结构与预期不一致）');
      }

      final c = _extractSessionCookie(resp.headers['set-cookie']);

      // 生成 profile id（同站点同邮箱覆盖）
      final pid = _makeProfileId(base, email);

      // 保存当前
      await Store.saveCurrent(
        baseUrl: base,
        authData: a,
        cookie: c,
        lastSubscribeUrl: (lastSubscribeUrl ?? ''),
      );
      await Store.saveCurrentProfileId(pid);

      // 写历史
      final profile = LoginProfile(
        id: pid,
        baseUrl: base,
        email: email,
        authData: a,
        cookie: c,
        lastSubscribeUrl: (lastSubscribeUrl ?? ''),
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await Store.upsertProfile(profile);

      setState(() {
        authData = a;
        cookie = c.isEmpty ? null : c;
      });
      await _reloadProfiles();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('登录成功，已保存到历史')));

      // 登录后拉一次订阅并保存
      await fetchSubscribe(showToast: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('错误：$e')));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> fetchSubscribe({bool showToast = false}) async {
    setState(() {
      loading = true;
      respStatus = null;
      respText = null;
    });

    try {
      final base = _normBaseUrl(baseUrlCtrl.text);
      final a = authData ?? await Store.getCurrentAuthData();
      if (a.isEmpty) throw Exception('未登录：请先登录');

      final headers = <String, String>{
        'Accept': 'application/json',
        'Authorization': a,
      };

      final c = cookie ?? await Store.getCurrentCookie();
      if (c.isNotEmpty) headers['Cookie'] = c;

      final uri = Uri.parse('$base/api/v1/user/getSubscribe');
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));

      setState(() {
        respStatus = resp.statusCode;
        respText = _prettyJsonIfPossible(resp.body);
      });

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('获取订阅失败：HTTP ${resp.statusCode}');
      }

      // 同步订阅链接（并把 set-cookie 的最新 session 更新进去）
      await _trySyncSubscribeFromResponse(
        requestPath: '/api/v1/user/getSubscribe',
        statusCode: resp.statusCode,
        responseBody: resp.body,
        setCookieHeader: resp.headers['set-cookie'],
      );

      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已获取最新订阅链接')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('错误：$e')));
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> callApi() async {
    final base = _normBaseUrl(baseUrlCtrl.text);
    final path = pathCtrl.text.trim();
    final a = authData ?? await Store.getCurrentAuthData();
    if (a.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先登录获取 auth_data')));
      return;
    }
    if (!path.startsWith('/')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('路径必须以 / 开头')));
      return;
    }

    setState(() {
      loading = true;
      respStatus = null;
      respText = null;
    });

    try {
      final uri = Uri.parse('$base$path');
      final headers = <String, String>{
        'Accept': 'application/json',
        'Authorization': a,
        'Content-Type': 'application/json',
      };
      final c = cookie ?? await Store.getCurrentCookie();
      if (c.isNotEmpty) headers['Cookie'] = c;

      http.Response resp;
      switch (method) {
        case HttpMethod.get:
          resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
          break;
        case HttpMethod.delete:
          resp = await http.delete(uri, headers: headers).timeout(const Duration(seconds: 20));
          break;
        case HttpMethod.post:
          resp = await http
              .post(uri, headers: headers, body: bodyCtrl.text.isEmpty ? '{}' : bodyCtrl.text)
              .timeout(const Duration(seconds: 20));
          break;
        case HttpMethod.put:
          resp = await http
              .put(uri, headers: headers, body: bodyCtrl.text.isEmpty ? '{}' : bodyCtrl.text)
              .timeout(const Duration(seconds: 20));
          break;
      }

      setState(() {
        respStatus = resp.statusCode;
        respText = _prettyJsonIfPossible(resp.body);
      });

      // ✅ 关键修复：如果你在“自定义 API”里请求 getSubscribe，也同步订阅链接到上方卡片
      await _trySyncSubscribeFromResponse(
        requestPath: path,
        statusCode: resp.statusCode,
        responseBody: resp.body,
        setCookieHeader: resp.headers['set-cookie'],
      );
    } catch (e) {
      setState(() => respText = 'Exception: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> copySubscribe() async {
    final s = lastSubscribeUrl;
    if (s == null || s.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: s));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制订阅链接')));
  }

  Future<void> clearAllLocal() async {
    await Store.clearAll();
    setState(() {
      authData = null;
      cookie = null;
      lastSubscribeUrl = null;
      respStatus = null;
      respText = null;
      profiles = [];
      lastFetchedAtMs = 0;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空所有本地数据与历史')));
  }

  Future<void> useProfile(LoginProfile p) async {
    baseUrlCtrl.text = p.baseUrl;
    emailCtrl.text = p.email;
    pwdCtrl.text = '';

    setState(() {
      authData = p.authData;
      cookie = p.cookie.isEmpty ? null : p.cookie;
      lastSubscribeUrl = p.lastSubscribeUrl.isEmpty ? null : p.lastSubscribeUrl;
    });

    await Store.saveCurrent(
      baseUrl: p.baseUrl,
      authData: p.authData,
      cookie: p.cookie,
      lastSubscribeUrl: p.lastSubscribeUrl,
    );
    await Store.saveCurrentProfileId(p.id);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已切换账号，正在刷新订阅…')));
    await fetchSubscribe(showToast: false);
  }

  Future<void> deleteProfile(LoginProfile p) async {
    await Store.deleteProfile(p.id);
    await _reloadProfiles();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除该历史记录')));
  }

  Future<void> clearProfilesOnly() async {
    await Store.clearProfiles();
    await _reloadProfiles();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已清空历史记录')));
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = (authData != null && authData!.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: const Text('XBoard API 工具'),
        actions: [
          IconButton(
            tooltip: '刷新订阅',
            onPressed: loading ? null : () => fetchSubscribe(showToast: true),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) async {
              if (v == 'clear_profiles') await clearProfilesOnly();
              if (v == 'clear_all') await clearAllLocal();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear_profiles', child: Text('清空历史记录')),
              PopupMenuItem(value: 'clear_all', child: Text('清空全部数据（含当前登录）')),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // ===== 历史登录列表 =====
            Row(
              children: [
                const Expanded(
                  child: Text('历史登录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: loading || profiles.isEmpty ? null : clearProfilesOnly,
                  child: const Text('清空历史'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (profiles.isEmpty)
              const Text('暂无历史记录（登录一次就会自动保存）', style: TextStyle(color: Colors.black54))
            else
              ...profiles.map((p) {
                return Card(
                  child: ListTile(
                    title: Text('${p.email.isEmpty ? '(未记录邮箱)' : p.email}  ·  ${p.baseUrl}'),
                    subtitle: Text(
                      '保存时间：${_fmtTime(p.savedAtMs)}'
                      '${p.lastSubscribeUrl.isNotEmpty ? '\n订阅：${p.lastSubscribeUrl}' : ''}',
                    ),
                    isThreeLine: p.lastSubscribeUrl.isNotEmpty,
                    onTap: loading ? null : () => useProfile(p),
                    trailing: IconButton(
                      tooltip: '删除',
                      onPressed: loading ? null : () => deleteProfile(p),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                );
              }),

            const Divider(height: 28),

            // ===== 登录区 =====
            const Text('登录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: baseUrlCtrl,
              decoration: const InputDecoration(labelText: '面板域名（例如 https://example.com）'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: '邮箱（用于历史记录标识）'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pwdCtrl,
              decoration: const InputDecoration(labelText: '密码（不会保存）'),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : loginAndPersist,
                child: Text(loading ? '处理中...' : '登录并保存到历史（使用 auth_data）'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loggedIn ? '✅ 当前已登录（auth_data 已保存）' : '未登录',
              style: TextStyle(color: loggedIn ? Colors.green : Colors.black54),
            ),

            const Divider(height: 28),

            // ===== 订阅链接 =====
            const Text('订阅链接', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (lastSubscribeUrl != null && lastSubscribeUrl!.isNotEmpty) ...[
              SelectableText(lastSubscribeUrl!),
              const SizedBox(height: 6),
              Text('最后刷新：${_fmtTime(lastFetchedAtMs)}', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: copySubscribe,
                  child: const Text('复制订阅链接'),
                ),
              ),
            ] else ...[
              const Text('暂无（登录后点右上角刷新或请求 getSubscribe）'),
            ],

            const Divider(height: 28),

            // ===== 自定义 API 请求 =====
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
                    decoration: const InputDecoration(labelText: '路径（例如 /api/v1/user/getSubscribe）'),
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
                child: Text(loading ? '请求中...' : '发送请求并输出返回'),
              ),
            ),

            const SizedBox(height: 16),
            if (respStatus != null)
              Text('HTTP Status: $respStatus', style: const TextStyle(fontWeight: FontWeight.w700)),
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
