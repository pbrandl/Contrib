import 'package:flutter/material.dart';
import 'package:flutter_application_test/navigation/desktop.dart';
import 'package:flutter_application_test/navigation/mobile.dart';
import 'package:flutter_application_test/navigation/tablet.dart';
import 'package:go_router/go_router.dart';

enum ScreenType { mobile, tablet, desktop }

class ResponsiveProvider extends InheritedWidget {
  final ScreenType screenType;
  final StatefulNavigationShell navigationShell;

  const ResponsiveProvider({
    super.key,
    required this.navigationShell,
    required this.screenType,
    required super.child,
  });

  static ResponsiveProvider? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResponsiveProvider>();

  @override
  bool updateShouldNotify(covariant ResponsiveProvider oldWidget) {
    return screenType != oldWidget.screenType;
  }

  factory ResponsiveProvider.fromMediaQuery(
      BuildContext context, StatefulNavigationShell shell) {
    var screenSize = MediaQuery.of(context).size.width;

    void goBranch(int index) {
      shell.goBranch(
        index,
        // navigating to the initial location when tapping the item that is already active.
        initialLocation: index == shell.currentIndex,
      );
    }

    if (screenSize < 500) {
      return ResponsiveProvider(
          screenType: ScreenType.mobile,
          navigationShell: shell,
          child: MobileScaffold(
            bodyWidget: shell,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: goBranch,
          ));
    } else if (screenSize < 1050) {
      return ResponsiveProvider(
          screenType: ScreenType.tablet,
          navigationShell: shell,
          child: TabletScaffold(
            bodyWidget: shell,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: goBranch,
          ));
    } else {
      return ResponsiveProvider(
          screenType: ScreenType.desktop,
          navigationShell: shell,
          child: DesktopScaffold(
            bodyWidget: shell,
            selectedIndex: shell.currentIndex,
            onDestinationSelected: goBranch,
          ));
    }
  }
}
