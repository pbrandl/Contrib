import 'package:flutter/material.dart';
import 'package:flutter_application_test/navigation/nav_desktop.dart';

class DesktopScaffold extends StatelessWidget {
  final Widget bodyWidget;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const DesktopScaffold({
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
          Column(
            children: [
              Flexible(
                child: NavRailDesktop(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  width: 230,
                ),
              ),
            ],
          ),
          Expanded(child: bodyWidget),
        ],
      ),
    );
  }
}
