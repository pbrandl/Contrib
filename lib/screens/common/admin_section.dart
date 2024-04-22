import 'dart:io';
import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:Contrib/globals/dialogs.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/globals/snackbar.dart';
import 'package:Contrib/globals/keypad.dart';
import 'package:Contrib/providers/responsive_provider.dart';
import 'package:Contrib/providers/user_provider.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html show AnchorElement, Blob, Url;

/// The user who administates the common can soley see this section
/// Here the user can set new rounds, close the common, etc.
class AdminSection extends StatefulWidget {
  final String _commonId;
  final ParseUser _admin;
  final ParseObject? _round;

  const AdminSection(this._commonId, this._admin, this._round, {super.key});

  @override
  State<AdminSection> createState() => _AdminSectionState();
}

class _AdminSectionState extends State<AdminSection> {
  late ResponsiveProvider _responsiveProvider;
  late ScreenType _screenType;
  late UserProvider _userProvider;

  ParseObject? get _round => widget._round;
  bool _isWidgetLocked = false; // Locked if a current request is ongoing.
  _lockWidget() => setState(() => _isWidgetLocked = true);
  _releaseWidget() => setState(() => _isWidgetLocked = false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _userProvider = UserProvider.of(context)!;
    _userProvider.user.addListener(updateState);

    _responsiveProvider = ResponsiveProvider.of(context)!;
    _screenType = _responsiveProvider.screenType;
  }

  void updateState() {
    if (mounted) {
      setState(() {});
    } else {
      debugPrint("Disconnected. Please reload the page.");
    }
  }

  @override
  void dispose() {
    _userProvider.user.removeListener(updateState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        H3(AppLocalizations.of(context)!.administraion),
        const SpaceH(),
        const SpaceHSmall(),
        // A switch which handles the round (in)active status
        ToggleRoundWidget(round: _round, admin: widget._admin),
        const SpaceH(),
        DeleteRoundWidget(round: _round),
        const SpaceH(),
        DownloadRound(_round),
        const SpaceH(),
        // A button which handles the request of a new round.
        NewRoundWidget(
          admin: widget._admin,
          commonId: widget._commonId,
          screenType: _screenType,
        ),

        const SpaceH(),
      ],
    );
  }
}

class DeleteRoundWidget extends StatefulWidget {
  final ParseObject? round;

  const DeleteRoundWidget({
    super.key,
    required this.round,
  });

  @override
  State<DeleteRoundWidget> createState() => _DeleteRoundWidgetState();
}

class _DeleteRoundWidgetState extends State<DeleteRoundWidget> {
  bool _isWidgetLocked = false; // Indicate whether a request is
  _lockWidget() => setState(() => _isWidgetLocked = true);
  _releaseWidget() => setState(() => _isWidgetLocked = false);

  /// Delete the given round. After the round is deleted also the associated contributions
  /// are deleted. The admin panel is locked during the pending request.
  Future requestDeleteRound(ParseObject round) async {
    _lockWidget();

    // Delete the round (this sets the last round as current round)
    if (widget.round == null) return; // If there is no round, return
    final response = await round.delete();

    // Return the error, if any, else delete contributions of the round
    if (response.error != null) {
      _releaseWidget();
      var error = response.error!;
      return Future.error(error.message);
    } else {
      // Query the contibutions of this round
      final contribs = QueryBuilder<ParseObject>(ParseObject('Contributions'))
        ..whereEqualTo('roundId', round.toPointer());
      final response = await contribs.query();

      // Iterate through the results and delete each contribution
      if (response.results != null) {
        for (var contribution in response.results!) {
          await contribution.delete();
        }
      }

      _releaseWidget();
    }
  }

  Future deleteRound() async {
    if (_isWidgetLocked || widget.round == null) {
      showError(context, AppLocalizations.of(context)!.round_recall_blocked);
    } else {
      await requestDeleteRound(widget.round!).catchError((error) {
        showError(context,
            "${AppLocalizations.of(context)!.round_recall_error} Error ${error.toString()}");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BoldText(AppLocalizations.of(context)!.reset_current_round),
            ],
          ),
        ),
        TextButton(
          onPressed: widget.round == null
              ? null
              : () => showResponsiveDialog(context,
                  screenType: ResponsiveProvider.of(context)!.screenType,
                  child: ConfirmDialog(
                    confirmQuestion:
                        AppLocalizations.of(context)!.dialog_round_reset_header,
                    onConfirm: deleteRound,
                  )),
          child: EllipsisText(AppLocalizations.of(context)!.delete),
        ),
      ],
    );
  }
}

