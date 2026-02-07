import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config_manager.dart';

class AuthDialogResult {
  final String email;
  final String password;
  final String authData; // Bearer ...
  final String cookie;   // server_name_session=...

  const AuthDialogResult({
    required this.email,
    required this.password,
    required this.authData,
    required this.cookie,
  });
}

enum AuthMode { login, register, forgot }

String _extractAuthData(Map<String, dynamic> j) {
  final data = j['data'];
  if (data is Map && data['auth_data'] != null) return '${data['auth_data']}';
  if (data is Map && data['token'] != null) return 'Bearer ${data['token']}';
  return '';
}

String _extractSessionCookie(String? setCookie) {
  if (setCookie == null || setCookie.isEmpty) return '';
  final m = RegExp(r'(server_name_session=[^;]+)').firstMatch(setCookie);
  return m?.group(1) ?? '';
}

Uri _apiV1(String pathUnderApiV1) {
  final base = ConfigManager.I.apiBaseUrl;
  final prefix = ConfigManager.I.apiPrefix;
  var p = pathUnderApiV1;
  if (!p.startsWith('/')) p = '/$p';
  return Uri.parse('$base$prefix$p');
}

class GuestConfig {
  final int isEmailVerify; // 0/1
  final List<String> emailWhitelistSuffix; // 为空表示 email_whitelist_suffix=0 或不是数组

  const GuestConfig({required this.isEmailVerify, required this.emailWhitelistSuffix});

  static GuestConfig? fromJson(dynamic j) {
    if (j is! Map) return null;
    final data = j['data'];
    if (data is! Map) return null;

    int toInt(dynamic v) {
      if (v is bool) return v ? 1 : 0;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final isEmailVerify = toInt(data['is_email_verify']);

    // 关键：email_whitelist_suffix 可能是 0 或 List
    final raw = data['email_whitelist_suffix'];
    List<String> suffixes = [];
    if (raw is List) {
      suffixes = raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      suffixes = suffixes.toSet().toList();
      suffixes.sort();
    } else {
      suffixes = [];
    }

    return GuestConfig(isEmailVerify: isEmailVerify, emailWhitelistSuffix: suffixes);
  }
}

class XBoardAuthDialog {
  static Future<AuthDialogResult?> show(
    BuildContext context, {
    String initialEmail = '',
    String initialPassword = '',
    bool forceLogin = false,
  }) async {
    await ConfigManager.I.init();
    return showDialog<AuthDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AuthDialog(
        initialEmail: initialEmail,
        initialPassword: initialPassword,
        forceLogin: forceLogin,
      ),
    );
  }
}

class _AuthDialog extends StatefulWidget {
  final String initialEmail;
  final String initialPassword;
  final bool forceLogin;

  const _AuthDialog({
    required this.initialEmail,
    required this.initialPassword,
    required this.forceLogin,
  });

