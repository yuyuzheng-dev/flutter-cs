import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 认证弹窗：登录 / 注册 / 忘记密码（发送邮箱验证码 + 重置密码）
///
/// 约定：baseUrl 只填域名，不带 /api/v1
/// 例如：https://com.android22.com
///
/// 返回：AuthDialogResult
class AuthDialogResult {
  final String baseUrl; // https://xxx
  final String email;
  final String password; // 你要求默认记录
  final String authData; // Bearer ...
  final String cookie; // server_name_session=...

  const AuthDialogResult({
    required this.baseUrl,
    required this.email,
    required this.password,
    required this.authData,
    required this.cookie,
  });
}

enum AuthTab { login, register, forgot }
enum EmailCodeScene { register, resetPassword }

extension _SceneExt on EmailCodeScene {
  String get value {
    switch (this) {
      case EmailCodeScene.register:
        return 'register';
      case EmailCodeScene.resetPassword:
        return 'resetPassword';
    }
  }

  String get label {
    switch (this) {
      case EmailCodeScene.register:
        return '注册';
      case EmailCodeScene.resetPassword:
        return '重置密码';
    }
  }
}

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

String _extractAuthData(dynamic j) {
  if (j is Map) {
    final data = j['data'];
    if (data is Map && data['auth_data'] != null) return '${data['auth_data']}';
    // 兼容少数面板：直接返回 token
    if (data is Map && data['token'] != null) return 'Bearer ${data['token']}';
  }
  if (j is Map && j['token'] != null) return 'Bearer ${j['token']}';
  return '';
}

String _extractSessionCookie(String? setCookie) {
  if (setCookie == null || setCookie.isEmpty) return '';
  final m = RegExp(r'(server_name_session=[^;]+)').firstMatch(setCookie);
  return m?.group(1) ?? '';
}

class XBoardAuthDialog {
  static Future<AuthDialogResult?> show(
    BuildContext context, {
    required String initialBaseUrl,
    String initialEmail = '',
    String initialPassword = '',
  }) {
    return showDialog<AuthDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AuthDialog(
        initialBaseUrl: initialBaseUrl,
        initialEmail: initialEmail,
        initialPassword: initialPassword,
      ),
    );
  }
}

class _AuthDialog extends StatefulWidget {
  final String initialBaseUrl;
  final String initialEmail;
  final String initialPassword;

  const _AuthDialog({
    required this.initialBaseUrl,
    required this.initialEmail,
    required this.initialPassword,
  });

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  AuthTab tab = AuthTab.login;

  final baseUrlCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();

  // register
  final inviteCtrl = TextEditingController();

  // forgot/reset
  final emailCodeCtrl = TextEditingController();

  // sendEmailCode scene
  EmailCodeScene codeScene = EmailCodeScene.register;

  bool loading = false;
  String? errText;

  @override
  void initState() {
    super.initState();
    baseUrlCtrl.text = widget.initialBaseUrl.isNotEmpty ? widget.initialBaseUrl : 'https://example.com';
    emailCtrl.text = widget.initialEmail;
    pwdCtrl.text = widget.initialPassword;
  }

