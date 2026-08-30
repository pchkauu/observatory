final class RedactionPolicy {
  static const defaultSensitiveHeaders = [
    'Authorization',
    'Proxy-Authorization',
    'Cookie',
    'Set-Cookie',
    'X-Api-Key',
    'X-Signature',
    'X-Device-Token',
    'X-FCM-Token',
    'X-Firebase-Token',
  ];

  static const defaultSensitiveBodyKeys = [
    'token',
    'apiKey',
    'credential',
    'password',
    'private',
    'privateKey',
    'secret',
    'signature',
    'authorization',
    'authToken',
    'fcmToken',
    'firebaseToken',
    'deviceToken',
    'dsn',
    'cookie',
  ];

  final bool enabled;
  final List<String> sensitiveHeaders;
  final List<String> sensitiveBodyKeys;

  const RedactionPolicy({
    this.enabled = true,
    this.sensitiveHeaders = defaultSensitiveHeaders,
    this.sensitiveBodyKeys = defaultSensitiveBodyKeys,
  });

  const RedactionPolicy.disabled() : enabled = false, sensitiveHeaders = const [], sensitiveBodyKeys = const [];

  bool isSensitiveHeader(String key) {
    if (!enabled) {
      return false;
    }
    return sensitiveHeaders.any((sensitiveKey) {
      return key.toLowerCase() == sensitiveKey.toLowerCase();
    });
  }

  bool isSensitiveBodyKey(String key) {
    if (!enabled) {
      return false;
    }
    final normalizedKey = _normalizeKey(key);
    return sensitiveBodyKeys.any((sensitiveKey) {
      return normalizedKey.contains(_normalizeKey(sensitiveKey));
    });
  }

  static String _normalizeKey(String key) {
    return key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  }
}