  @override
  State<_AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<_AuthDialog> {
  AuthMode mode = AuthMode.login;

  // 登录/找回：完整邮箱输入
  final emailFullCtrl = TextEditingController();

  // 注册：若有白名单后缀，则用前缀+下拉
  final emailPrefixCtrl = TextEditingController();
  String selectedSuffix = '';

  final pwdCtrl = TextEditingController();
  final inviteCtrl = TextEditingController();
  final emailCodeCtrl = TextEditingController();

  bool loading = false;

  // 联通检测状态
  bool configLoading = true;
  bool configOk = false;
  GuestConfig? guestConfig;
  String? errText;

  bool get _registerHasWhitelistSuffix =>
      (guestConfig?.emailWhitelistSuffix.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    emailFullCtrl.text = widget.initialEmail.trim();
    pwdCtrl.text = widget.initialPassword;
    _recheckAndLoadGuestConfig();
  }

  @override
  void dispose() {
    emailFullCtrl.dispose();
    emailPrefixCtrl.dispose();
    pwdCtrl.dispose();
    inviteCtrl.dispose();
    emailCodeCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _parseJson(http.Response resp) async {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('Unexpected JSON type');
    } catch (_) {
      throw Exception('后端返回不是 JSON：HTTP ${resp.statusCode}\n${resp.body}');
    }
  }

  String _formatApiError(Map<String, dynamic> j, int statusCode) {
    final msg = j['message']?.toString() ?? 'HTTP $statusCode';
    final errs = j['errors'];
    if (errs == null) return msg;
    return '$msg\n$errs';
  }

  // 注册邮箱：强制白名单后缀
  String _currentEmailForRegister() {
    if (!_registerHasWhitelistSuffix) return emailFullCtrl.text.trim();
    final prefix = emailPrefixCtrl.text.trim();
    final suffix = selectedSuffix.trim();
    if (prefix.isEmpty || suffix.isEmpty) return '';
    return '$prefix@$suffix';
  }

  // 登录/找回：不限制后缀（按你要求“注册才限制”）
  String _currentEmailNormal() => emailFullCtrl.text.trim();

  Future<void> _recheckAndLoadGuestConfig() async {
    setState(() {
      configLoading = true;
      configOk = false;
      guestConfig = null;
      errText = null;
    });

    try {
      // 先拉远程 config + 竞速选最快域名
      await ConfigManager.I.refreshRemoteConfigAndRace();
      if (!ConfigManager.I.ready) {
        throw Exception('没有可用域名（远程配置/兜底域名都为空或不可用）');
      }

      // 再用“已选最快域名”请求 guest config
      final resp = await http
          .get(_apiV1('/guest/comm/config'), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(_formatApiError(j, resp.statusCode));
      }

      final cfg = GuestConfig.fromJson(j);
      if (cfg == null) throw Exception('返回格式异常');

      // 如果注册白名单存在，初始化 selectedSuffix
      if (cfg.emailWhitelistSuffix.isNotEmpty) {
        // 尝试从 emailFull 拆分
        final full = emailFullCtrl.text.trim();
        if (full.contains('@')) {
          final parts = full.split('@');
          emailPrefixCtrl.text = parts.first;
          final suf = parts.length > 1 ? parts.last : '';
          selectedSuffix = cfg.emailWhitelistSuffix.contains(suf) ? suf : cfg.emailWhitelistSuffix.first;
        } else {
          emailPrefixCtrl.text = full;
          selectedSuffix = cfg.emailWhitelistSuffix.first;
        }
      }

      setState(() {
        guestConfig = cfg;
        configOk = true;
      });
    } catch (e) {
      setState(() {
        errText = '联通检测失败：$e';
        configOk = false;
      });
    } finally {
      setState(() => configLoading = false);
    }
  }

  Future<void> _sendEmailCode() async {
    // 自动场景：注册 register，找回 resetPassword
    final scene = (mode == AuthMode.forgot) ? 'resetPassword' : 'register';

    setState(() {
      loading = true;
      errText = null;
    });

    try {
      if (!configOk) throw Exception('联通检测未通过');

      final email = (mode == AuthMode.register)
          ? _currentEmailForRegister()
          : _currentEmailNormal();

      if (email.isEmpty) throw Exception('请输入邮箱');

      final resp = await http
          .post(
            _apiV1('/passport/auth/sendEmailCode'),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'scene': scene}),
          )
          .timeout(const Duration(seconds: 20));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(_formatApiError(j, resp.statusCode));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('验证码已发送（$scene）')));
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
      if (!configOk) throw Exception('联通检测未通过');

      final email = _currentEmailNormal();
      final pwd = pwdCtrl.text;
      if (email.isEmpty || pwd.isEmpty) throw Exception('请输入邮箱和密码');

      final resp = await http
          .post(
            _apiV1('/passport/auth/login'),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': pwd}),
          )
          .timeout(const Duration(seconds: 20));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(_formatApiError(j, resp.statusCode));
      }

      final authData = _extractAuthData(j);
      if (authData.isEmpty) throw Exception('登录成功但缺少 data.auth_data');

      final cookie = _extractSessionCookie(resp.headers['set-cookie']);

      if (!mounted) return;
      Navigator.of(context).pop(AuthDialogResult(
        email: email,
        password: pwd,
        authData: authData,
        cookie: cookie,
      ));
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
      if (!configOk) throw Exception('联通检测未通过');

      final email = _currentEmailForRegister();
      final pwd = pwdCtrl.text;
      if (email.isEmpty || pwd.isEmpty) throw Exception('请输入邮箱和密码');

      // 强制：如果有白名单后缀，则必须在列表里
      if (_registerHasWhitelistSuffix) {
        final suffix = email.split('@').length > 1 ? email.split('@').last : '';
        if (!(guestConfig?.emailWhitelistSuffix.contains(suffix) ?? false)) {
          throw Exception('邮箱后缀不在白名单内');
        }
      }

      final invite = inviteCtrl.text.trim();

      final resp = await http
          .post(
            _apiV1('/passport/auth/register'),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email,
              'password': pwd,
              if (invite.isNotEmpty) 'invite_code': invite,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(_formatApiError(j, resp.statusCode));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注册成功，正在登录…')));
      // 注册成功后直接登录返回 token/auth_data（按你之前接口）
      await _login();
    } catch (e) {
      setState(() => errText = '错误：$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _resetPassword() async {
    setState(() {
      loading = true;
      errText = null;
    });

    try {
      if (!configOk) throw Exception('联通检测未通过');

      final email = _currentEmailNormal();
      final pwd = pwdCtrl.text;
      final code = emailCodeCtrl.text.trim();

      if (email.isEmpty) throw Exception('请输入邮箱');
      if (pwd.isEmpty) throw Exception('请输入新密码');
      if (code.isEmpty) throw Exception('请输入邮箱验证码');

      final resp = await http
          .post(
            _apiV1('/passport/auth/resetPassword'),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': pwd, 'email_code': code}),
          )
          .timeout(const Duration(seconds: 20));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(_formatApiError(j, resp.statusCode));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('重置成功，正在登录…')));
      await _login();
    } catch (e) {
      setState(() => errText = '错误：$e');
    } finally {
      setState(() => loading = false);
    }
  }

  // 你原规则：is_email_verify=0 => 注册不显示发送验证码
  bool get _showSendCodeInRegister =>
      mode == AuthMode.register && (guestConfig?.isEmailVerify == 1);

  bool get _showSendCodeInForgot => mode == AuthMode.forgot;

  @override
  Widget build(BuildContext context) {
    final title = switch (mode) {
      AuthMode.login => '登录',
      AuthMode.register => '注册',
      AuthMode.forgot => '找回密码',
    };

    final canInteract = configOk && !loading && !configLoading;

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(title)),
          IconButton(
            tooltip: '重新检测（竞速选最快域名）',
            onPressed: (loading || configLoading) ? null : _recheckAndLoadGuestConfig,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: configLoading
                  ? const SizedBox(
                      key: ValueKey('spin'),
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      configOk ? Icons.verified : Icons.error_outline,
                      key: ValueKey('status'),
                      color: configOk ? Colors.green : Colors.red,
                    ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 联通检测动画区
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: configLoading
                    ? Container(
                        key: const ValueKey('checking'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          children: const [
                            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 10),
                            Expanded(child: Text('正在检测网站联通性（竞速选最快域名）…')),
                          ],
                        ),
                      )
                    : Container(
                        key: const ValueKey('checked'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          children: [
                            Icon(configOk ? Icons.check_circle : Icons.cancel,
                                color: configOk ? Colors.green : Colors.red),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                configOk ? '联通正常' : '联通异常（站点/API 可能有问题）',
                                style: TextStyle(color: configOk ? Colors.green : Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 12),

              // 邮箱输入：
              // - 登录/找回：完整输入
              // - 注册：如果 email_whitelist_suffix 是数组则强制前缀+下拉
              if (mode == AuthMode.register && _registerHasWhitelistSuffix) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: emailPrefixCtrl,
                        enabled: !loading && !configLoading,
                        decoration: const InputDecoration(labelText: '邮箱前缀'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: (selectedSuffix.isNotEmpty)
                            ? selectedSuffix
                            : (guestConfig!.emailWhitelistSuffix.isNotEmpty ? guestConfig!.emailWhitelistSuffix.first : ''),
                        items: guestConfig!.emailWhitelistSuffix
                            .map((s) => DropdownMenuItem(value: s, child: Text('@$s')))
                            .toList(),
                        onChanged: (!loading && !configLoading)
                            ? (v) => setState(() => selectedSuffix = v ?? selectedSuffix)
                            : null,
                        decoration: const InputDecoration(labelText: '邮箱后缀'),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: emailFullCtrl,
                  enabled: !loading && !configLoading,
                  decoration: const InputDecoration(labelText: '邮箱'),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],

              const SizedBox(height: 10),

              TextField(
                controller: pwdCtrl,
                enabled: !loading && !configLoading,
                decoration: InputDecoration(labelText: mode == AuthMode.forgot ? '新密码' : '密码'),
                obscureText: true,
              ),

              if (mode == AuthMode.register) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: inviteCtrl,
                  enabled: !loading && !configLoading,
                  decoration: const InputDecoration(labelText: '邀请码（可选）'),
                ),
              ],

              if (mode == AuthMode.forgot) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: emailCodeCtrl,
                  enabled: !loading && !configLoading,
                  decoration: const InputDecoration(labelText: '邮箱验证码'),
                ),
              ],

              // 发送验证码按钮：
              // - 注册：仅 is_email_verify=1 才显示（你要求）
              // - 找回：一直显示（因为 resetPassword 需要 email_code）
              if (_showSendCodeInRegister || _showSendCodeInForgot) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: canInteract ? _sendEmailCode : null,
                    child: Text(loading ? '发送中…' : '发送邮箱验证码'),
                  ),
                ),
              ],

              if (errText != null) ...[
                const SizedBox(height: 10),
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

              const SizedBox(height: 8),

              // 底部导航：默认登录；左下找回；右下注册
              Row(
                children: [
                  TextButton(
                    onPressed: (loading || configLoading)
                        ? null
                        : () => setState(() {
                              mode = AuthMode.forgot;
                              errText = null;
                            }),
                    child: const Text('找回密码'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: (loading || configLoading)
                        ? null
                        : () => setState(() {
                              mode = AuthMode.register;
                              errText = null;
                            }),
                    child: const Text('注册'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!widget.forceLogin)
          TextButton(
            onPressed: (loading || configLoading) ? null : () => Navigator.of(context).pop(null),
            child: const Text('关闭'),
          ),
        if (mode == AuthMode.login)
          ElevatedButton(
            onPressed: canInteract ? _login : null,
            child: Text(loading ? '处理中…' : '登录'),
          ),
        if (mode == AuthMode.register)
          ElevatedButton(
            onPressed: canInteract ? _register : null,
            child: Text(loading ? '处理中…' : '注册并登录'),
          ),
        if (mode == AuthMode.forgot)
          ElevatedButton(
            onPressed: canInteract ? _resetPassword : null,
            child: Text(loading ? '处理中…' : '重置并登录'),
          ),
      ],
    );
  }
}
