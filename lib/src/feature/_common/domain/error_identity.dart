final class StackFrameView {
  final bool inApp;
  final String? package;
  final String? module;
  final String? absPath;
  final String? fileName;
  final String? function;
  final int? lineNo;
  final int? colNo;

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

abstract final class ErrorIdentity {
  static String formatLogMessage(
    String message, {
    Object? error,
    String? describedType,
    String? typeIdentifier,
  }) {
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
    final pool = inApp.isNotEmpty ? inApp : frames;
    final picked = pool.first;
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
    return null;
  }

  static String? fallbackOperation(String? operation) {
    final op = operation?.trim();
    if (op == null || op.isEmpty || op == 'default') {
      return null;
    }
    return op;
  }
}
