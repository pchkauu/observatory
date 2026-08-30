import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/core/package_context.dart';
import 'package:observatory/src/dependencies/dependencies.dart';
import 'package:package_context/package_context.dart' as package_context;

Future<void> initPackage({
  required Config config,
  required Dependencies dependencies,
}) {
  return packageContext.ensureInitialized(
    graph: package_context.PackageGraph(
      config: config,
      dependencies: dependencies,
    ),
    isBound: false,
    bind: () async {},
  );
}
