import 'package:flutter/material.dart';
import 'package:observatory/src/feature/_common/application/observatory.dart';

class ObservatoryLogScreen extends StatelessWidget {
  final String appBarTitle;

  const ObservatoryLogScreen({
    required this.appBarTitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Observatory.logScreen(appBarTitle: appBarTitle);
  }
}
