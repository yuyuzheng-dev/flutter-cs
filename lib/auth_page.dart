import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_storage.dart';
import 'home_page.dart';
import 'xboard_api.dart';

enum AuthTab { login, register, reset }

class AuthPage extends StatefulWidget {
  final bool force;
  const AuthPage({super.key, required this.force});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  AuthTab tab = AuthTab.login;

  GuestConfigParsed guest = const GuestConfigParsed(isEmailVerify: 0, emailWhitelistSuffix: []);
  bool loadingGuest = true;

  bool busy = false;
  String? msg; // 提示/错误统一输出

  // login
  final _loginKey = GlobalKey<FormState>();
  final loginEmailCtrl = TextEditingController();
  final loginPwdCtrl = TextEditingController();
  bool rememberPwd = true;

  // register
  final _regKey = GlobalKey<FormState>();
  final regEmailPlainCtrl = TextEditingController();
  final regEmailPrefixCtrl = TextEditingController();
  String? regEmailSuffix;
  final regCodeCtrl = TextEditingController();
  final regPwd1Ctrl = TextEditingController();
  final regPwd2Ctrl = TextEditingController();
  final regInviteCtrl = TextEditingController();
  bool regPwdTouched = false;

  // reset
  final _resetKey = GlobalKey<FormState>();
  final resetEmailPlainCtrl = TextEditingController();
  final resetEmailPrefixCtrl = TextEditingController();
  String? resetEmailSuffix;
  final resetCodeCtrl = TextEditingController();
  final resetPwd1Ctrl = TextEditingController();
  final resetPwd2Ctrl = TextEditingController();
  bool resetPwdTouched = false;

  bool get hasWhitelist => guest.emailWhitelistSuffix.isNotEmpty;

  @override
  void initState() {
    super.initState();

    loginEmailCtrl.text = XBoardApi.I.email;
    rememberPwd = XBoardApi.I.rememberPassword;
    if (rememberPwd) loginPwdCtrl.text = XBoardApi.I.password;

    final cached = AppStorage.I.getJson(AppStorage.kGuestConfigCache);
    if (cached != null) {
      final isEv = (cached['is_email_verify'] is num) ? (cached['is_email_verify'] as num).toInt() : 0;
      final wl = (cached['email_whitelist_suffix'] is List)
          ? (cached['email_whitelist_suffix'] as List).map((e) => e.toString()).toList()
          : <String>[];
      guest = GuestConfigParsed(isEmailVerify: isEv, emailWhitelistSuffix: wl);
      if (guest.emailWhitelistSuffix.isNotEmpty) {
        regEmailSuffix ??= guest.emailWhitelistSuffix.first;
        resetEmailSuffix ??= guest.emailWhitelistSuffix.first;
      }
    }

    _reloadAll();
  }

