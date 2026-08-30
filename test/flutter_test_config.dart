import 'dart:async';

import 'package:observatory/observatory.dart';
import 'package:observatory/src/core/package_context.dart';
import 'package:package_context/package_context.dart' as package_context;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (!packageContext.isInitialized) {
    packageContext.initialize(
      const package_context.PackageGraph(
        config: Config(),
        dependencies: Dependencies(),
      ),
    );
  }

  await testMain();
}
