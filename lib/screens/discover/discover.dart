import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_test/globals/categories.dart';
import 'package:flutter_application_test/globals/custom_future_builder.dart';
import 'package:flutter_application_test/globals/global_widgets.dart';
import 'package:flutter_application_test/globals/shimmer_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class DiscoverWidget extends StatefulWidget {
  const DiscoverWidget({Key? key}) : super(key: key);

  @override
  State<DiscoverWidget> createState() => _DiscoverWidgetState();
}

class _DiscoverWidgetState extends State<DiscoverWidget> {
  final maxNewCommons = 5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<List<ParseObject>> getNewCommons() async {
    final QueryBuilder<ParseObject> queryNewCommons =
        QueryBuilder<ParseObject>(ParseObject('Commons'));
    queryNewCommons.setLimit(maxNewCommons);
    queryNewCommons.orderByDescending('createdAt');
    queryNewCommons.keysToReturn(['name', 'logo', 'domain', 'objectId']);

    final ParseResponse apiResponse = await queryNewCommons.query();

    if (apiResponse.success && apiResponse.results != null) {
      return apiResponse.results as List<ParseObject>;
    } else {
      return [];
    }
  }

  Future<List<ParseObject>> getNewRounds() async {
    final QueryBuilder<ParseObject> queryNewCommons =
        QueryBuilder<ParseObject>(ParseObject('Rounds'))
          ..setLimit(maxNewCommons)
          ..orderByDescending('createdAt')
          ..includeObject(['commonId']);

    final ParseResponse apiResponse = await queryNewCommons.query();

    if (apiResponse.success && apiResponse.results != null) {
      return apiResponse.results as List<ParseObject>;
    } else {
      return [];
    }
  }

  Widget searchBar() => Hero(
        tag: 'search_bar',
        child: CupertinoSearchTextField(
          placeholder: AppLocalizations.of(context)!.title_search,
          onTap: () => context.goNamed('search'),
        ),
      );

  Widget categorySlider() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          height: 150,
          child: Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: List<Widget>.generate(categoryImages.length, (index) {
                String categoryTranslation =
                    getCategoryTranslations(context).values.toList()[index];

                // The key (in english) to access the right category
                String categoryKey = categoryImages.keys.toList()[index];
                return Center(
                  child: InkWell(
                    hoverColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    onTap: () => GoRouter.of(context).pushNamed(
                      'category',
                      pathParameters: <String, String>{'category': categoryKey},
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(left: 16),
                      width: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        image: DecorationImage(
                          image: AssetImage(categoryImages[categoryKey]!),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 32,
                              decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(20),
                                    bottomRight: Radius.circular(20),
                                  ),
                                  color: Colors.black.withOpacity(0.7)),
                              child: Center(
                                child: EllipsisText(
                                  categoryTranslation,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      );

  Widget discoverShimmerList = const Column(
    mainAxisAlignment: MainAxisAlignment.start,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(left: 12),
        child: ShimmerH1(),
      ),
      SpaceHSmall(),
      CustomContainer(
        child: Column(
          children: [
            ShimmerListTile(),
            ShimmerListTile(),
            ShimmerListTile(),
            ShimmerListTile(),
            ShimmerListTile()
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    Widget newCommonsList = SizedBox(
      width: 500,
      child: CustomFutureBuilder(
        future: getNewCommons(),
        onLoaded: ((List<ParseObject> commons) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: H2(AppLocalizations.of(context)!.newest_commons),
              ),
              const SpaceHSmall(),
              CustomContainer(
                child: Column(
                  children: [
                    if (commons.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(AppLocalizations.of(context)!
                              .num_commons_found(0)),
                        ),
                      ),
                    for (var common in commons)
                      CommonNavListTile(
                        titleName: common['name'],
                        subtitleName:
                            translateCategory(context, common['domain']),
                        leadingLogoUrl: common['logo']?['url'],
                        commonObjectId: common['objectId'],
                      )
                  ],
                ),
              ),
            ],
          );
        }),
        onError: (error) => Text(
            AppLocalizations.of(context)!.arbitrary_error(error.toString())),
        onLoading: discoverShimmerList,
      ),
    );

    Widget newRoundList = SizedBox(
      width: 500,
      child: CustomFutureBuilder(
        future: getNewRounds(),
        onLoaded: ((List<ParseObject> rounds) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: H2(AppLocalizations.of(context)!.newest_round),
              ),
              const SpaceHSmall(),
              CustomContainer(
                child: Column(
                  children: [
                    if (rounds.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(AppLocalizations.of(context)!
                              .num_commons_found(0)),
                        ),
                      ),
                    for (var round in rounds)
                      CommonNavListTile(
                        titleName: round['commonId']['name'],
                        subtitleName: DateFormat('dd.MM.yyyy')
                            .format(round['commonId']['createdAt']),
                        leadingLogoUrl: round['commonId']['logo']?['url'],
                        commonObjectId: round['commonId']['objectId'],
                      )
                  ],
                ),
              ),
            ],
          );
        }),
        onError: (error) => Text(
            AppLocalizations.of(context)!.arbitrary_error(error.toString())),
        onLoading: discoverShimmerList,
      ),
    );

    Widget padding(c) => Padding(padding: const EdgeInsets.all(16), child: c);

    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SpaceH(),
            padding(
              SizedBox(
                width: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    H1(AppLocalizations.of(context)!.title_search),
                    searchBar(),
                  ],
                ),
              ),
            ),
            const SpaceH(),
            categorySlider(),
            const SpaceH(),
            padding(newCommonsList),
            padding(newRoundList),
            const SpaceH(),
          ],
        ),
      ),
    );
  }
}
