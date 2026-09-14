import 'package:flutter/widgets.dart';
import 'package:observatory/src/feature/_common/application/observatory.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Adds Sentry's widget wrapper only when remote capture is active.
class ObservatoryWidget extends StatelessWidget {
  /// Application subtree wrapped by Observatory.
  final Widget child;

  /// Creates a conditional Sentry wrapper for [child].
  const ObservatoryWidget({required this.child, super.key});
  @override
  Widget build(BuildContext context) => Observatory.isSentryEnabled ? SentryWidget(child: child) : child;
}
