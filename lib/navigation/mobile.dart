import 'package:flutter/material.dart';
import 'package:flutter_application_test/navigation/nav_bar.dart';

class MobileScaffold extends StatelessWidget {
  final Widget bodyWidget;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const MobileScaffold({
    super.key,
    required this.bodyWidget,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: bodyWidget,
      bottomNavigationBar: MobileNavBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
      ),
    );
  }
}
