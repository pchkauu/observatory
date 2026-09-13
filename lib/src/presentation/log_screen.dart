import 'package:flutter/material.dart';
import 'package:observatory/src/application/observatory.dart';
import 'package:talker_flutter/talker_flutter.dart';

class ObservatoryLogScreen extends StatelessWidget {
  final String appBarTitle;
  const ObservatoryLogScreen({required this.appBarTitle, super.key});

  @override
  Widget build(BuildContext context) => TalkerScreen(
    talker: Observatory.talker,
    appBarTitle: appBarTitle,
    isLogsExpanded: false,
    theme: TalkerScreenTheme.fromTheme(Theme.of(context)),
  );
}
