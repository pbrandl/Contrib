import 'package:flutter/material.dart';
import 'package:Contrib/globals/categories.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';

class CategoryWidget extends StatefulWidget {
  final String category;

  const CategoryWidget({
    super.key,
    required this.category,
  });

  @override
  State<CategoryWidget> createState() => _CategoryWidgetState();
}

class _CategoryWidgetState extends State<CategoryWidget> {
  bool _isLoading = false;
  _lockWidget() => setState(() => _isLoading = true);
  _releaseWidget() => setState(() => _isLoading = false);

  List<ParseObject> _commons = [];
  late AppLocalizations l10n;

  @override
  void initState() {
    super.initState();
    requestCommonsWithCategory(widget.category);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    l10n = AppLocalizations.of(context)!;
  }

  Widget resultList(commons) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: commons.length,
      itemBuilder: (context, index) {
        final common = commons[index];
        return CommonNavListTile(
          titleName: common['name'],
          subtitleName: translateCategory(context, common['domain']),
          commonObjectId: common['objectId'],
          leadingLogoUrl: common['logo']?['url'],
          trailingWidget: const Icon(Icons.chevron_right),
        );
      },
    );
  }

  Future requestCommonsWithCategory(String category) async {
    _lockWidget();
    final QueryBuilder<ParseObject> query =
        QueryBuilder<ParseObject>(ParseObject('Commons'))
          ..whereStartsWith('domain', category);

    final ParseResponse apiResponse = await query.query();

    if (apiResponse.success && apiResponse.results != null) {
      if (mounted) {
        setState(() {
          _commons = apiResponse.results as List<ParseObject>;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _commons = [];
        });
      }
    }
    _releaseWidget();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: H2(translateCategory(context, widget.category)),
                ),
                const SpaceHSmall(),
                CustomContainer(
                  child: _isLoading
                      ? Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Center(child: H3(l10n.searching)),
                        )
                      : _commons.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Center(
                                  child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  H3(l10n.no_results_for),
                                  H3("'${translateCategory(context, widget.category)}'"),
                                ],
                              )),
                            )
                          : resultList(_commons),
                ),
                const SpaceH(),
                Center(
                  child: SmallText(
                    AppLocalizations.of(context)!
                        .num_commons_found(_commons.length),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