  @override
  void dispose() {
    loginEmailCtrl.dispose();
    loginPwdCtrl.dispose();
    regEmailPlainCtrl.dispose();
    regEmailPrefixCtrl.dispose();
    regCodeCtrl.dispose();
    regPwd1Ctrl.dispose();
    regPwd2Ctrl.dispose();
    regInviteCtrl.dispose();
    resetEmailPlainCtrl.dispose();
    resetEmailPrefixCtrl.dispose();
    resetCodeCtrl.dispose();
    resetPwd1Ctrl.dispose();
    resetPwd2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _openExternal(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _reloadAll() async {
    setState(() {
      loadingGuest = true;
      msg = null;
    });

    try {
      await XBoardApi.I.refreshDomainRacer();
      final g = await XBoardApi.I.fetchGuestConfig();
      guest = g;
      await AppStorage.I.setJson(AppStorage.kGuestConfigCache, g.toJson());
      if (guest.emailWhitelistSuffix.isNotEmpty) {
        regEmailSuffix ??= guest.emailWhitelistSuffix.first;
        resetEmailSuffix ??= guest.emailWhitelistSuffix.first;
      }
      msg = '联通正常';
    } catch (e) {
      msg = '联通检测失败：$e';
    } finally {
      if (mounted) setState(() => loadingGuest = false);
    }
  }

  String _buildEmail({required TextEditingController plain, required TextEditingController prefix, required String? suffix}) {
    if (!hasWhitelist) return plain.text.trim();
    final p = prefix.text.trim();
    final s = (suffix ?? '').trim();
    if (p.isEmpty || s.isEmpty) return '';
    return '$p@$s';
  }

  String? _vEmailPlain(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '请输入邮箱';
    if (!s.contains('@')) return '邮箱格式不正确';
    return null;
  }

  String? _vEmailPrefix(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '请输入邮箱前缀';
    if (s.contains('@')) return '这里不需要 @';
    return null;
  }

  String? _vPwdMin8(String? v) {
    final s = (v ?? '');
    if (s.isEmpty) return '请输入密码';
    if (s.length < 8) return '密码至少 8 位';
    return null;
  }

  String? _vPwd2Match(String? v, TextEditingController pwd1) {
    final s = (v ?? '');
    if (s.isEmpty) return '请再次输入密码';
    if (s.length < 8) return '密码至少 8 位';
    if (s != pwd1.text) return '两次密码不一致';
    return null;
  }

  Widget _emailField({
    required String label,
    required TextEditingController plainCtrl,
    required TextEditingController prefixCtrl,
    required String? suffixValue,
    required ValueChanged<String?> onSuffixChanged,
    required bool enabled,
  }) {
    if (!hasWhitelist) {
      return TextFormField(
        controller: plainCtrl,
        enabled: enabled,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(labelText: label),
        validator: _vEmailPlain,
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: prefixCtrl,
            enabled: enabled,
            decoration: const InputDecoration(labelText: '邮箱前缀'),
            validator: _vEmailPrefix,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<String>(
            value: suffixValue ?? (guest.emailWhitelistSuffix.isNotEmpty ? guest.emailWhitelistSuffix.first : null),
            items: guest.emailWhitelistSuffix
                .map((e) => DropdownMenuItem<String>(value: e, child: Text('@$e', overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: enabled ? onSuffixChanged : null,
            decoration: const InputDecoration(labelText: '后缀'),
          ),
        ),
      ],
    );
  }

  Future<void> _doLogin() async {
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      if (!_loginKey.currentState!.validate()) return;

      final j = await XBoardApi.I.login(email: loginEmailCtrl.text.trim(), password: loginPwdCtrl.text);
      await XBoardApi.I.saveLoginFromResponse(
        loginEmailCtrl.text.trim(),
        loginPwdCtrl.text,
        j,
        rememberPwd,
      );

      final sub = await XBoardApi.I.getSubscribe();
      final subData = (sub['data'] is Map) ? Map<String, dynamic>.from(sub['data']) : <String, dynamic>{};
      await AppStorage.I.setJson(AppStorage.kSubscribeCache, subData);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => HomePage(initialSubscribeCache: subData)));
    } catch (e) {
      setState(() => msg = '登录失败：$e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _sendCode(String email, String scene) async {
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      await XBoardApi.I.sendEmailCode(email: email, scene: scene);
      setState(() => msg = '验证码已发送，请查收邮箱');
    } catch (e) {
      setState(() => msg = '发送失败：$e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _doRegister() async {
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      if (!_regKey.currentState!.validate()) return;
      final email = _buildEmail(plain: regEmailPlainCtrl, prefix: regEmailPrefixCtrl, suffix: regEmailSuffix);
      if (email.isEmpty) throw Exception('邮箱不完整');

      await XBoardApi.I.register(
        email: email,
        password: regPwd1Ctrl.text,
        inviteCode: regInviteCtrl.text.trim().isEmpty ? null : regInviteCtrl.text.trim(),
        emailCode: guest.isEmailVerify == 1 ? regCodeCtrl.text.trim() : null,
      );

      setState(() {
        tab = AuthTab.login;
        msg = '注册成功，请登录';
        loginEmailCtrl.text = email;
      });
    } catch (e) {
      setState(() => msg = '注册失败：$e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _doReset() async {
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      if (guest.isEmailVerify != 1) {
        throw Exception('当前站点未开启邮箱验证，请联系管理员重置密码。');
      }
      if (!_resetKey.currentState!.validate()) return;

      final email = _buildEmail(plain: resetEmailPlainCtrl, prefix: resetEmailPrefixCtrl, suffix: resetEmailSuffix);
      if (email.isEmpty) throw Exception('邮箱不完整');

      final code = resetCodeCtrl.text.trim();
      if (code.isEmpty) throw Exception('请输入验证码');

      await XBoardApi.I.resetPassword(email: email, password: resetPwd1Ctrl.text, emailCode: code);

      setState(() {
        tab = AuthTab.login;
        msg = '密码重置成功，请登录';
        loginEmailCtrl.text = email;
      });
    } catch (e) {
      setState(() => msg = '$e');
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (tab) {
      AuthTab.login => '登录',
      AuthTab.register => '注册帐号',
      AuthTab.reset => '找回密码',
    };

    return PopScope(
      canPop: !widget.force,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F17),
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: busy ? null : _reloadAll,
              icon: const Icon(Icons.refresh),
            ),
            TextButton(onPressed: () => _openExternal(XBoardApi.I.supportUrl), child: const Text('客服')),
            TextButton(onPressed: () => _openExternal(XBoardApi.I.websiteUrl), child: const Text('官网')),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  color: const Color(0xFF121827),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (loadingGuest)
                          Row(
                            children: [
                              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 10),
                              Text('联通检测中…', style: TextStyle(color: Colors.white.withOpacity(0.7))),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.greenAccent.withOpacity(0.9)),
                              const SizedBox(width: 8),
                              Text(msg ?? '联通正常'),
                            ],
                          ),
                        const SizedBox(height: 12),

                        Expanded(child: _buildTabBody()),
                        const SizedBox(height: 8),

                        if (msg != null && !loadingGuest)
                          Text(
                            msg!,
                            style: TextStyle(color: msg!.contains('成功') || msg!.contains('正常') ? Colors.greenAccent : Colors.redAccent),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody() {
    return SingleChildScrollView(
      child: switch (tab) {
        AuthTab.login => _loginBody(),
        AuthTab.register => _registerBody(),
        AuthTab.reset => _resetBody(),
      },
    );
  }

  Widget _loginBody() {
    return Form(
      key: _loginKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: loginEmailCtrl,
            enabled: !busy,
            decoration: const InputDecoration(labelText: '邮箱'),
            validator: _vEmailPlain,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: loginPwdCtrl,
            enabled: !busy,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码（至少8位）'),
            validator: _vPwdMin8,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(value: rememberPwd, onChanged: busy ? null : (v) => setState(() => rememberPwd = v ?? true)),
              const Text('记住密码'),
              const Spacer(),
              TextButton(onPressed: busy ? null : () => setState(() => tab = AuthTab.reset), child: const Text('忘记密码？')),
              TextButton(onPressed: busy ? null : () => setState(() => tab = AuthTab.register), child: const Text('去注册')),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: busy ? null : _doLogin,
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('登录'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _registerBody() {
    return Form(
      key: _regKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _emailField(
            label: '邮箱',
            plainCtrl: regEmailPlainCtrl,
            prefixCtrl: regEmailPrefixCtrl,
            suffixValue: regEmailSuffix,
            onSuffixChanged: (v) => setState(() => regEmailSuffix = v),
            enabled: !busy,
          ),
          const SizedBox(height: 12),

          if (guest.isEmailVerify == 1) ...[
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: regCodeCtrl,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: '邮箱验证码'),
                    validator: (v) => (v ?? '').trim().isEmpty ? '请输入验证码' : null,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: busy
                        ? null
                        : () {
                            if (!_regKey.currentState!.validate()) return;
                            final email = _buildEmail(plain: regEmailPlainCtrl, prefix: regEmailPrefixCtrl, suffix: regEmailSuffix);
                            if (email.isEmpty) {
                              setState(() => msg = '邮箱不完整');
                              return;
                            }
                            _sendCode(email, 'register');
                          },
                    child: const Text('发送验证码'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          TextFormField(
            controller: regPwd1Ctrl,
            enabled: !busy,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码（至少8位）'),
            onChanged: (_) => setState(() => regPwdTouched = true),
            validator: _vPwdMin8,
          ),
          if (regPwdTouched && regPwd1Ctrl.text.length < 8)
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('密码至少 8 位', style: TextStyle(color: Colors.redAccent))),

          const SizedBox(height: 12),
          TextFormField(
            controller: regPwd2Ctrl,
            enabled: !busy,
            obscureText: true,
            decoration: const InputDecoration(labelText: '确认密码'),
            validator: (v) => _vPwd2Match(v, regPwd1Ctrl),
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: regInviteCtrl,
            enabled: !busy,
            decoration: const InputDecoration(labelText: '邀请码（可选）'),
          ),
          const SizedBox(height: 12),

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: busy ? null : _doRegister,
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('注册'),
            ),
          ),
          TextButton(onPressed: busy ? null : () => setState(() => tab = AuthTab.login), child: const Text('返回登录')),
        ],
      ),
    );
  }

  Widget _resetBody() {
    if (guest.isEmailVerify != 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('当前站点未开启邮箱验证，请联系管理员重置密码。'),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: busy ? null : () => setState(() => tab = AuthTab.login),
              child: const Text('返回登录'),
            ),
          ),
        ],
      );
    }

