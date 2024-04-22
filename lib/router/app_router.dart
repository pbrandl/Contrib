import 'package:flutter/material.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/providers/responsive_provider.dart';
import 'package:Contrib/screens/discover/category.dart';
import 'package:go_router/go_router.dart';

import 'package:Contrib/screens/map/map.dart';
import 'package:Contrib/screens/discover/serach.dart';
import 'package:Contrib/screens/profile/profile.dart';
import 'package:Contrib/screens/discover/discover.dart';
import 'package:Contrib/screens/dashboard/dashboard.dart';
import 'package:Contrib/screens/common/common.dart';

// ignore_for_file: prefer_const_constructors
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKeyMap = GlobalKey<NavigatorState>(
  debugLabel: 'Map',
);
final _shellNavigatorKeyCommons = GlobalKey<NavigatorState>(
  debugLabel: 'Commons',
);
final _shellNavigatorKeyDiscover = GlobalKey<NavigatorState>(
  debugLabel: 'Discover',
);
final _shellNavigatorKeySettings = GlobalKey<NavigatorState>(
  debugLabel: 'Settings',
);

final GoRouter _appRouter = GoRouter(
  debugLogDiagnostics: true,
  initialLocation: '/commons',
  navigatorKey: _rootNavigatorKey,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ResponsiveProvider.fromMediaQuery(context, navigationShell);
      },
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKeyCommons,
          routes: [
            GoRoute(
              path: '/commons',
              name: 'commons',
              pageBuilder: (context, state) => NoTransitionPage(
                child: Dashboard(),
              ),
              routes: [
                GoRoute(
                  path: 'detail/:id',
                  name: 'detail',
                  builder: (context, state) => Common(
                    commonId: state.pathParameters['id']!,
                    openDrawer: state.extra as bool?,
                  ),
                )
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKeyDiscover,
          routes: [
            GoRoute(
              path: '/discover',
              name: 'discover',
              pageBuilder: (context, state) => NoTransitionPage(
                child: DiscoverWidget(),
              ),
              routes: [
                GoRoute(
                  path: 'search',
                  name: 'search',
                  builder: (context, state) => SearchWidget(),
                ),
                GoRoute(
                  path: 'category/:category',
                  name: 'category',
                  builder: (context, state) => CategoryWidget(
                    category: state.pathParameters['category']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKeyMap,
          routes: [
            GoRoute(
              path: '/map',
              name: 'map',
              pageBuilder: (context, state) => NoTransitionPage(
                child: MapsWidget(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellNavigatorKeySettings,
          routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ProfileWidget(),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      EllipsisText("Error 404 | Page not found."),
      SpaceH(),
      TextButton(
        onPressed: () => GoRouter.of(context).goNamed('commons'),
        child: EllipsisText('Home', color: Colors.black),
      )
    ],
  ),
);

final GoRoute router = GoRoute(
  path: '/error',
  builder: (BuildContext context, GoRouterState state) => Text('a'),
);

GoRouter getAppRouter() {
  return _appRouter;
}
