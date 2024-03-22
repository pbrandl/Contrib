import 'package:flutter_application_test/globals/global_widgets.dart';
import 'package:flutter_application_test/providers/responsive_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'destinations.dart';
import 'package:flutter/material.dart';

class NavRailDesktop extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final double width;

  const NavRailDesktop({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    ScreenType? screenType = ResponsiveProvider.of(context)?.screenType;

    Widget? headline() {
      if (screenType != null && screenType == ScreenType.desktop) {
        return Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: H3(AppLocalizations.of(context)!.nav),
          ),
        );
      }
      return null;
    }

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
              AppLogo(width: width, height: 140),
              Expanded(
                child: NavigationRail(
                  leading: headline(),
                  extended: true,
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
