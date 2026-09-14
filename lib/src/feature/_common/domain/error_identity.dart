/// Detached stack-frame fields used for stable error location selection.
final class StackFrameView {
  /// Whether the source SDK classified this as an application frame.
  final bool inApp;

  /// Package name reported for the frame.
  final String? package;

  /// Module name reported for the frame.
  final String? module;

  /// Absolute source path reported for the frame.
  final String? absPath;

  /// Source filename reported for the frame.
  final String? fileName;

  /// Function name reported for the frame.
  final String? function;

  /// One-based source line when available.
  final int? lineNo;

  /// One-based source column when available.
  final int? colNo;

  /// Creates a detached view from optional stack-frame fields.
  const StackFrameView({
    this.inApp = false,
    this.package,
    this.module,
    this.absPath,
    this.fileName,
    this.function,
    this.lineNo,
    this.colNo,
  });
}

/// Builds stable error metadata and source locations.
abstract final class ErrorIdentity {
  /// Adds available error type metadata to [message] once.
  static String formatLogMessage(String message, {Object? error, String? describedType, String? typeIdentifier}) {
    final metadata = <String>[
      if (describedType != null && describedType.isNotEmpty) 'error.type=$describedType',
      if (typeIdentifier != null && typeIdentifier.isNotEmpty) 'failure.type_identifier=$typeIdentifier',
    ];
    if (metadata.isEmpty) {
      return message;
    }
    if (metadata.every(message.contains)) {
      return message;
    }
    return '$message\n${metadata.join('\n')}';
  }

  /// Returns a useful first-line description for an otherwise unknown [error].
  static String? describeUnknown(Object? error) {
    if (error == null) {
      return null;
    }
    final description = error.toString().trim();
    if (description.isEmpty || description.startsWith('Instance of ')) {
      return 'unknown';
    }
    return description.split('\n').first.trim();
  }

  /// Whether [function] is too short or generic for a stable identity.
  static bool looksObfuscatedOrGeneric(String function) {
    final f = function.trim();
    if (f.isEmpty) {
      return true;
    }
    if (f == 'default') {
      return true;
    }
    if (f.length <= 2) {
      return true;
    }
    return RegExp(r'^[A-Za-z0-9]{1,3}$').hasMatch(f);
  }

  /// Selects the nearest useful application location from [frames].
  ///
  /// Application frames are preferred. When [preferFileLine] is true, source
  /// coordinates take priority over function names.
  static String? locationFrom({
    required List<StackFrameView> frames,
    required String appPackageName,
    required bool preferFileLine,
  }) {
    if (frames.isEmpty) {
      return null;
    }

    bool isAppFrame(StackFrameView frame) {
      if (frame.inApp) {
        return true;
      }
      if (appPackageName.isEmpty) {
        return false;
      }
      return (frame.package?.contains(appPackageName) ?? false) ||
          (frame.module?.contains(appPackageName) ?? false) ||
          (frame.absPath?.contains(appPackageName) ?? false);
    }

    final inApp = frames.where(isAppFrame).toList();
    final pool = [...inApp, ...frames.where((frame) => !isAppFrame(frame))];
    for (final picked in pool) {
      final line = picked.lineNo;
      final col = picked.colNo;
      final filename = picked.fileName?.trim();

      if (preferFileLine) {
        if (filename != null && filename.isNotEmpty && line != null) {
          return col != null ? '$filename:$line:$col' : '$filename:$line';
        }
      }

      final function = picked.function?.trim();
      if (function != null && function.isNotEmpty) {
        final cleaned = function.replaceAll('<anonymous closure>', '').trim();
        if (cleaned.isNotEmpty && !looksObfuscatedOrGeneric(cleaned)) {
          return line != null ? '$cleaned.$line' : cleaned;
        }
      }

      if (filename != null && filename.isNotEmpty && line != null) {
        return col != null ? '$filename:$line:$col' : '$filename:$line';
      }

      final module = picked.module?.trim();
      if (module != null && module.isNotEmpty && line != null) {
        return '$module:$line';
      }
      final pkg = picked.package?.trim();
      if (pkg != null && pkg.isNotEmpty && line != null) {
        return '$pkg:$line';
      }
    }
    return null;
  }

  /// Returns a usable operation name or `null` for empty default values.
  static String? fallbackOperation(String? operation) {
    final op = operation?.trim();
    if (op == null || op.isEmpty || op == 'default') {
      return null;
    }
    return op;
  }
}
