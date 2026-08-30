import 'package:flutter/material.dart';
import 'package:observatory/src/feature/_common/application/observatory.dart';

class ObservatoryWidget extends StatelessWidget {
  final Widget child;

  const ObservatoryWidget({
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Observatory.wrapApp(child: child);
  }
}
