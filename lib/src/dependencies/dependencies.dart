import 'package:package_context/package_context.dart' as package_context;
import 'package:talker_flutter/talker_flutter.dart' hide LogLevel;

final class Dependencies extends package_context.PackageDependencies {
  final Talker? talker;

  const Dependencies({
    this.talker,
  });
}
