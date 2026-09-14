import 'package:flutter/widgets.dart';
import 'package:observatory/src/feature/_common/application/observatory.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class ObservatoryWidget extends StatelessWidget {
  final Widget child;
  const ObservatoryWidget({required this.child, super.key});
  @override
  Widget build(BuildContext context) => Observatory.isSentryEnabled ? SentryWidget(child: child) : child;
}
