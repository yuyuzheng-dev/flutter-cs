import 'dart:convert';
import 'package:http/http.dart' as http;

import 'app_storage.dart';
import 'config_manager.dart';
import 'domain_racer.dart';
import 'session_service.dart';

class GuestConfigParsed {
  final int isEmailVerify; // 0/1
  final List<String> emailWhitelistSuffix;
  final String? appDescription;

  const GuestConfigParsed({
    required this.isEmailVerify,
    required this.emailWhitelistSuffix,
    this.appDescription,
  });

  static GuestConfigParsed fromResponse(Map<String, dynamic> j) {
    final data = j['data'];
    if (data is! Map) return const GuestConfigParsed(isEmailVerify: 0, emailWhitelistSuffix: []);

    int toInt(dynamic v) {
      if (v is bool) return v ? 1 : 0;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final isEv = toInt(data['is_email_verify']);
    final raw = data['email_whitelist_suffix'];

    List<String> suffix = [];
    if (raw is List) {
      suffix = raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();
    }

    return GuestConfigParsed(
      isEmailVerify: isEv,
      emailWhitelistSuffix: suffix,
      appDescription: data['app_description']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'is_email_verify': isEmailVerify,
        'email_whitelist_suffix': emailWhitelistSuffix,
        'app_description': appDescription,
      };
}

class XBoardApiException implements Exception {
  final String message;
  final dynamic raw;

  const XBoardApiException(this.message, {this.raw});

  @override
  String toString() => raw == null ? message : '$message, raw: $raw';
}

class XBoardApi {
  static final XBoardApi I = XBoardApi._();
  XBoardApi._();

  static const subscribeTimeout = Duration(seconds: 8);
  static const normalTimeout = Duration(seconds: 10);

  bool _ready = false;
  late ResolvedDomain _resolved;

  bool get ready => _ready;

  String get baseUrl => _resolved.baseUrl;
  String get apiPrefix => _resolved.config.apiPrefix;

  String get supportUrl => _resolved.config.supportUrl;
  String get websiteUrl => _resolved.config.websiteUrl;

  // ✅ 给 auth_page 用的 getter
  String get email => SessionService.I.email;
  String get password => SessionService.I.password;
  bool get rememberPassword => SessionService.I.rememberPassword;
  bool get isLoggedIn => SessionService.I.isLoggedIn;

  Uri _api(String pathUnderApiV1) {
    var p = pathUnderApiV1.trim();
    if (!p.startsWith('/')) p = '/$p';
    return Uri.parse('$baseUrl$apiPrefix$p');
  }

  Map<String, String> _headers({bool json = false, bool auth = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    if (auth) {
      final a = SessionService.I.authData.trim();
      if (a.isNotEmpty) h['Authorization'] = a;
      final c = SessionService.I.cookie.trim();
      if (c.isNotEmpty) h['Cookie'] = c;
    }
    return h;
  }

  Future<void> initResolveDomain() async {
    if (_ready) return;
    final rc = await ConfigManager.I.loadRemoteConfig();
    _resolved = await DomainRacer.I.resolve(rc);
    _ready = true;
  }

  /// ✅ 刷新按钮：重新拉远程配置 + 重新竞速
  Future<void> refreshDomainRacer() async {
    final rc = await ConfigManager.I.loadRemoteConfig(forceRefresh: true);
    _resolved = await DomainRacer.I.resolve(rc, forceRefresh: true);
    _ready = true;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    bool auth = false,
  }) async {
    if (!_ready) await initResolveDomain();

    final resp = await http
        .post(
          _api(path),
          headers: _headers(json: true, auth: auth),
          body: jsonEncode(body),
        )
        .timeout(normalTimeout);

    final dynamic j = jsonDecode(resp.body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = (j is Map && j['message'] != null) ? j['message'].toString() : 'HTTP ${resp.statusCode}';
      throw Exception(msg);
    }
    if (j is! Map<String, dynamic>) throw Exception('response not object');
    return j;
  }

  Future<dynamic> _get(String path, {bool auth = true}) async {
    if (!_ready) await initResolveDomain();

    final resp = await http.get(_api(path), headers: _headers(auth: auth)).timeout(normalTimeout);
    final dynamic j = jsonDecode(resp.body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = (j is Map && j['message'] != null) ? j['message'].toString() : 'HTTP ${resp.statusCode}';
      throw XBoardApiException(msg, raw: j);
    }
    return j;
  }

  Future<dynamic> _post(String path, {Object? data, bool auth = true}) async {
    if (!_ready) await initResolveDomain();

    final resp = await http
        .post(_api(path), headers: _headers(json: true, auth: auth), body: data)
        .timeout(normalTimeout);
    final dynamic j = jsonDecode(resp.body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = (j is Map && j['message'] != null) ? j['message'].toString() : 'HTTP ${resp.statusCode}';
      throw XBoardApiException(msg, raw: j);
    }
    return j;
  }

  Future<GuestConfigParsed> fetchGuestConfig() async {
    if (!_ready) await initResolveDomain();
    final resp = await http.get(_api('/guest/comm/config'), headers: _headers()).timeout(normalTimeout);
    final dynamic j = jsonDecode(resp.body);
    if (resp.statusCode != 200 || j is! Map<String, dynamic>) {
      throw Exception('guest config http ${resp.statusCode}');
    }
    return GuestConfigParsed.fromResponse(j);
  }

  Future<Map<String, dynamic>> login({required String email, required String password}) async {
    return _postJson('/passport/auth/login', {'email': email, 'password': password}, auth: false);
  }

  /// ✅ auth_page 会调用这个保存 token
  Future<void> saveLoginFromResponse(
    String email,
    String password,
    Map<String, dynamic> loginResp,
    bool rememberPassword,
  ) async {
    final data = loginResp['data'];
    if (data is! Map) throw Exception('登录返回缺少 data');

    String auth = '';
    if (data['auth_data'] != null) auth = data['auth_data'].toString();
    if (auth.isEmpty && data['token'] != null) auth = 'Bearer ${data['token']}';
    if (auth.isEmpty) throw Exception('登录成功但缺少 auth_data/token');

    await SessionService.I.saveLogin(
      email: email,
      password: password,
      authData: auth,
      cookie: '',
      rememberPassword: rememberPassword,
    );
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? inviteCode,
    String? emailCode,
  }) async {
    final body = <String, dynamic>{'email': email, 'password': password};
    if (inviteCode != null && inviteCode.trim().isNotEmpty) body['invite_code'] = inviteCode.trim();
    if (emailCode != null && emailCode.trim().isNotEmpty) body['email_code'] = emailCode.trim();
    return _postJson('/passport/auth/register', body, auth: false);
  }

  Future<Map<String, dynamic>> sendEmailCode({required String email, required String scene}) async {
    return _postJson('/passport/auth/sendEmailCode', {'email': email, 'scene': scene}, auth: false);
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String password,
    required String emailCode,
  }) async {
    return _postJson('/passport/auth/resetPassword', {'email': email, 'password': password, 'email_code': emailCode});
  }