/// Creating a new round needs a short dialog to define the new round's target. This
/// differs between desktop and mobile. This widgets handels the responsiveness
/// and the target input.
class NewRoundWidget extends StatefulWidget {
  final String commonId;
  final ParseUser admin;
  final ScreenType screenType;

  const NewRoundWidget({
    super.key,
    required this.commonId,
    required this.admin,
    required this.screenType,
  });

  @override
  State<NewRoundWidget> createState() => _NewRoundWidgetState();
}

class _NewRoundWidgetState extends State<NewRoundWidget> {
  final KeyPadController _padController = KeyPadController();

  @override
  void initState() {
    super.initState();
  }

  bool _isLoading = false; // Indicate whether a request is
  _lockWidget() => setState(() => _isLoading = true);
  _releaseWidget() => setState(() => _isLoading = false);

  /// Create and initializes a new round. LiveQuery tracks the creation.
  /// After creation the user interface is set accordingly and new contributions
  /// are added to the new round.
  Future requesCreateRound(double target) async {
    _lockWidget();

    final common = ParseObject('Commons')..objectId = widget.commonId;

    final acl = ParseACL()
      ..setPublicReadAccess(allowed: true)
      ..setReadAccess(userId: widget.admin.objectId!, allowed: true)
      ..setWriteAccess(userId: widget.admin.objectId!, allowed: true);

    final roundObject = ParseObject('Rounds')
      ..set('contribution', 0)
      ..set('target', target)
      ..set('commonId', common.toPointer())
      ..setACL(acl);

    final response = await roundObject.save();

    if (response.error != null) {
      _releaseWidget();
      return Future.error(response.error!.message);
    }

    _releaseWidget();
  }

  /// Requests a new round to the server and handels the feedback which is displayed to
  /// the user as SnackBars.
  void createRound(double target) {
    requesCreateRound(target).then((_) {
      if (widget.screenType != ScreenType.desktop) Navigator.of(context).pop();
    }).catchError((error) {
      showError(
        context,
        "${AppLocalizations.of(context)!.new_round_error} Error: ${error.toString()}",
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget newRoundKeyPad = FractionallySizedBox(
      heightFactor: 1,
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              child: SizedBox(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(width: 700),
                    const SpaceH(),
                    const SpaceH(),
                    const SpaceH(),
                    SizedBox(
                      width: 270,
                      child: H2(AppLocalizations.of(context)!.next_target),
                    ),
                    const SpaceH(),
                    SizedBox(
                      width: 270,
                      child: KeyPad(_padController),
                    ),
                    const SpaceH(),
                    const SpaceH(),
                    SizedBox(
                      width: 270,
                      child: FilledButton(
                        onPressed: _isLoading
                            ? null
                            : () => createRound(_padController.getDouble()),
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
          if (_isLoading)
            LoadingWidget(
              loadingText: AppLocalizations.of(context)!.creating_round,
            )
        ],
      ),
    );

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BoldText(AppLocalizations.of(context)!.start_new_round),
                ],
              ),
            ),
            if (widget.screenType != ScreenType.desktop)
              TextButton(
                onPressed: () {
                  showModalBottomSheet(
                    isScrollControlled: true,
                    context: context,
                    builder: (BuildContext context) {
                      return FractionallySizedBox(
                        heightFactor: 1,
                        child: newRoundKeyPad,
                      );
                    },
                  );
                },
                child: Row(
                  children: [
                    EllipsisText(
                      AppLocalizations.of(context)!.new_round,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SpaceHSmall(),
        if (widget.screenType == ScreenType.desktop)
          NumberTextFieldButton(
            buttonLabel: AppLocalizations.of(context)!.new_round,
            textLabel: AppLocalizations.of(context)!.target,
            textPrefixIcon: const Icon(
              Icons.euro,
              size: 20,
            ),
            buttonPrefixWidget: !_isLoading
                ? null
                : Container(
                    width: 24,
                    height: 16,
                    padding: const EdgeInsets.only(right: 8),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                    )),
            onClick: (double target) {
              if (target > 0) {
                createRound(target);
              }
            },
          ),
      ],
    );
  }
}

class DownloadRound extends StatefulWidget {
  final ParseObject? _round;

  const DownloadRound(this._round, {super.key, required});

  @override
  State<DownloadRound> createState() => _DownloadRoundState();
}

class _DownloadRoundState extends State<DownloadRound> {
  bool _isLoading = false;
  _lockWidget() => setState(() => _isLoading = true);
  _releaseWidget() => setState(() => _isLoading = false);

  /// Downloads the current state of a round if widget is not locked.
  Future<List<ParseObject>> downloadContributions() async {
    _lockWidget();

    final query = QueryBuilder<ParseObject>(ParseObject('Contributions'))
      ..whereEqualTo('roundId', widget._round)
      ..keysToReturn(['sumContributions', 'userId'])
      ..includeObject(['userId'])
      ..setLimit(10000);

    final ParseResponse apiResponse = await query.query();

    _releaseWidget();
    if (apiResponse.success && apiResponse.results != null) {
      return apiResponse.results as List<ParseObject>;
    } else if (!apiResponse.success) {
      return Future.error(apiResponse.error!);
    } else {
      return [];
    }
  }

  Future<void> saveContributionsToCSV(List<ParseObject> contributions) async {
    _lockWidget();
    final List<List<dynamic>> csvData = [
      ['User', 'Contribution']
    ];

    for (final contribution in contributions) {
      // If no user is found return an 'user unknown'
      final userId = contribution.get<ParseObject>('userId')?['username'] ??
          'user unknown';
      final sumContributions = contribution.get<num>('sumContributions');

      csvData.add([userId, sumContributions]);
    }

    final String csv = const ListToCsvConverter().convert(csvData);

    // Use file picker to allow the user to choose the location to save the CSV file
    if (kIsWeb) {
      final bytes = utf8.encode(csv);
      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', 'contributions.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      final String? path = await FilePicker.platform.saveFile(
        fileName: 'contributions.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      // Save CSV data to the chosen file path
      if (path != null) {
        final File file = File(path);
        await file.writeAsString(csv);
      }
    }
    _releaseWidget();
  }

  void downloadHandler() {
    if (_isLoading) return;

    downloadContributions().then((contributions) {
      saveContributionsToCSV(contributions);
    }).catchError((error) {
      showError(context,
          "${AppLocalizations.of(context)!.download_error} Error: ${error.toString()}");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BoldText(AppLocalizations.of(context)!.download_current_round),
            ],
          ),
        ),
        TextButton(
          onPressed: widget._round == null ? null : downloadHandler,
          child: Row(
            children: [
              if (_isLoading)
                Container(
                  width: 22,
                  height: 14,
                  padding: const EdgeInsets.only(right: 8),
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              Text(AppLocalizations.of(context)!.download),
            ],
          ),
        )
      ],
    );
  }
}

class ToggleRoundWidget extends StatefulWidget {
  final ParseObject? round;
  final ParseUser admin;

