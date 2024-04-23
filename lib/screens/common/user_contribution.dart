import 'package:Contrib/screens/common/not_logged_in_widget.dart';
import 'package:flutter/material.dart';
import 'package:Contrib/globals/formatter.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/globals/keypad.dart';
import 'package:Contrib/globals/snackbar.dart';
import 'package:Contrib/providers/responsive_provider.dart';
import 'package:Contrib/providers/user_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class UserContributionWidget extends StatefulWidget {
  final bool showInfo;
  final ParseObject common;
  final ParseObject? round;

  const UserContributionWidget({
    super.key,
    required this.round,
    required this.common,
    this.showInfo = true,
  });

  @override
  State<UserContributionWidget> createState() => _UserContributionWidgetState();
}

class _UserContributionWidgetState extends State<UserContributionWidget> {
  bool _isWidgetLocked = false;
  bool _isContribLoading = false;
  bool _isRecallLoading = false;

  _lockWidget() => setState(() => _isWidgetLocked = true);
  _releaseWidget() => setState(() => _isWidgetLocked = false);
  _lockContrib() => setState(() => _isContribLoading = true);
  _releaseContrib() => setState(() => _isContribLoading = false);
  _lockRecall() => setState(() => _isRecallLoading = true);
  _releaseRecall() => setState(() => _isRecallLoading = false);

  double getSumContrib(ParseObject? contrib) =>
      _userContrib?['sumContribution'] ?? 0;

  late ResponsiveProvider _responsiveProvider;
  late ScreenType _screenType;
  late UserProvider _userProvider;
  ParseObject? _round;
  ParseObject? _userContrib;

  @override
  void initState() {
    super.initState();
    _round = widget.round;
  }

  Future initializeContribution() async {
    ParseObject? newUserContrib =
        await _fetchUserContribution(_round!).catchError(
      (e) {
        showError(
          context,
          AppLocalizations.of(context)!.arbitrary_error(e.toString()),
        );
        return null;
      },
    );

    if (mounted) {
      setState(() {
        _userContrib = newUserContrib;
      });
    }
  }

  @override
  void didUpdateWidget(UserContributionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.round?.objectId != widget.round?.objectId) {
      _round = widget.round;
      if (_round != null) initializeContribution();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _userProvider = UserProvider.of(context)!;
    _userProvider.user.addListener(updateState);

    _responsiveProvider = ResponsiveProvider.of(context)!;
    _screenType = _responsiveProvider.screenType;

    if (widget.round != null) initializeContribution();
  }

