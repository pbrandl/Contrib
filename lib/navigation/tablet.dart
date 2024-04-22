import 'package:flutter/material.dart';
import 'package:Contrib/navigation/nav_tablet.dart';

class TabletScaffold extends StatelessWidget {
  final Widget bodyWidget;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const TabletScaffold({
    super.key,
    required this.bodyWidget,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavRailTablet(
              extendedMode: false,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              width: 80),
          Expanded(
            child: bodyWidget,
          ),
        ],
      ),
    );
  }
}