  const ToggleRoundWidget({
    super.key,
    required this.round,
    required this.admin,
  });

  @override
  State<ToggleRoundWidget> createState() => _ToggleRoundWidgetState();
}

class _ToggleRoundWidgetState extends State<ToggleRoundWidget> {
  bool _isWidgetLocked = false;
  _lockWidget() => setState(() => _isWidgetLocked = true);
  _releaseWidget() => setState(() => _isWidgetLocked = false);

  /// Toggles the round status from active to inactive, and vice versa.
  /// If an error occures it is returned.
  Future toggleRoundStatus(ParseObject round) async {
    _lockWidget();

    final acl = ParseACL()
      ..setPublicReadAccess(allowed: true)
      ..setReadAccess(userId: widget.admin.objectId!, allowed: true)
      ..setWriteAccess(userId: widget.admin.objectId!, allowed: true);

    round
      ..set('isActive', !round['isActive'])
      ..setACL(acl);

    final response = await round.save();

    if (response.error != null) {
      return Future.error(response.error!.message);
    }
    _releaseWidget();
  }

  /// Request the toggle of the round status and manage the return to
  /// show the user a feedback as SnackBars.
  void toggleRoundStatusHandler() {
    if (_isWidgetLocked || widget.round == null) return;
    toggleRoundStatus(widget.round!).then((value) {
      if (widget.round!['isActive']) {
        showSuccess(context, AppLocalizations.of(context)!.round_started);
      } else {
        showSuccess(context, AppLocalizations.of(context)!.round_stopped);
      }
    }).catchError((error) {
      showError(context,
          "${AppLocalizations.of(context)!.round_status_error} Error: ${error.toString()}");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BoldText(AppLocalizations.of(context)!.switch_round_status),
              EllipsisText(widget.round == null
                  ? AppLocalizations.of(context)!.round_not_started
                  : !widget.round!['isActive']
                      ? AppLocalizations.of(context)!.currently_inactive
                      : AppLocalizations.of(context)!.currently_active),
            ],
          ),
        ),
        Row(children: [
          if (_isWidgetLocked)
            Container(
              width: 22,
              height: 14,
              padding: const EdgeInsets.only(right: 8),
              child: const CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
          Switch.adaptive(
            applyCupertinoTheme: true,
            value: (widget.round != null && widget.round!['isActive']),
            onChanged: _isWidgetLocked || widget.round == null
                ? null
                : (_) => toggleRoundStatusHandler(),
          ),
        ]),
      ],
    );
  }
}
