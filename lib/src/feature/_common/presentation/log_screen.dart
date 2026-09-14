import 'package:flutter/material.dart';
import 'package:observatory/src/feature/_common/application/observatory.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// Displays the managed Talker history with the package screen theme.
class ObservatoryLogScreen extends StatelessWidget {
  /// Title displayed in the screen app bar.
  final String appBarTitle;

  /// Creates a log screen with [appBarTitle].
  const ObservatoryLogScreen({required this.appBarTitle, super.key});

  @override
  Widget build(BuildContext context) => TalkerScreen(
    talker: Observatory.talker,
    appBarTitle: appBarTitle,
    isLogsExpanded: false,
    theme: TalkerScreenTheme.fromTheme(Theme.of(context)),
  );
}
