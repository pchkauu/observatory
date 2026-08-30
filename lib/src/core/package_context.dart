import 'package:observatory/src/config/config.dart';
import 'package:observatory/src/dependencies/dependencies.dart';
import 'package:package_context/package_context.dart' as package_context;

final packageContext = package_context.PackageContext<Config, Dependencies>();

Config get config => packageContext.config;

Dependencies get dependencies => packageContext.dependencies;