  Future<void> logout() async {
    try {
      await _postJson('/passport/auth/logout', {}, auth: true);
    } catch (_) {}
  }

  Future<void> clearSessionOnly() => SessionService.I.clearSessionOnly();

  Future<Map<String, dynamic>> getSubscribe() async {
    if (!_ready) await initResolveDomain();
    final resp = await http.get(_api('/user/getSubscribe'), headers: _headers(auth: true)).timeout(subscribeTimeout);

    final dynamic j = jsonDecode(resp.body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = (j is Map && j['message'] != null) ? j['message'].toString() : 'HTTP ${resp.statusCode}';
      throw Exception(msg);
    }
    if (j is! Map<String, dynamic>) throw Exception('subscribe response not object');
    return j;
  }

  /// 获取余额信息
  Future<Map<String, dynamic>> fetchBalance() async {
    final data = await _get('/user/balance/fetch');
    if (data is Map<String, dynamic>) return data;
    throw XBoardApiException('Unexpected balance response format', raw: data);
  }

  /// 获取套餐列表
  Future<List<dynamic>> fetchPlans() async {
    final data = await _get('/user/plan/fetch');
    if (data is Map && data['data'] is List) {
      return data['data'] as List<dynamic>;
    }
    if (data is List) return data;
    throw XBoardApiException('Unexpected plan list format', raw: data);
  }

  /// 获取当前用户订单列表
  Future<List<dynamic>> fetchUserOrders() async {
    final data = await _get('/user/order/fetch');
    if (data is Map && data['data'] is List) {
      return data['data'] as List<dynamic>;
    }
    if (data is List) return data;
    throw XBoardApiException('Unexpected order list format', raw: data);
  }

  /// 创建订单
  Future<Map<String, dynamic>> createOrder({
    required String planId,
    String? couponCode,
  }) async {
    final body = <String, dynamic>{
      'plan_id': planId,
    };
    if (couponCode != null && couponCode.isNotEmpty) {
      body['coupon_code'] = couponCode;
    }

    final data = await _post(
      '/user/order/create',
      data: jsonEncode(body),
    );

    if (data is Map<String, dynamic>) return data;
    throw XBoardApiException('Unexpected createOrder response format', raw: data);
  }

  /// 获取支付方式列表
  Future<List<dynamic>> fetchPaymentMethods() async {
    final data = await _get('/user/order/getPaymentMethod');
    if (data is Map && data['data'] is List) {
      return data['data'] as List<dynamic>;
    }
    if (data is List) return data;
    throw XBoardApiException('Unexpected payment methods format', raw: data);
  }
}
