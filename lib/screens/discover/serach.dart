import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';

class SearchWidget extends StatefulWidget {
  const SearchWidget({super.key});

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  final TextEditingController _controller = TextEditingController();
  List<ParseObject> _commons = [];
  bool _isLoading = false;
  _lockWidget() => setState(() => _isLoading = true);
  _releaseWidget() => setState(() => _isLoading = false);

  late AppLocalizations l10n;

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
          subtitleName: common['domain'],
          commonObjectId: common['objectId'],
          leadingLogoUrl: common['logo']?['url'],
          trailingWidget: const Icon(Icons.chevron_right),
        );
      },
    );
  }

  Future requestCommonsStartingWith(String searchInput) async {
    if (searchInput.isEmpty) {
      setState(() {
        _commons = [];
      });
      return;
    }
    _lockWidget();

    if (searchInput.isEmpty) return;
    final QueryBuilder<ParseObject> query =
        QueryBuilder<ParseObject>(ParseObject('Commons'))
          ..whereStartsWith('name', searchInput);

    final ParseResponse apiResponse = await query.query();

    if (apiResponse.success && apiResponse.results != null) {
      setState(() {
        _commons = apiResponse.results as List<ParseObject>;
      });
    } else {
      setState(() {
        _commons = [];
      });
    }
    _releaseWidget();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 600,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SpaceH(),
              Row(
                children: [
                  Expanded(
                    child: Hero(
                      tag: 'search_bar',
                      child: CupertinoSearchTextField(
                        autofocus: true,
                        autocorrect: false,
                        controller: _controller,
                        onChanged: requestCommonsStartingWith,
                        onSuffixTap: () => _controller.text = "",
                        placeholder: l10n.title_search,
                        prefixIcon: _isLoading
                            ? const Padding(
                                padding: EdgeInsets.only(
                                    top: 4.0, right: 3.0, left: 3.0),
                                child: Center(
                                  child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      )),
                                ),
                              )
                            : const Icon(CupertinoIcons.search),
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onBackground, // Set text color
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  TextButton(
                    child: Text(AppLocalizations.of(context)!.btn_cancel),
                    onPressed: () => context.pop('/search'),
                  ),
                ],
              ),
              if (_isLoading)
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SpaceH(),
                      const SpaceH(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.search, size: 22),
                          const SizedBox(width: 8),
                          H2(l10n.searching),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_commons.isNotEmpty &&
                  !_isLoading &&
                  _controller.text.isNotEmpty)
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SpaceH(),
                      const SpaceH(),
                      H2(l10n.search_results),
                      const SpaceHSmall(),
                      CustomContainer(child: resultList(_commons)),
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
              if (_controller.text.isEmpty && !_isLoading)
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SpaceH(),
                      const SpaceH(),
                      H2(l10n.what_are_you_searching_for),
                    ],
                  ),
                ),
              if (_controller.text.isNotEmpty &&
                  _commons.isEmpty &&
                  !_isLoading)
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SpaceH(),
                      const SpaceH(),
                      H3(l10n.no_results_for),
                      H2("'${_controller.text}'")
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
