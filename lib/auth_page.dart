import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_storage.dart';
import 'home_page.dart';
import 'session_service.dart';
import 'xboard_api.dart';

class AuthPage extends StatefulWidget {
  final bool force;
  const AuthPage({super.key, required this.force});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final emailCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();
  bool rememberPwd = true;
  bool loading = false;
  String? err;

  @override
  void initState() {
    super.initState();
    emailCtrl.text = SessionService.I.email;
    rememberPwd = SessionService.I.rememberPassword;
    if (rememberPwd) pwdCtrl.text = SessionService.I.password;

    // 尝试读取后台缓存的 guest config（不阻塞）
    // 你后续做注册/找回会用到
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    pwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _openExternal(String url) async {
    final u = url.trim();
    if (u.isEmpty) return;
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      loading = true;
      err = null;
    });

    try {
      await XBoardApi.I.initResolveDomain();

      final j = await XBoardApi.I.login(email: emailCtrl.text.trim(), password: pwdCtrl.text);

      final data = j['data'];
      if (data is! Map) throw Exception('login data missing');

      // 兼容你的后端：data.auth_data 优先，其次 token 拼 Bearer
      String auth = '';
      if (data['auth_data'] != null) auth = data['auth_data'].toString();
      if (auth.isEmpty && data['token'] != null) auth = 'Bearer ${data['token']}';
      if (auth.isEmpty) throw Exception('登录成功但缺少 auth_data');

      // cookie 在 http 库这里拿不到 response headers（你如果强依赖 cookie，可改成自定义 client）
      // 目前你的后端 Bearer 足够获取订阅，所以 cookie 暂时保存空
      const cookie = '';

      await SessionService.I.saveLogin(
        email: emailCtrl.text.trim(),
        password: pwdCtrl.text,
        authData: auth,
        cookie: cookie,
        rememberPassword: rememberPwd,
      );

      // 登录后立刻拉订阅并缓存（让主页快）
      final sub = await XBoardApi.I.getSubscribe();
      final subData = (sub['data'] is Map) ? Map<String, dynamic>.from(sub['data']) : <String, dynamic>{};
      await AppStorage.I.setJson(AppStorage.kSubscribeCache, subData);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomePage(initialSubscribeCache: subData)),
      );
    } catch (e) {
      setState(() => err = e.toString());
    } finally {
      setState(() => loading = false);
    }
  }

  String? _vEmail(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '请输入邮箱';
    if (!s.contains('@')) return '邮箱格式不正确';
    return null;
  }

  String? _vPwd(String? v) {
    final s = (v ?? '');
    if (s.isEmpty) return '请输入密码';
    if (s.length < 8) return '密码至少 8 位';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.force,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0F17),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 顶部：右上角外链
                    Row(
                      children: [
                        const Text('登录', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _openExternal(XBoardApi.I.ready ? XBoardApi.I.supportUrl : ''),
                          child: const Text('客服'),
                        ),
                        TextButton(
                          onPressed: () => _openExternal(XBoardApi.I.ready ? XBoardApi.I.websiteUrl : ''),
                          child: const Text('官网'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Card(
                      color: const Color(0xFF121827),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: emailCtrl,
                                enabled: !loading,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: '邮箱',
                                  border: OutlineInputBorder(),
                                ),
                                validator: _vEmail,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: pwdCtrl,
                                enabled: !loading,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: '密码',
                                  border: OutlineInputBorder(),
                                ),
                                validator: _vPwd,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Checkbox(
                                    value: rememberPwd,
                                    onChanged: loading ? null : (v) => setState(() => rememberPwd = v ?? true),
                                  ),
                                  const Text('记住密码'),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: loading ? null : _login,
                                  child: loading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('登录'),
                                ),
                              ),
                              if (err != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                                  ),
                                  child: Text(err!, style: const TextStyle(color: Colors.redAccent)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                    const Spacer(),
                    if (widget.force)
                      Text(
                        '需要登录后才能继续',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withOpacity(0.55)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
