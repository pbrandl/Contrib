import 'package:flutter/material.dart';
import 'destinations.dart';

class MobileNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const MobileNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: NavigationBarTheme(
        data: const NavigationBarThemeData(
          backgroundColor: Colors.transparent,
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: getAllDestinations(context).map((destination) {
            return NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.title,
              tooltip: '',
            );
          }).toList(),
        ),
      ),
    );
  }
}
