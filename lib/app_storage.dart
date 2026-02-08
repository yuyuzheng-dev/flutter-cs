import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  static final AppStorage I = AppStorage._();
  AppStorage._();

  late SharedPreferences _sp;

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
  }

  // -------- 通用 ----------
  String getString(String k, {String def = ''}) => _sp.getString(k) ?? def;
  Future<void> setString(String k, String v) => _sp.setString(k, v);

  bool getBool(String k, {bool def = false}) => _sp.getBool(k) ?? def;
  Future<void> setBool(String k, bool v) => _sp.setBool(k, v);

  int getInt(String k, {int def = 0}) => _sp.getInt(k) ?? def;
  Future<void> setInt(String k, int v) => _sp.setInt(k, v);

  Map<String, dynamic>? getJson(String k) {
    final s = _sp.getString(k);
    if (s == null || s.isEmpty) return null;
    try {
      final j = jsonDecode(s);
      return (j is Map) ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String k, Map<String, dynamic> v) => _sp.setString(k, jsonEncode(v));

  Future<void> remove(String k) => _sp.remove(k);

  // -------- Key 统一管理（后续加功能就在这里加 key） ----------
  static const kBestDomain = 'best_domain';
  static const kBestDomainTs = 'best_domain_ts';
  static const kRemoteConfigCache = 'remote_config_cache'; // json

  static const kAuthData = 'auth_data';
  static const kCookie = 'cookie';
  static const kEmail = 'email';
  static const kPassword = 'password';
  static const kRememberPassword = 'remember_password';

  static const kGuestConfigCache = 'guest_config_cache'; // json
  static const kSubscribeCache = 'subscribe_cache'; // json(含subscribe_url等)
}
