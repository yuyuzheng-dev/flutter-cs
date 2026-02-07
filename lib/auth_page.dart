import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'config_manager.dart';

class AuthResult {
  final String email;
  final String password;
  final String authData;
  final String cookie;
  const AuthResult({required this.email, required this.password, required this.authData, required this.cookie});
}

enum AuthMode { login, register, forgot }

class GuestConfig {
  final int isEmailVerify; // 0/1
  final List<String> emailWhitelistSuffix;

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
    final raw = data['email_whitelist_suffix'];

    List<String> suffixes = [];
    if (raw is List) {
      suffixes = raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      suffixes = suffixes.toSet().toList()..sort();
    }

    return GuestConfig(isEmailVerify: isEmailVerify, emailWhitelistSuffix: suffixes);
  }
}

class AuthPage extends StatefulWidget {
  /// force=true：禁止返回（未登录时必须留在认证页）
  final bool force;
  final String initialEmail;
  final String initialPassword;

  const AuthPage({super.key, required this.force, this.initialEmail = '', this.initialPassword = ''});

  static Route<AuthResult?> route({required bool force, String initialEmail = '', String initialPassword = ''}) {
    return MaterialPageRoute<AuthResult?>(
      fullscreenDialog: false,
      builder: (_) => AuthPage(force: force, initialEmail: initialEmail, initialPassword: initialPassword),
    );
  }

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  static const int _minPwdLen = 8;

  late final TabController _tabs;
  AuthMode _mode = AuthMode.login;

  final _formKey = GlobalKey<FormState>();

  // 登录：完整邮箱
  final emailFullCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();

  // 注册/找回：前缀 + 后缀（如果有白名单）
  final emailPrefixCtrl = TextEditingController();
  String selectedSuffix = '';

  // 注册/找回：二次确认
  final pwd2Ctrl = TextEditingController();

  // 邀请码
  final inviteCtrl = TextEditingController();

  // 邮箱验证码
  final emailCodeCtrl = TextEditingController();

  bool loading = false;
  bool configLoading = true;
  bool configOk = false;
  GuestConfig? guestConfig;
  String? errText;

