/// Defines sensitive keys that are masked before data leaves its source.
final class RedactionPolicy {
  /// Default case-insensitive HTTP header names to mask.
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

  /// Default normalized URI, JSON, and FormData key fragments to mask.
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

  /// Whether masking is active.
  final bool enabled;

  /// Case-insensitive HTTP header names to mask.
  final List<String> sensitiveHeaders;

  /// Normalized URI, JSON, and FormData key fragments to mask.
  final List<String> sensitiveBodyKeys;

  /// Creates an enabled redaction policy with safe defaults.
  const RedactionPolicy({
    this.enabled = true,
    this.sensitiveHeaders = defaultSensitiveHeaders,
    this.sensitiveBodyKeys = defaultSensitiveBodyKeys,
  });

  /// Creates an explicit policy that performs no masking.
  const RedactionPolicy.disabled() : enabled = false, sensitiveHeaders = const [], sensitiveBodyKeys = const [];

  /// Returns whether the HTTP header [key] must be masked.
  bool isSensitiveHeader(String key) {
    if (!enabled) {
      return false;
    }
    return sensitiveHeaders.any((sensitiveKey) {
      return key.toLowerCase() == sensitiveKey.toLowerCase();
    });
  }

  /// Returns whether the structured payload [key] must be masked.
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