  @override
  void dispose() {
    baseUrlCtrl.dispose();
    emailCtrl.dispose();
    pwdCtrl.dispose();
    inviteCtrl.dispose();
    emailCodeCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body) async {
    final base = _normBaseUrl(baseUrlCtrl.text);
    final uri = _api(base, path);
    final resp = await http
        .post(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    final raw = resp.body;
    Map<String, dynamic> json;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        json = parsed;
      } else {
        throw Exception('Unexpected JSON type');
      }
    } catch (_) {
      throw Exception('后端返回不是 JSON：HTTP ${resp.statusCode}\n$raw');
    }

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      // 尽量把 message/ errors 输出
      final msg = json['message']?.toString() ?? 'HTTP ${resp.statusCode}';
      final errs = json['errors']?.toString() ?? '';
      throw Exception(errs.isEmpty ? msg : '$msg\n$errs');
    }
    return json;
  }

  Future<void> _sendEmailCode() async {
    setState(() {
      loading = true;
      errText = null;
    });
    try {
      final email = emailCtrl.text.trim();
      if (email.isEmpty) throw Exception('请输入邮箱');
      final scene = codeScene.value;

      // 你的接口：/api/v1/passport/auth/sendEmailCode
      await _postJson('/api/v1/passport/auth/sendEmailCode', {
        'email': email,
        'scene': scene,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('验证码已发送（场景：${codeScene.label}）')),
      );
    } catch (e) {
      setState(() => errText = '错误：$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _login() async {
    setState(() {
      loading = true;
      errText = null;
    });
    try {
      final base = _normBaseUrl(baseUrlCtrl.text);
      if (!base.startsWith('http://') && !base.startsWith('https://')) {
        throw Exception('面板域名必须以 http:// 或 https:// 开头');
      }
      final email = emailCtrl.text.trim();
      final pwd = pwdCtrl.text;
      if (email.isEmpty || pwd.isEmpty) throw Exception('请输入邮箱和密码');

      final uri = _api(base, '/api/v1/passport/auth/login');
      final resp = await http
          .post(
            uri,
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': pwd}),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic> j;
      try {
        final parsed = jsonDecode(resp.body);
        if (parsed is Map<String, dynamic>) {
          j = parsed;
        } else {
          throw Exception('Unexpected JSON type');
        }
      } catch (_) {
        throw Exception('后端返回不是 JSON：HTTP ${resp.statusCode}\n${resp.body}');
      }

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final msg = j['message']?.toString() ?? 'HTTP ${resp.statusCode}';
        final errs = j['errors']?.toString() ?? '';
        throw Exception(errs.isEmpty ? msg : '$msg\n$errs');
      }

      final authData = _extractAuthData(j);
      if (authData.isEmpty) throw Exception('登录成功但未找到 data.auth_data');

      final cookie = _extractSessionCookie(resp.headers['set-cookie']);

      if (!mounted) return;
      Navigator.of(context).pop(
        AuthDialogResult(
          baseUrl: base,
          email: email,
          password: pwd,
          authData: authData,
          cookie: cookie,
        ),
      );
    } catch (e) {
      setState(() => errText = '错误：$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _register() async {
    setState(() {
      loading = true;
      errText = null;
    });
    try {
      final email = emailCtrl.text.trim();
      final pwd = pwdCtrl.text;
      if (email.isEmpty || pwd.isEmpty) throw Exception('请输入邮箱和密码');

      final invite = inviteCtrl.text.trim();

      // 你的接口：/api/v1/passport/auth/register
      await _postJson('/api/v1/passport/auth/register', {
        'email': email,
        'password': pwd,
        if (invite.isNotEmpty) 'invite_code': invite,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注册成功，正在登录…')));

      // 注册后直接登录拿 auth_data
      await _login();
    } catch (e) {
      setState(() => errText = '错误：$e');
      setState(() => loading = false);
    }
  }

  Future<void> _resetPassword() async {
    setState(() {
      loading = true;
      errText = null;
    });
    try {
      final email = emailCtrl.text.trim();
      final pwd = pwdCtrl.text;
      final code = emailCodeCtrl.text.trim();
      if (email.isEmpty) throw Exception('请输入邮箱');
      if (pwd.isEmpty) throw Exception('请输入新密码');
      if (code.isEmpty) throw Exception('请输入邮箱验证码');

      // 你的接口：/api/v1/passport/auth/resetPassword
      await _postJson('/api/v1/passport/auth/resetPassword', {
        'email': email,
        'password': pwd,
        'email_code': code,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('重置成功，正在登录…')));

      // 重置成功后直接登录
      await _login();
    } catch (e) {
      setState(() => errText = '错误：$e');
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (tab) {
      AuthTab.login => '登录',
      AuthTab.register => '注册',
      AuthTab.forgot => '忘记密码',
    };

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // tabs
              SegmentedButton<AuthTab>(
                segments: const [
                  ButtonSegment(value: AuthTab.login, label: Text('登录')),
                  ButtonSegment(value: AuthTab.register, label: Text('注册')),
                  ButtonSegment(value: AuthTab.forgot, label: Text('忘记密码')),
                ],
                selected: {tab},
                onSelectionChanged: loading
                    ? null
                    : (s) {
                        setState(() {
                          tab = s.first;
                          errText = null;
                          // 默认切换场景
                          codeScene = (tab == AuthTab.forgot) ? EmailCodeScene.resetPassword : EmailCodeScene.register;
                        });
                      },
              ),
              const SizedBox(height: 12),

              TextField(
                controller: baseUrlCtrl,
                decoration: const InputDecoration(
                  labelText: '面板域名（不要带 /api/v1）',
                  hintText: 'https://com.android22.com',
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: '邮箱'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 10),

              TextField(
                controller: pwdCtrl,
                decoration: InputDecoration(
                  labelText: tab == AuthTab.forgot ? '新密码' : '密码',
                ),
                obscureText: true,
              ),

              if (tab == AuthTab.register) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: inviteCtrl,
                  decoration: const InputDecoration(labelText: '邀请码（可选）'),
                ),
              ],

              if (tab == AuthTab.forgot) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: emailCodeCtrl,
                  decoration: const InputDecoration(labelText: '邮箱验证码'),
                ),
              ],

              const SizedBox(height: 10),

              // send code row
              if (tab != AuthTab.login) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<EmailCodeScene>(
                        value: codeScene,
                        items: const [
                          DropdownMenuItem(value: EmailCodeScene.register, child: Text('验证码场景：注册')),
                          DropdownMenuItem(value: EmailCodeScene.resetPassword, child: Text('验证码场景：重置密码')),
                        ],
                        onChanged: loading
                            ? null
                            : (v) {
                                if (v != null) setState(() => codeScene = v);
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: loading ? null : _sendEmailCode,
                      child: Text(loading ? '发送中…' : '发送验证码'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],

              if (errText != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(errText!, style: const TextStyle(color: Colors.red)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: loading ? null : () => Navigator.of(context).pop(null),
          child: const Text('关闭'),
        ),
        if (tab == AuthTab.login)
          ElevatedButton(onPressed: loading ? null : _login, child: Text(loading ? '处理中…' : '登录')),
        if (tab == AuthTab.register)
          ElevatedButton(onPressed: loading ? null : _register, child: Text(loading ? '处理中…' : '注册并登录')),
        if (tab == AuthTab.forgot)
          ElevatedButton(onPressed: loading ? null : _resetPassword, child: Text(loading ? '处理中…' : '重置并登录')),
      ],
    );
  }
}