  bool get _hasWhitelistSuffix => (guestConfig?.emailWhitelistSuffix.isNotEmpty ?? false);
  bool get _useSuffixUi => (_mode != AuthMode.login) && _hasWhitelistSuffix;
  bool get _needEmailVerifyInRegister => _mode == AuthMode.register && (guestConfig?.isEmailVerify == 1);
  bool get _showSendCode => (_mode == AuthMode.forgot) || _needEmailVerifyInRegister;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    emailFullCtrl.text = widget.initialEmail.trim();
    pwdCtrl.text = widget.initialPassword;

    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {
        _mode = AuthMode.values[_tabs.index];
        errText = null;
        emailCodeCtrl.clear();
        inviteCtrl.clear();
        pwd2Ctrl.clear();
      });
    });

    _recheckAndLoadGuestConfig();
  }

  @override
  void dispose() {
    _tabs.dispose();
    emailFullCtrl.dispose();
    pwdCtrl.dispose();
    emailPrefixCtrl.dispose();
    pwd2Ctrl.dispose();
    inviteCtrl.dispose();
    emailCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _openExternal(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<Map<String, dynamic>> _parseJson(http.Response resp) async {
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception('Unexpected JSON type');
  }

  String _formatApiError(Map<String, dynamic> j, int statusCode) {
    final msg = j['message']?.toString() ?? 'HTTP $statusCode';
    final errs = j['errors'];
    if (errs == null) return msg;
    return '$msg\n$errs';
  }

  void _initSuffixFromEmailIfPossible(GuestConfig cfg) {
    if (cfg.emailWhitelistSuffix.isEmpty) return;

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

  Future<void> _recheckAndLoadGuestConfig() async {
    setState(() {
      configLoading = true;
      configOk = false;
      guestConfig = null;
      errText = null;
    });

    try {
      await ConfigManager.I.refreshRemoteConfigAndRace();
      final resp = await http
          .get(ConfigManager.I.api('/guest/comm/config'), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 12));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw Exception(_formatApiError(j, resp.statusCode));

      final cfg = GuestConfig.fromJson(j);
      if (cfg == null) throw Exception('返回格式异常');

      _initSuffixFromEmailIfPossible(cfg);

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

  String _currentEmailForMode() {
    if (_mode == AuthMode.login) return emailFullCtrl.text.trim();

    if (_useSuffixUi) {
      final prefix = emailPrefixCtrl.text.trim();
      final suffix = selectedSuffix.trim();
      if (prefix.isEmpty || suffix.isEmpty) return '';
      return '$prefix@$suffix';
    }
    return emailFullCtrl.text.trim();
  }

  String? _validateEmail() {
    if (_mode == AuthMode.login) {
      final e = emailFullCtrl.text.trim();
      if (e.isEmpty) return '请输入邮箱';
      if (!e.contains('@') || !e.contains('.')) return '邮箱格式不正确';
      return null;
    }

    if (_useSuffixUi) {
      if (emailPrefixCtrl.text.trim().isEmpty) return '请输入邮箱前缀';
      if (selectedSuffix.trim().isEmpty) return '请选择邮箱后缀';
      return null;
    }

    final e = emailFullCtrl.text.trim();
    if (e.isEmpty) return '请输入邮箱';
    if (!e.contains('@') || !e.contains('.')) return '邮箱格式不正确';
    return null;
  }

  String? _validatePwd(String v) {
    if (v.isEmpty) return '请输入密码';
    if (_mode != AuthMode.login && v.length < _minPwdLen) return '密码至少 $_minPwdLen 位';
    return null;
  }

  String? _validatePwdConfirm(String v) {
    if (_mode == AuthMode.login) return null;
    if (v.isEmpty) return '请再次输入密码';
    if (v != pwdCtrl.text) return '两次密码不一致';
    return null;
  }

  Future<void> _sendEmailCode() async {
    final scene = (_mode == AuthMode.forgot) ? 'resetPassword' : 'register';

    setState(() {
      loading = true;
      errText = null;
    });

    try {
      if (!configOk) throw Exception('联通检测未通过');
      final email = _currentEmailForMode();
      if (email.isEmpty) throw Exception('请输入邮箱');

      final resp = await http
          .post(
            ConfigManager.I.api('/passport/auth/sendEmailCode'),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'scene': scene}),
          )
          .timeout(const Duration(seconds: 20));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw Exception(_formatApiError(j, resp.statusCode));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('验证码已发送')));
    } catch (e) {
      setState(() => errText = '错误：$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      loading = true;
      errText = null;
    });

    try {
      if (!configOk) throw Exception('联通检测未通过');

      final email = emailFullCtrl.text.trim();
      final pwd = pwdCtrl.text;

      final resp = await http
          .post(
            ConfigManager.I.api('/passport/auth/login'),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': pwd}),
          )
          .timeout(const Duration(seconds: 20));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw Exception(_formatApiError(j, resp.statusCode));

      final data = j['data'];
      String auth = '';
      if (data is Map && data['auth_data'] != null) auth = '${data['auth_data']}';
      if (auth.isEmpty && data is Map && data['token'] != null) auth = 'Bearer ${data['token']}';
      if (auth.isEmpty) throw Exception('登录成功但缺少 data.auth_data');

      final setCookie = resp.headers['set-cookie'];
      String cookie = '';
      if (setCookie != null) {
        final m = RegExp(r'(server_name_session=[^;]+)').firstMatch(setCookie);
        cookie = m?.group(1) ?? '';
      }

      if (!mounted) return;
      Navigator.of(context).pop(AuthResult(email: email, password: pwd, authData: auth, cookie: cookie));
    } catch (e) {
      setState(() => errText = '错误：$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      loading = true;
      errText = null;
    });

    try {
      if (!configOk) throw Exception('联通检测未通过');

      final email = _currentEmailForMode();
      final pwd = pwdCtrl.text;
      final pwd2 = pwd2Ctrl.text;
      if (pwd.length < _minPwdLen) throw Exception('密码至少 $_minPwdLen 位');
      if (pwd != pwd2) throw Exception('两次密码不一致');

      final verify = guestConfig?.isEmailVerify ?? 0;
      final code = emailCodeCtrl.text.trim();
      if (verify == 1 && code.isEmpty) throw Exception('请输入邮箱验证码');

      final invite = inviteCtrl.text.trim();
      final body = <String, dynamic>{
        'email': email,
        'password': pwd,
        if (invite.isNotEmpty) 'invite_code': invite,
        if (verify == 1) 'email_code': code,
      };

      final resp = await http
          .post(
            ConfigManager.I.api('/passport/auth/register'),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw Exception(_formatApiError(j, resp.statusCode));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('注册成功，请去登录')));
      _tabs.animateTo(0);
    } catch (e) {
      setState(() => errText = '错误：$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      loading = true;
      errText = null;
    });

    try {
      if (!configOk) throw Exception('联通检测未通过');

      final email = _currentEmailForMode();
      final code = emailCodeCtrl.text.trim();
      final pwd = pwdCtrl.text;
      final pwd2 = pwd2Ctrl.text;

      if (code.isEmpty) throw Exception('请输入邮箱验证码');
      if (pwd.length < _minPwdLen) throw Exception('密码至少 $_minPwdLen 位');
      if (pwd != pwd2) throw Exception('两次密码不一致');

      final resp = await http
          .post(
            ConfigManager.I.api('/passport/auth/resetPassword'),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: jsonEncode({'email': email, 'password': pwd, 'email_code': code}),
          )
          .timeout(const Duration(seconds: 20));

      final j = await _parseJson(resp);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw Exception(_formatApiError(j, resp.statusCode));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('重置成功，请去登录')));
      _tabs.animateTo(0);
    } catch (e) {
      setState(() => errText = '错误：$e');
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _onPrimary() async {
    if (!configOk || loading || configLoading) return;
    switch (_mode) {
      case AuthMode.login:
        return _login();
      case AuthMode.register:
        return _register();
      case AuthMode.forgot:
        return _resetPassword();
    }
  }

  String _primaryText() {
    if (loading) return '处理中…';
    return switch (_mode) {
      AuthMode.login => '登录',
      AuthMode.register => '注册',
      AuthMode.forgot => '重置密码',
    };
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 30, offset: const Offset(0, 18)),
        ],
      ),
      child: child,
    );
  }

  Widget _connectBadge() {
    final text = configLoading ? '联通检测中…' : (configOk ? '联通正常' : '联通异常');
    final icon = configLoading
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(configOk ? Icons.check_circle : Icons.cancel, color: configOk ? Colors.green : Colors.red, size: 20);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: Colors.white.withOpacity(0.9))),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '重新检测',
            onPressed: (loading || configLoading) ? null : _recheckAndLoadGuestConfig,
            icon: Icon(Icons.refresh, color: Colors.white.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  InputDecoration _deco(String label, {String? hint}) {
    final labelColor = Colors.white.withOpacity(0.75);
    final hintColor = Colors.white.withOpacity(0.40);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: labelColor),
      hintText: hint,
      hintStyle: TextStyle(color: hintColor),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
    );
  }

  Widget _emailField() {
    if (_mode != AuthMode.login && _useSuffixUi) {
      final items = guestConfig!.emailWhitelistSuffix;
      final v = selectedSuffix.isNotEmpty ? selectedSuffix : (items.isNotEmpty ? items.first : '');

      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: emailPrefixCtrl,
              enabled: !loading && !configLoading,
              style: const TextStyle(color: Colors.white),
              decoration: _deco('邮箱前缀'),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (_) => _validateEmail(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: v.isEmpty ? null : v,
              isExpanded: true,
              dropdownColor: const Color(0xFF1D2230),
              style: const TextStyle(color: Colors.white),
              items: items.map((s) => DropdownMenuItem(value: s, child: Text('@$s', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (!loading && !configLoading) ? (vv) => setState(() => selectedSuffix = vv ?? selectedSuffix) : null,
              decoration: _deco('后缀'),
            ),
          ),
        ],
      );
    }

    return TextFormField(
      controller: emailFullCtrl,
      enabled: !loading && !configLoading,
      style: const TextStyle(color: Colors.white),
      decoration: _deco(_mode == AuthMode.login ? '账号' : '邮箱', hint: '邮箱'),
      keyboardType: TextInputType.emailAddress,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (_) => _validateEmail(),
    );
  }

  Widget _passwordField(TextEditingController ctrl, String label, {bool confirm = false}) {
    return TextFormField(
      controller: ctrl,
      enabled: !loading && !configLoading,
      style: const TextStyle(color: Colors.white),
      obscureText: true,
      decoration: _deco(label, hint: confirm ? null : '至少 8 位'),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) => confirm ? _validatePwdConfirm(v ?? '') : _validatePwd(v ?? ''),
    );
  }

  Widget _codeFieldIfNeeded() {
    if (_mode == AuthMode.login) return const SizedBox.shrink();
    if (_mode == AuthMode.register && !_needEmailVerifyInRegister) return const SizedBox.shrink();

    return TextFormField(
      controller: emailCodeCtrl,
      enabled: !loading && !configLoading,
      style: const TextStyle(color: Colors.white),
      decoration: _deco('邮箱验证码'),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) {
        if ((_mode == AuthMode.forgot || _needEmailVerifyInRegister) && (v ?? '').trim().isEmpty) return '请输入邮箱验证码';
        return null;
      },
    );
  }

  Widget _inviteFieldIfNeeded() {
    if (_mode != AuthMode.register) return const SizedBox.shrink();
    return TextFormField(
      controller: inviteCtrl,
      enabled: !loading && !configLoading,
      style: const TextStyle(color: Colors.white),
      decoration: _deco('邀请码（可选）'),
    );
  }

  Widget _bottomHintLogin() {
    if (_mode != AuthMode.login) return const SizedBox.shrink();
    return Row(
      children: [
        Text('没有账号？', style: TextStyle(color: Colors.white.withOpacity(0.7))),
        TextButton(onPressed: (loading || configLoading) ? null : () => _tabs.animateTo(1), child: const Text('去注册')),
        Text(' / ', style: TextStyle(color: Colors.white.withOpacity(0.35))),
        TextButton(onPressed: (loading || configLoading) ? null : () => _tabs.animateTo(2), child: const Text('忘记密码？')),
      ],
    );
  }

  Widget _primaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: (!configOk || loading || configLoading) ? null : _onPrimary,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.12),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_primaryText(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _sendCodeButton() {
    if (!_showSendCode) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: (!configOk || loading || configLoading) ? null : _sendEmailCode,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withOpacity(0.18)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Text(loading ? '发送中…' : '发送邮箱验证码'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.force,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: !widget.force,
          title: const Text(''),
          actions: [
            IconButton(
              tooltip: '联系客服',
              onPressed: () => _openExternal(ConfigManager.I.supportUrl),
              icon: const Icon(Icons.support_agent),
            ),
            IconButton(
              tooltip: '访问官网',
              onPressed: () => _openExternal(ConfigManager.I.websiteUrl),
              icon: const Icon(Icons.public),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0A1024), Color(0xFF060A14)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: -80,
              top: 120,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF4C6FFF).withOpacity(0.18)),
              ),
            ),
            Positioned(
              right: -90,
              bottom: 140,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF7A5CFF).withOpacity(0.14)),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      children: [
                        Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.08),
                            border: Border.all(color: Colors.white.withOpacity(0.14)),
                          ),
                          child: Icon(Icons.flash_on, color: Colors.white.withOpacity(0.9), size: 40),
                        ),
                        const SizedBox(height: 14),
                        const Text('King', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text('安全、高效的网络管理工具', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                        const SizedBox(height: 20),

                        _glassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _mode == AuthMode.login ? '登录' : (_mode == AuthMode.register ? '注册' : '找回密码'),
                                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                                  ),
                                  const Spacer(),
                                  _connectBadge(),
                                ],
                              ),
                              const SizedBox(height: 16),

                              TabBar(
                                controller: _tabs,
                                indicatorColor: Colors.white,
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.white.withOpacity(0.6),
                                tabs: const [Tab(text: '登录'), Tab(text: '注册'), Tab(text: '找回')],
                              ),
                              const SizedBox(height: 16),

                              Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    _emailField(),
                                    const SizedBox(height: 12),
                                    _passwordField(pwdCtrl, '密码'),
                                    if (_mode != AuthMode.login) ...[
                                      const SizedBox(height: 12),
                                      _passwordField(pwd2Ctrl, '确认密码', confirm: true),
                                    ],
                                    const SizedBox(height: 12),
                                    _codeFieldIfNeeded(),
                                    const SizedBox(height: 12),
                                    _inviteFieldIfNeeded(),
                                    const SizedBox(height: 16),

                                    _sendCodeButton(),
                                    const SizedBox(height: 12),
                                    _primaryButton(),
                                    const SizedBox(height: 8),
                                    _bottomHintLogin(),

                                    if (errText != null) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: Colors.red.withOpacity(0.25)),
                                        ),
                                        child: Text(errText!, style: const TextStyle(color: Colors.redAccent)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (widget.force) Text('需要登录后才能继续', style: TextStyle(color: Colors.white.withOpacity(0.45))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
