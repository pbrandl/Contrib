import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_test/globals/categories.dart';
import 'package:flutter_application_test/globals/global_widgets.dart';
import 'package:flutter_application_test/globals/custom_future_builder.dart';
import 'package:flutter_application_test/globals/formatter.dart';
import 'package:flutter_application_test/globals/snackbar.dart';
import 'package:flutter_application_test/providers/responsive_provider.dart';
import 'package:flutter_application_test/screens/common/admin_section.dart';
import 'package:flutter_application_test/screens/common/common_shimmer.dart';
import 'package:flutter_application_test/screens/common/charts.dart';
import 'package:flutter_application_test/screens/common/user_contribution.dart';
import 'package:flutter_application_test/providers/user_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class Common extends StatefulWidget {
  final String commonId;
  final bool? openDrawer;

  const Common({
    super.key,
    required this.commonId,
    this.openDrawer = true,
  });

  @override
  State<Common> createState() => _CommonState();
}

class _CommonState extends State<Common> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int selectedChartIndex = 1; // Index to display the selection
  String selection = 'all'; // Select either 'current' or 'all' rounds

  ParseObject? _common;
  List<ParseObject> _rounds = [];
  bool _isFavoredByUser = false;
  ParseObject? _commonDetails; // Describtion and website

  late Future<bool> isInitialized;
  late UserProvider userProvider; // Current user logged in
  late ResponsiveProvider responsiveProvider;
  late ScreenType _screenType;
  late AppLocalizations l10n;

  ParseObject? get lastRound => _rounds.isEmpty ? null : _rounds.last;

  /// Live Query, that is used to update the contributions in real time.
  /// The subscription is used to subscribe and unsubscribe in dispose().
  final LiveQuery roundsLiveQuery = LiveQuery();
  Subscription? _totalContribSub;

  /// The web url to the commons
  String url =
      'https://commons-git-main-pbrandls-projects.vercel.app/#/commons/detail/';

  /// Initializes the widget by fetching the data for this common
  /// from the server and setting up live queries.
  @override
  void initState() {
    super.initState();
    isInitialized = initializeScreen(widget.commonId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openDrawer == true) {
        _scaffoldKey.currentState?.openEndDrawer();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    userProvider = UserProvider.of(context)!;
    userProvider.user.addListener(updateState);

    responsiveProvider = ResponsiveProvider.of(context)!;
    _screenType = responsiveProvider.screenType;

    l10n = AppLocalizations.of(context)!;
  }

  void updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    if (_totalContribSub != null) {
      roundsLiveQuery.client.unSubscribe(_totalContribSub!);
    }
    userProvider.user.removeListener(updateState);
    super.dispose();
  }

  /// Fetches the name and the logo of the common to display on the screen
  Future<ParseObject?> fetchCommon(String commonId) async {
    var queryBuilder = QueryBuilder<ParseObject>(ParseObject('Commons'))
      ..whereEqualTo('objectId', commonId)
      ..keysToReturn(['name', 'logo', 'domain', 'admin']);

    final ParseResponse parseResponse = await queryBuilder.query();

    if (parseResponse.success && parseResponse.result != null) {
      return parseResponse.result[0];
    }

    return null;
  }

  // Fetch all necessary data to display on the screen
  Future<bool> initializeScreen(String commonId) async {
    ParseObject? common = await fetchCommon(commonId);

    if (common == null) {
      return Future.error("Common not found");
    }

    List<ParseObject> rounds = await fetchRounds(commonId);
    bool isFavored = await fetchIsFavored(commonId);
    ParseObject? details = await fetchCommonDetails(widget.commonId);

    if (mounted) {
      setState(() {
        _common = common;
        _rounds = rounds;
        _isFavoredByUser = isFavored;
        _commonDetails = details;
      });
    }

    initLiveQueryRound(common);

    return true;
  }

  // Asks whether the current user is the admin of this common
  isAdmin({required ParseUser? admin}) {
    ParseUser? user = userProvider.user.getParseUser();

    if (user == null || admin == null) {
      return false;
    }

    return user.objectId == admin.objectId;
  }

  // Asks whether the current user is the admin of this common
  Future<bool> fetchIsFavored(String commonId) async {
    ParseUser? user = userProvider.user.getParseUser();

    if (user == null) {
      return false;
    }

    // Query 'favorites' relation
    final ParseRelation relation = user.getRelation('favorites');

    QueryBuilder relationQuery = relation.getQuery()
      ..whereEqualTo('objectId', commonId);

    var response = await relationQuery.query();

    if (response.success && response.results != null) {
      return true;
    } else {
      return false;
    }
  }

  /// Initialize LiveQuery to keep track of the rounds.
  void initLiveQueryRound(ParseObject common) async {
    QueryBuilder<ParseObject> totalContrib =
        QueryBuilder<ParseObject>(ParseObject('Rounds'))
          ..whereEqualTo('commonId', common.toPointer())
          ..keysToReturn(['target', 'contribution', 'isActive']);

    _totalContribSub = await roundsLiveQuery.client.subscribe(totalContrib);

    // Get the new total contribution in case of an update event.
    _totalContribSub!.on(LiveQueryEvent.update, (ParseObject round) {
      setState(() {
        _rounds.last = round;
      });
    });

    // Initialize a new round on create event.
    _totalContribSub!.on(LiveQueryEvent.create, (ParseObject round) {
      setState(() {
        _rounds.add(round);
      });

      showSuccess(context, l10n.round_started);
    });

    _totalContribSub!.on(LiveQueryEvent.delete, (ParseObject deleted) {
      setState(() {
        _rounds.removeWhere((round) => deleted.objectId == round.objectId);
      });
      showSuccess(context, l10n.round_reset);
    });
  }

  Future<ParseObject?> fetchCommonDetails(String commonId) async {
    final QueryBuilder<ParseObject> query =
        QueryBuilder<ParseObject>(ParseObject('CommonDetails'))
          ..whereEqualTo('commonId', {
            '__type': 'Pointer',
            'className': 'Commons',
            'objectId': commonId,
          })
          ..keysToReturn(['websiteUrl', 'description']);

    final ParseResponse apiResponse = await query.query();

    if (apiResponse.success && apiResponse.results != null) {
      return apiResponse.results!.first as ParseObject;
    } else {
      return null;
    }
  }

  /// Fetch the rounds in an ascending order, i.e. newest is last.
  /// Also set the displayed target and contribution accordingly.
  Future<List<ParseObject>> fetchRounds(String commonId) async {
    final common = ParseObject('Commons')..objectId = widget.commonId;

    final QueryBuilder<ParseObject> queryRounds =
        QueryBuilder<ParseObject>(ParseObject('Rounds'))
          ..whereEqualTo('commonId', common.toPointer())
          ..orderByAscending('createdAt')
          ..keysToReturn(['contribution', 'target', 'objectId', 'isActive']);

    final ParseResponse apiResponse = await queryRounds.query();

    if (apiResponse.success && apiResponse.results != null) {
      if (mounted) {
        setState(() {
          _rounds = apiResponse.results as List<ParseObject>;
        });
      }
      return apiResponse.results as List<ParseObject>;
    } else {
      return [];
    }
  }

  // Add this common to user's favorites
  Future<void> addFavorite() async {
    ParseUser? user = userProvider.user.getParseUser();

    if (_common == null) return Future.error("Null error.");

    user!.addRelation('favorites', [_common!]);
    ParseResponse response = await userProvider.user.saveAndNotify();

    if (response.success) {
      if (mounted) setState(() => _isFavoredByUser = true);
      return;
    } else if (response.error == null) {
      return Future.error(response.results![0]);
    } else {
      return Future.error(response.error!);
    }
  }

  // Delete this common from user's favorites
  Future<void> deleteFavorite() async {
    ParseUser? user = userProvider.user.getParseUser();

    if (_common == null) return Future.error("Null error.");

    user!.removeRelation('favorites', [_common!]);
    ParseResponse response = await userProvider.user.saveAndNotify();

    if (response.success) {
      setState(() => _isFavoredByUser = false);
      return;
    } else if (response.error == null) {
      return Future.error(response.results![0]);
    } else {
      return Future.error(response.error!);
    }
  }

  Widget favoriteButton() {
    return CustomIconButton(
      onPressed: () {
        if (!_isFavoredByUser) {
          addFavorite().then((value) {
            showSuccess(
              context,
              l10n.add_to_favorites,
            );
          }).catchError((e) {
            showError(context, l10n.adding_to_favorites_failed);
          });
        } else {
          deleteFavorite().then((value) {
            showSuccess(
              context,
              l10n.remove_from_favorites,
            );
          }).catchError((e) {
            showError(context, l10n.removing_from_favorites_failed);
          });
        }
      },
      tooltipMessage: !_isFavoredByUser ? l10n.follow : l10n.unfollow,
      icon: !_isFavoredByUser ? Icons.favorite_outline : Icons.favorite,
      iconSize: 20,
    );
  }

  Widget adminButton() {
    return CustomIconButton(
      onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
      tooltipMessage: l10n.administraion,
      icon: Icons.menu,
    );
  }

  // Button which shows a QR code linking to this common
  Widget qrCodeButton() => CustomIconButton(
        icon: Icons.qr_code,
        tooltipMessage: l10n.show_qr_code,
        onPressed: () {
          showDialog(
            context: context,
            barrierColor: Colors.black87,
            builder: (BuildContext context) {
              return Dialog(
                child: SizedBox(
                  width: 350,
                  height: 350,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: QrImageView(
                        padding: EdgeInsets.zero,
                        foregroundColor:
                            Theme.of(context).colorScheme.onBackground,
                        data: '$url${widget.commonId}',
                        version: QrVersions.auto,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

  // Button that copies link to clipboard
  Widget copyLinkButton() => CustomIconButton(
        tooltipMessage: l10n.copy_link,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: '$url${widget.commonId}'));
          showSuccess(context, l10n.link_copied);
        },
        icon: Icons.share,
        iconSize: 20,
      );

  Future<void> _launchUrl(String url) async {
    if (!url.startsWith('https://')) {
      url = 'https://$url';
    }

    bool response = await launchUrl(Uri.parse(url));
    if (response) {
      return Future.error('${l10n.could_not_load_website}: $url.');
    }
  }

  Widget goToWebsiteButton() => CustomIconButton(
        onPressed: () => _launchUrl(_commonDetails?['websiteUrl'])
            .catchError((e) => showError(context, e.toString())),
        icon: Icons.language,
        tooltipMessage: _commonDetails != null
            ? l10n.go_to_website
            : l10n.could_not_load_website,
      );

  double computePercentage() {
    if (_rounds.isEmpty) return 0;
    if (_rounds.last['contribution'] == 0) return 0;
    if (_rounds.last['target'] == 0) return 0;
    return (_rounds.last['contribution'] / _rounds.last['target']) * 100;
  }

  Widget header() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row shows logo, name and contribution
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _common!['logo'] == null
                              ? CommonAvatar(commonName: _common!['name'][0])
                              : CommonLogo(url: _common!['logo']?['url']),
                          const ResponsiveVSpace(),
                          copyLinkButton(),
                          const ResponsiveVSpace(),
                          qrCodeButton(),
                          const ResponsiveVSpace(),
                          if (_commonDetails != null &&
                              _commonDetails!['websiteUrl'] != "")
                            goToWebsiteButton(),
                        ],
                      ),
                    ),
                    H1(currencyFormatter.format(lastRound?['target'] ?? 0)),
                  ],
                ),
                // Row shows link, qr button and target
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: H1(_common!['name'])),
                    H1(_rounds.isEmpty
                        ? "0.0 %"
                        : '${computePercentage().toStringAsFixed(1)}%'),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

  Widget chartSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButtonAccent(
              onPressed: _rounds.isEmpty
                  ? null
                  : () => setState(() {
                        selectedChartIndex = (selectedChartIndex + 1) % 2;
                      }),
              text: selectedChartIndex == 0 ? l10n.show_current : l10n.show_all,
            ),
          ),
          const SpaceH(),
          // If there is no round started show empty shart
          if (_rounds.isEmpty)
            Stack(
              children: [
                const SizedBox(height: 200, child: CircleChart(percentage: 0)),
                Positioned.fill(
                  child: Center(
                    child: Card(
                      color: Theme.of(context).colorScheme.inversePrimary,
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: BoldText(
                          color: Theme.of(context).colorScheme.inverseSurface,
                          l10n.round_not_started,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (_rounds.isNotEmpty)
            // If there is at least one round show chart
            Column(
              children: [
                Stack(
                  children: [
                    Stack(alignment: Alignment.topRight, children: [
                      selectedChartIndex == 0
                          ? Chart(rounds: _rounds)
                          : SizedBox(
                              height: 200,
                              child: CircleChart(
                                  percentage: computePercentage(),
                                  centerWidget: H2(currencyFormatter
                                      .format(_rounds.last['contribution']))),
                            ),
                    ]),
                    if (!_rounds.last['isActive'])
                      Positioned.fill(
                        child: Center(
                          child: Card(
                            elevation: 10,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: SizedBox(
                                width: 270,
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.warning_amber_outlined),
                                      const SizedBox(width: 10),
                                      Text(l10n.round_is_inactive)
                                    ]),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          const SpaceH(),
        ],
      );

  SingleChildScrollView showContent() {
    return SingleChildScrollView(
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 550, minWidth: 200),
                child: ResponsivePadding(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomFutureBuilder(
                        future: isInitialized,
                        onLoaded: (data) {
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              header(),
                              const SpaceH(),
                              const SpaceH(),
                              const SpaceH(),
                              chartSection(),
                              if (_screenType != ScreenType.desktop)
                                Column(
                                  children: [
                                    const SpaceH(),
                                    const SpaceH(),
                                    const SpaceH(),
                                    UserContributionWidget(
                                      common: _common!,
                                      round: lastRound,
                                    ),
                                  ],
                                ),
                              const SpaceH(),
                              const SpaceH(),
                              const SpaceH(),
                              const SpaceH(),
                              Describtion(
                                description: _commonDetails?['description'] ??
                                    l10n.failed_loading_description,
                                category: _common?['domain'],
                              ),
                            ],
                          );
                        },
                        onError: (e) {
                          return Text(
                            AppLocalizations.of(context)!.common_not_found,
                          );
                        },
                        onLoading: const ShimmerCommon(),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          flex: 8,
          child: Scaffold(
            key: _scaffoldKey,
            drawerScrimColor: Colors.black.withOpacity(0.25),
            endDrawer: _screenType == ScreenType.desktop
                ? null
                : Drawer(
                    width: 400,
                    child: ResponsivePadding(
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: CloseButton(
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          if (isAdmin(admin: _common?['admin']))
                            AdminSection(
                              widget.commonId,
                              userProvider.user.getParseUser()!,
                              lastRound,
                            ),
                        ],
                      ),
                    ),
                  ),
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              actions: [
                if (userProvider.isLoggedIn()) favoriteButton(),
                const SizedBox(width: 8),
                if (_screenType != ScreenType.desktop &&
                    userProvider.isLoggedIn() &&
                    isAdmin(admin: _common?['admin']))
                  Row(children: [adminButton(), const SizedBox(width: 8)]),
              ],
              leading: IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => GoRouter.of(context).pop(),
                  style: ButtonStyle(backgroundColor:
                      MaterialStateProperty.resolveWith<Color>(
                          (Set<MaterialState> states) {
                    return Colors.grey.withOpacity(0.15);
                  }))),
            ),
            body: Center(
              child: showContent(),
            ),
          ),
        ),
        if (_screenType == ScreenType.desktop)
          const VerticalDivider(thickness: 1, width: 1),
        if (_screenType == ScreenType.desktop)
          Flexible(
            flex: 4,
            child: Container(
              color: Theme.of(context).cardColor,
              height: double.infinity,
              child: Center(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: CustomFutureBuilder(
                      future: isInitialized,
                      onLoaded: (data) {
                        return Center(
                          child: SizedBox(
                            width: 400,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SpaceH(),
                                const SpaceH(),
                                if (userProvider.isLoggedIn())
                                  UserContributionWidget(
                                    round: lastRound,
                                    common: _common!,
                                  ),
                                if (isAdmin(admin: _common?['admin']))
                                  Column(
                                    children: [
                                      const SpaceH(),
                                      const SpaceH(),
                                      const Divider(),
                                      const SpaceH(),
                                      const SpaceH(),
                                      AdminSection(
                                        widget.commonId,
                                        userProvider.user.getParseUser()!,
                                        lastRound,
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                      onError: (p0) => H2("Loading data failed ..."),
                    ),
                  ),
                ),
              ),
            ),
          )
      ],
    );
  }
}

class Describtion extends StatefulWidget {
  final String description;
  final String? category;

  const Describtion({
    super.key,
    required this.description,
    required this.category,
  });

  @override
  State<Describtion> createState() => _DescribtionState();
}

class _DescribtionState extends State<Describtion> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            H2(AppLocalizations.of(context)!.subtitle_description),
            const SizedBox(width: 16),
            SizedBox(
              height: 26,
              child: ElevatedButton(
                onPressed: null,
                style: ButtonStyle(
                  backgroundColor:
                      MaterialStateProperty.all(Colors.grey.withOpacity(0.55)),
                ),
                child: SmallText(
                  translateCategory(context, widget.category),
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
        const SpaceHSmall(),
        GestureDetector(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded; // Toggle expanded state
            });
          },
          child: Text(
            widget.description,
            softWrap: true,
            // TODO: Prototype does not support read more/read less
            maxLines: _isExpanded
                ? 1000 // a fix, to be sure the whole text is displayed
                : 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SpaceHSmall(),
        // if (!_isExpanded) // Conditionally display 'Read more' text
        //   TextButtonAccent(
        //     onPressed: () {
        //       setState(() {
        //         _isExpanded = true;
        //       });
        //     },
        //     text: 'Read less',
        //   ),
        // if (_isExpanded) // Conditionally display 'Read more' text
        //   TextButtonAccent(
        //     onPressed: () {
        //       setState(() {
        //         _isExpanded = false;
        //       });
        //     },
        //     text: 'Read more',
        //   ),
      ],
    );
  }
}