    return Form(
      key: _resetKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _emailField(
            label: '邮箱',
            plainCtrl: resetEmailPlainCtrl,
            prefixCtrl: resetEmailPrefixCtrl,
            suffixValue: resetEmailSuffix,
            onSuffixChanged: (v) => setState(() => resetEmailSuffix = v),
            enabled: !busy,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: resetCodeCtrl,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: '邮箱验证码'),
                  validator: (v) => (v ?? '').trim().isEmpty ? '请输入验证码' : null,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                height: 48,
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          if (!_resetKey.currentState!.validate()) return;
                          final email =
                              _buildEmail(plain: resetEmailPlainCtrl, prefix: resetEmailPrefixCtrl, suffix: resetEmailSuffix);
                          if (email.isEmpty) {
                            setState(() => msg = '邮箱不完整');
                            return;
                          }
                          _sendCode(email, 'reset_password');
                        },
                  child: const Text('发送验证码'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: resetPwd1Ctrl,
            enabled: !busy,
            obscureText: true,
            decoration: const InputDecoration(labelText: '新密码（至少8位）'),
            onChanged: (_) => setState(() => resetPwdTouched = true),
            validator: _vPwdMin8,
          ),
          if (resetPwdTouched && resetPwd1Ctrl.text.length < 8)
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('密码至少 8 位', style: TextStyle(color: Colors.redAccent))),

          const SizedBox(height: 12),
          TextFormField(
            controller: resetPwd2Ctrl,
            enabled: !busy,
            obscureText: true,
            decoration: const InputDecoration(labelText: '确认新密码'),
            validator: (v) => _vPwd2Match(v, resetPwd1Ctrl),
          ),
          const SizedBox(height: 12),

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: busy ? null : _doReset,
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text