  void updateState() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _userProvider.user.removeListener(updateState);
    super.dispose();
  }

  /// This function adds a new contribution to either an existing contribution
  /// for a particular round or creates a new contribution to this round.
  /// As well it adds new contributions to the user's relations. Common admin
  /// gets read access to the users contribution.
  Future<ParseObject?> _addContribution(
    ParseObject common,
    ParseObject round,
    double newContrib,
  ) async {
    ParseUser? user = _userProvider.user.getParseUser();
    if (user == null) {
      return Future.error(NoUserException());
    }

    ParseACL acl = ParseACL(owner: user)
      ..setReadAccess(userId: widget.common['admin'].objectId, allowed: true);

    ParseObject newContribObj;
    if (_userContrib == null) {
      newContribObj = ParseObject('Contributions')
        ..set('roundId', round.toPointer())
        ..set('commonId', widget.common.toPointer())
        ..set('contributions', [newContrib])
        ..set('sumContributions', newContrib)
        ..set('userId', user.toPointer())
        ..setACL(acl);

      ParseRelation userContribs = user.getRelation('contributions');
      userContribs.add(newContribObj); // Add to user relation
      user.setACL(acl); // Allow read address for Common admin
      await _userProvider.user.saveAndNotify();
    } else {
      final allContribs = _userContrib!['contributions'];
      final sumContribs = _userContrib!['sumContributions'];

      allContribs.add(newContrib);
      newContribObj = ParseObject('Contributions')
        ..set('contributions', allContribs)
        ..set('sumContributions', sumContribs + newContrib)
        ..set('objectId', _userContrib!.objectId);
    }

    final response = await newContribObj.save();

    if (!response.success) {
      return Future.error(response.error!.message);
    }

    setState(() {
      _userContrib = newContribObj;
    });
    return newContribObj;
  }

  // Recall contribution. It deletes the contribution of the current round.
  Future _recallContribution(ParseObject round) async {
    ParseUser? user = _userProvider.user.getParseUser();

    if (user == null) {
      return Future.error(NoUserException());
    }

    if (_userContrib == null) return; // Nothing to do

    // Delete contirb, relation to the contrib and restrict Common admin access.
    ParseACL acl = ParseACL(owner: user)
      ..setReadAccess(userId: widget.common['admin'].objectId, allowed: false);
    ParseRelation contribs = user.getRelation('contributions');
    user.setACL(acl);
    _userProvider.user.saveAndNotify();

    contribs.remove(_userContrib!);
    final response = await _userContrib!.delete();

    if (!response.success) {
      return Future.error(response.error!.message);
    }

    setState(() {
      _userContrib = null;
    });
  }

  /// Fetches the contribution of the user initially.
  Future<ParseObject?> _fetchUserContribution(ParseObject? round) async {
    if (round == null) return null;

    ParseUser? user = _userProvider.user.getParseUser();

    if (user == null) {
      return null;
    }

    final QueryBuilder<ParseObject> query =
        QueryBuilder<ParseObject>(ParseObject('Contributions'))
          ..whereEqualTo('roundId', round.toPointer())
          ..whereEqualTo('userId', user)
          ..keysToReturn(['sumContributions', 'contributions']);

    final ParseResponse response = await query.query();

    if (response.success && response.results != null) {
      return response.result.first as ParseObject;
    } else {
      return null;
    }
  }

  /// Recalls the all contributions of the user for this round.
  Widget recallButton() => FilledButton.tonal(
        onPressed: widget.round == null ||
                !widget.round!['isActive'] ||
                _isRecallLoading ||
                _isWidgetLocked
            ? null
            : () => _recallContributionHandler(widget.round!),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _isRecallLoading
                ? Container(
                    width: 24,
                    height: 18,
                    padding: const EdgeInsets.only(left: 6),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                    ))
                : Text(
                    AppLocalizations.of(context)!.btn_recall,
                  ),
          ],
        ),
      );

  Widget recallTextButton() => TextButton(
        onPressed: widget.round == null ||
                !widget.round!['isActive'] ||
                _isRecallLoading ||
                _isWidgetLocked
            ? null
            : () => _recallContributionHandler(widget.round!),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(AppLocalizations.of(context)!.btn_recall),
            const SizedBox(width: 5),
            _isRecallLoading
                ? Container(
                    width: 24,
                    height: 18,
                    padding: const EdgeInsets.only(left: 6),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                    ))
                : const Icon(
                    Icons.refresh,
                  ),
          ],
        ),
      );

  Widget contributionButtonMobile() {
    return FilledButton(
      onPressed: widget.round == null ||
              !widget.round!['isActive'] ||
              _isContribLoading ||
              _isWidgetLocked
          ? null
          : () {
              showBottomSheet(
                context: context,
                builder: (BuildContext context) {
                  KeyPadController padController = KeyPadController();
                  return FractionallySizedBox(
                    heightFactor: 1,
                    child: Center(
                      child: SingleChildScrollView(
                        child: SizedBox(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              const SizedBox(
                                  width: 700), // Width of the bottom sheet
                              const SpaceH(),
                              const SpaceH(),
                              const SpaceH(),
                              H2(AppLocalizations.of(context)!
                                  .add_contribution),
                              const SpaceH(),
                              SizedBox(
                                width: 270,
                                child: KeyPad(padController),
                              ),
                              const SpaceH(),
                              const SpaceH(),
                              SizedBox(
                                width: 270,
                                child: FilledButton(
                                  onPressed: () {
                                    double newContribution = double.parse(
                                        padController.numberString);
                                    if (newContribution > 0) {
                                      addContributionHandler(widget.common,
                                          widget.round!, newContribution);
                                    }
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    AppLocalizations.of(context)!.btn_confirm,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
      child: _isContribLoading
          ? Container(
              width: 24,
              height: 18,
              padding: const EdgeInsets.only(left: 6),
              child: const CircularProgressIndicator(
                strokeWidth: 2,
              ))
          : Text(
              AppLocalizations.of(context)!.btn_contribute,
            ),
    );
  }

  Widget info() {
    return IconButton(
      onPressed: () => showAdaptiveDialog(
          context: context,
          builder: (context) {
            return Dialog(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            H2("Info"),
                            const CloseButton(),
                          ],
                        ),
                        const SpaceH(),
                        Text(AppLocalizations.of(context)!.contribute_info),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      icon: const Icon(
        Icons.info_outline,
        semanticLabel: "acb",
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget userContributionMobile() {
      if (_userProvider.isLoggedIn()) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    H2(AppLocalizations.of(context)!.my_contribution),
                    const SizedBox(width: 16),
                    H2(currencyFormatter
                        .format(_userContrib?['sumContributions'] ?? 0)),
                  ],
                ),
                info()
              ],
            ),
            const SpaceH(),
            const SpaceH(),
            Row(children: [
              Expanded(child: contributionButtonMobile()),
              const SizedBox(width: 16),
              Expanded(child: recallButton()),
            ]),
          ],
        );
      } else {
        return const NotLoggedInWidget();
      }
    }

    // Mobile version
    if (_screenType != ScreenType.desktop) {
      return CustomContainer(
        child: ResponsivePadding(
          child: userContributionMobile(),
        ),
      );
    } else {
      // Desktop version
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              H3(AppLocalizations.of(context)!.my_contribution),
              const SizedBox(width: 2),
              info()
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              H3(currencyFormatter
                  .format(_userContrib?['sumContributions'] ?? 0)),
              recallTextButton(),
            ],
          ),
          const SpaceH(),
          NumberTextFieldButton(
            buttonLabel: AppLocalizations.of(context)!.btn_confirm,
            textLabel: AppLocalizations.of(context)!.contribution,
            buttonSuffixWidget: _isContribLoading
                ? Container(
                    width: 20,
                    height: 18,
                    padding: const EdgeInsets.only(left: 2),
                    child: const CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send, size: 20),
            textPrefixIcon: const Icon(
              Icons.euro,
              size: 20,
            ),
            onClick:
                widget.round == null || _isContribLoading || _isWidgetLocked
                    ? null
                    : (double contrib) {
                        if (contrib > 0) {
                          addContributionHandler(
                              widget.common, widget.round!, contrib);
                        }
                      },
          ),
        ],
      );
    }
  }

  void addContributionHandler(
    ParseObject common,
    ParseObject round,
    double newContribution,
  ) {
    _lockWidget();
    _lockContrib();
    // Reject if current round is active (same check shoud disable contribution button)
    if (!round['isActive']) {
      _releaseContrib();
      _releaseWidget();
      showError(context, AppLocalizations.of(context)!.round_is_inactive);
    } else {
      _addContribution(common, round, newContribution).then((_) {
        _releaseContrib();
        _releaseWidget();
      }).catchError((e) {
        _releaseContrib();
        _releaseWidget();
        showError(
          context,
          AppLocalizations.of(context)!.arbitrary_error(e.toString()),
        );
      });
    }
  }

  void _recallContributionHandler(
    ParseObject round,
  ) {
    _lockWidget();
    _lockRecall();
    // Reject if current round is active (same check shoud disable contribution button)
    if (!round['isActive']) {
      showError(context, AppLocalizations.of(context)!.round_is_inactive);
    }

    // Show error
    _recallContribution(round).then((_) {
      _releaseRecall();
      _releaseWidget();
    }).catchError((error) {
      _releaseRecall();
      _releaseWidget();
      showError(
        context,
        "${AppLocalizations.of(context)!.contribution_recall_error} Error: ${error.toString()}",
      );
    });
  }
}
