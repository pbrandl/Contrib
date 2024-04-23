import 'package:flutter/material.dart';
import 'package:Contrib/globals/dialogs.dart';
import 'package:Contrib/globals/snackbar.dart';
import 'package:Contrib/globals/categories.dart';
import 'package:Contrib/globals/formatter.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/globals/custom_future_builder.dart';
import 'package:Contrib/providers/responsive_provider.dart';
import 'package:Contrib/screens/dashboard/edit_commons.dart';
import 'package:Contrib/globals/signup_login.dart';
import 'package:Contrib/providers/user_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late UserProvider userProvider;

  bool _isWidgetLocked = false; // Locked if a current request is ongoing.
  _lockWidget() => setState(() => _isWidgetLocked = true);
  _releaseWidget() => setState(() => _isWidgetLocked = false);

  List<ParseObject> userCommonAdmin = [];
  List<ParseObject> userContrib = [];
  List<ParseObject> userFavorites = [];

  late Future<bool> _initialization;

  late ResponsiveProvider responsiveProvider;
  late ScreenType _screenType;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    userProvider = UserProvider.of(context)!;
    userProvider.user.addListener(updateState);
    updateState();

    responsiveProvider = ResponsiveProvider.of(context)!;
    _screenType = responsiveProvider.screenType;
  }

  void updateState() {
    setState(() {
      if (userProvider.isLoggedIn()) {
        _initialization = initialize(userProvider.user.getParseUser()!);
      }
    });
  }

  @override
  void dispose() {
    userProvider.user.removeListener(updateState);
    super.dispose();
  }

  Future<bool> initialize(ParseUser user) async {
    _lockWidget();
    try {
      // Fetch user contributions and favorites
      List<ParseObject> fetchedCommonAdmin = await fetchUserCommonsAdmin(user);
      List<ParseObject> fetchedContribs = await fetchUserContribs(user);
      List<ParseObject> fetchedFavorites = await fetchFavorites(user);

      setState(() {
        userCommonAdmin = fetchedCommonAdmin;
        userContrib = fetchedContribs;
        userFavorites = fetchedFavorites;
      });

      _releaseWidget();
      return true;
    } catch (e) {
      _releaseWidget();
      return false;
    }
  }

  Future<List<ParseObject>> fetchUserCommonsAdmin(ParseUser user) async {
    final QueryBuilder<ParseObject> queryBuilder =
        QueryBuilder<ParseObject>(ParseObject('Commons'))
          ..whereEqualTo('admin', user.toPointer());

    final response = await queryBuilder.query();

    if (response.success) {
      if (response.results != null) {
        return response.results as List<ParseObject>;
      } else {
        return [];
      }
    } else {
      return Future.error(response.error!.message);
    }
  }

  Future<List<ParseObject>> fetchUserContribs(ParseUser user) async {
    final QueryBuilder<ParseObject> queryBuilder =
        QueryBuilder<ParseObject>(ParseObject('Contributions'))
          ..whereRelatedTo('contributions', '_User', user.objectId!)
          ..includeObject(['commonId', 'roundId']);

    final response = await queryBuilder.query();

    if (response.success) {
      if (response.results != null) {
        return response.results as List<ParseObject>;
      } else {
        return [];
      }
    } else {
      return Future.error(response.error!.message);
    }
  }

  Future<List<ParseObject>> fetchFavorites(ParseUser user) async {
    final QueryBuilder<ParseObject> queryBuilder =
        QueryBuilder<ParseObject>(ParseObject('Commons'))
          ..whereRelatedTo('favorites', '_User', user.objectId!);

    final response = await queryBuilder.query();

    if (response.success) {
      if (response.results != null) {
        return response.results as List<ParseObject>;
      } else {
        return [];
      }
    } else {
      return Future.error(response.error!.message);
    }
  }

  /// This function builds a widget given all contributions of the current user
  /// to a common and wraps it in a container.
  Widget commonContributions(ParseObject common, List<ParseObject> contribs) {
    // Common as header
    List<Widget> contribWidgets = [];
    contribWidgets.add(CommonNavListTile(
      titleName: common['name'],
      subtitleName: translateCategory(context, common['domain']),
      leadingLogoUrl: common['logo']?['url'],
      commonObjectId: common['objectId'],
      padding: true,
    ));
    contribWidgets.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: H3(AppLocalizations.of(context)!.contribution),
    ));

    // List contributions to each round
    for (ParseObject contrib in contribs) {
      Widget contribWidget = Padding(
        padding: const EdgeInsets.only(left: 16.0, right: 28),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            EllipsisText(DateFormat('dd.MM.yyyy').format(contrib['updatedAt'])),
            BoldText(currencyFormatter.format(contrib['sumContributions']))
          ],
        ),
      );
      contribWidgets.add(contribWidget);
    }
    contribWidgets.add(const SpaceHSmall());

    // Return the widget wrapped in a container
    return CustomContainer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: contribWidgets,
        ),
      ),
    );
  }

  Widget myContributionsWidget() {
    // Collect all contributions in a map by common.
    Map<String, List<ParseObject>> contribToCommon = {};
    for (ParseObject contrib in userContrib) {
      String commonId = contrib['commonId']['name'];

      if (!contribToCommon.containsKey(commonId)) {
        contribToCommon[commonId] = [];
      }
      contribToCommon[commonId]!.add(contrib);
    }

    if (userContrib.isNotEmpty) {
      // List all contributions by common, if any
      return Column(
        children: [
          for (var contribs in contribToCommon.values)
            Column(children: [
              commonContributions(contribs[0]['commonId'], contribs),
              const SpaceHSmall()
            ])
        ],
      );
    } else {
      // Show information if no contributions
      return CustomContainer(
        child: ResponsivePadding(
          child: Center(
            child: Column(
              children: [
                const SpaceH(),
                Text(AppLocalizations.of(context)!.no_contributions),
                Text(AppLocalizations.of(context)!.discover_start_contributing),
                const SpaceH(),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 60),
                  child: ElevatedButton(
                    onPressed: () {
                      context.goNamed('discover');
                    },
                    child: Text(AppLocalizations.of(context)!.title_search),
                  ),
                ),
                const SpaceH(),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future deleteCommon(ParseObject common) async {
    _lockWidget();
    final response = await common.delete();
    _releaseWidget();
    if (response.error != null) {
      var error = response.error!;
      return Future.error("${error.code} ${error.message}");
    }
  }

  deleteCommonHandler(ParseObject common) {
    showResponsiveDialog(context,
        screenType: _screenType,
        child: ConfirmDialog(
          confirmQuestion: AppLocalizations.of(context)!
              .delete_common_confirm(common['name']),
          onConfirm: () => deleteCommon(common).then((value) {
            initialize(userProvider.user.getParseUser()!);
            // Delete locally on success and update UI
            userCommonAdmin
                .removeWhere((item) => item.objectId == common.objectId);
            setState(() {});
            showSuccess(context, AppLocalizations.of(context)!.common_deleted);
          }).catchError((error) {
            showError(context,
                "${AppLocalizations.of(context)!.common_delete_error} Error: ${error.toString()}");
          }),
        ));
  }

  Widget userAdminWidget() {
    if (userCommonAdmin.isNotEmpty) {
      return CustomContainer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0.0),
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: userCommonAdmin.length,
            itemBuilder: (BuildContext context, int index) {
              ParseObject common = userCommonAdmin[index];
              return CommonNavListTile(
                titleName: common['name'],
                subtitleName: translateCategory(context, common['domain']),
                leadingLogoUrl: common['logo']?['url'],
                commonObjectId: common['objectId'],
                trailingWidget: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: AppLocalizations.of(context)!.edit,
                      child: CustomIconButton(
                        onPressed: _isWidgetLocked
                            ? null
                            : () => {
                                  showResponsiveDialog(
                                    context,
                                    heightFactor: 1,
                                    screenType: _screenType,
                                    child: EditCommonsDialog(
                                      // Edit a common
                                      common: common,
                                    ),
                                  ).then((value) {
                                    // if dialog is confirmed re-initialize
                                    if (value != null && value) {
                                      initialize(
                                          userProvider.user.getParseUser()!);
                                    }
                                  })
                                },
                        icon: Icons.edit_note,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: AppLocalizations.of(context)!.delete,
                      child: CustomIconButton(
                        onPressed: _isWidgetLocked
                            ? null
                            : () => deleteCommonHandler(common),
                        icon: Icons.delete,
                        iconSize: 20,
                      ),
                    ),
                    // const SizedBox(width: 4),
                    // CustomIconButton(
                    //   onPressed: () => GoRouter.of(context).pushNamed(
                    //     'detail',
                    //     pathParameters: <String, String>{
                    //       'id': common['objectId']
                    //     },
                    //   ),
                    //   icon: Icons.chevron_right,
                    // ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    } else {
      // Returns if user is no Admin of Commons
      return CustomContainer(
        child: ResponsivePadding(
          child: Center(
            child: Column(
              children: [
                const SpaceH(),
                Text(AppLocalizations.of(context)!.start_own_common),
                const SpaceH(),
                ElevatedButton(
                  onPressed: () {
                    openCreateCommonsDialog();
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 60),
                    child: Text(AppLocalizations.of(context)!.new_common_btn,
                        textAlign: TextAlign.center),
                  ),
                ),
                const SpaceH(),
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget userFavoritesWidget() {
    if (userFavorites.isNotEmpty) {
      return CustomContainer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0.0),
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: userFavorites.length,
            itemBuilder: (BuildContext context, int index) {
              ParseObject common = userFavorites[index];
              return CommonNavListTile(
                titleName: common['name'],
                subtitleName: translateCategory(context, common['domain']),
                leadingLogoUrl: common['logo']?['url'],
                commonObjectId: common['objectId'],
              );
            },
          ),
        ),
      );
    } else {
      return CustomContainer(
        child: ResponsivePadding(
          child: Center(
            child: Column(
              children: [
                const SpaceH(),
                Text(AppLocalizations.of(context)!.save_favorites),
                Text(AppLocalizations.of(context)!.discover_on_map),
                const SpaceH(),
                ElevatedButton(
                  onPressed: () {
                    context.goNamed('map');
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 60),
                    child: Text(AppLocalizations.of(context)!.nav_map,
                        textAlign: TextAlign.center),
                  ),
                ),
                const SpaceH(),
              ],
            ),
          ),
        ),
      );
    }
  }

  // Create a new Commons
  openCreateCommonsDialog() => showResponsiveDialog(
        context,
        heightFactor: 1,
        screenType: _screenType,
        child: const EditCommonsDialog(),
      ).then((value) {
        // if dialog is confirmed re-initialize
        if (value != null && value) {
          initialize(userProvider.user.getParseUser()!);
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldMessengerKey,
      body: userProvider.isLoggedIn()
          ? Center(
              child: CustomFutureBuilder(
                future: _initialization,
                onLoaded: (_) {
                  return SingleChildScrollView(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 550,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(left: 12.0),
                                          child: H2(
                                              AppLocalizations.of(context)!
                                                  .administraion),
                                        ),
                                      ),
                                      Tooltip(
                                        message: AppLocalizations.of(context)!
                                            .create_own_commons,
                                        preferBelow: false,
                                        child: TextButton.icon(
                                          onPressed: () {
                                            openCreateCommonsDialog();
                                          },
                                          icon: const Icon(Icons.add),
                                          label: Text(
                                            AppLocalizations.of(context)!
                                                .new_common_btn,
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                  const SpaceHSmall(),
                                  userAdminWidget(),
                                  const SpaceH(),
                                  const SpaceH(),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12.0),
                                    child: H2(AppLocalizations.of(context)!
                                        .my_contribution),
                                  ),
                                  const SpaceHSmall(),
                                  myContributionsWidget(),
                                  const SpaceHSmall(),
                                  const SpaceH(),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12.0),
                                    child: H2(AppLocalizations.of(context)!
                                        .subtitle_favorites),
                                  ),
                                  const SpaceHSmall(),
                                  userFavoritesWidget(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                onLoading: const Center(child: CircularProgressIndicator()),
                onError: (error) {
                  return Center(
                    child: Text(AppLocalizations.of(context)!
                        .arbitrary_error(error.toString())),
                  );
                },
              ),
            )
          : const SignUpLogInDialog(),
    );
  }
}
