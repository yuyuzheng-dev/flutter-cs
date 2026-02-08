import 'app_storage.dart';

/// Session（会话）与账号信息的统一管理
/// - authData/cookie：会话凭证
/// - email/password：账号信息（password 是否保存由 rememberPassword 控制）
///
/// 后续你扩展“购买套餐、个性化设置”时，也建议都走 AppStorage 的统一 key 管理
class SessionService {
  static final SessionService I = SessionService._();
  SessionService._();

  // ---- 会话凭证 ----
  String get authData => AppStorage.I.getString(AppStorage.kAuthData);
  String get cookie => AppStorage.I.getString(AppStorage.kCookie);

  bool get isLoggedIn => authData.trim().isNotEmpty;

  // ---- 账号信息 ----
  String get email => AppStorage.I.getString(AppStorage.kEmail);
  String get password => AppStorage.I.getString(AppStorage.kPassword);
  bool get rememberPassword => AppStorage.I.getBool(AppStorage.kRememberPassword, def: true);

  /// 保存登录信息
  /// - rememberPassword=false 时不会保存 password（但仍保存 email）
  Future<void> saveLogin({
    required String email,
    required String password,
    required String authData,
    required String cookie,
    required bool rememberPassword,
  }) async {
    await AppStorage.I.setString(AppStorage.kEmail, email);
    await AppStorage.I.setBool(AppStorage.kRememberPassword, rememberPassword);

    if (rememberPassword) {
      await AppStorage.I.setString(AppStorage.kPassword, password);
    } else {
      await AppStorage.I.remove(AppStorage.kPassword);
    }

    await AppStorage.I.setString(AppStorage.kAuthData, authData);
    await AppStorage.I.setString(AppStorage.kCookie, cookie);
  }

  /// 仅清会话（token/cookie），保留 email / (可选) password
  Future<void> clearSessionOnly() async {
    await AppStorage.I.remove(AppStorage.kAuthData);
    await AppStorage.I.remove(AppStorage.kCookie);
  }

  /// 退出登录（当前策略：清会话即可）
  /// 你要更“彻底”可把 email/password 也清掉
  Future<void> logoutClearAll({bool clearAccount = false}) async {
    await clearSessionOnly();
    if (clearAccount) {
      await AppStorage.I.remove(AppStorage.kEmail);
      await AppStorage.I.remove(AppStorage.kPassword);
      await AppStorage.I.remove(AppStorage.kRememberPassword);
    }
  }
}
