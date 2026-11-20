import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Keeps a supplier session for the same Med.ai owner across app restarts.
/// Cookies themselves remain inside WebView; no supplier credentials are read.
class RetailerSession {
  static const _storage = FlutterSecureStorage();
  static const _ownerKey = 'medai_retailer_session_owner';
  static WebViewController? _controller;
  static Future<void> _queue = Future<void>.value();

  static Future<void> _serialized(Future<void> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.catchError((Object _) {});
    return result;
  }

  static Future<void> prepare(String owner, WebViewController controller) =>
      _serialized(() async {
        final previous = await _storage.read(key: _ownerKey);
        if (previous != owner) {
          await WebViewCookieManager().clearCookies();
          await controller.clearLocalStorage();
          await _storage.write(key: _ownerKey, value: owner);
        }
        _controller = controller;
      });

  static Future<void> clear() => _serialized(() async {
    // Clear persistent cookies even if no supplier screen was opened this run.
    await WebViewCookieManager().clearCookies();
    if (_controller != null) await _controller!.clearLocalStorage();
    await _storage.delete(key: _ownerKey);
    _controller = null;
  });
}
