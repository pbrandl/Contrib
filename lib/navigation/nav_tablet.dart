import 'package:Contrib/globals/global_widgets.dart';
import 'destinations.dart';
import 'package:flutter/material.dart';

class NavRailTablet extends StatelessWidget {
  final bool extendedMode;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final double width;

  final NavigationRailLabelType labelType = NavigationRailLabelType.all;

  const NavRailTablet({
    super.key,
    required this.extendedMode,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: width,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppLogo(width: width, height: 75),
              Expanded(
                child: NavigationRail(
                  leading: const SpaceHSmall(),
                  labelType: labelType,
                  extended: false,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  destinations: getAllDestinations(context).map((destination) {
                    return NavigationRailDestination(
                      icon: Icon(destination.icon),
                      label: EllipsisText(destination.title),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1)
      ],
    );
  }
}
