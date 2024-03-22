import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_test/globals/global_widgets.dart';
import 'package:flutter_application_test/globals/snackbar.dart';
import 'package:flutter_application_test/providers/responsive_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// This file contains all kinds of dialogs that are used throughout the app.
/// Note that dialogs on mobile/tablet are represented by a BottomSheet and
/// on desktop by a casuall dialog widget.
Future<T?> showResponsiveDialog<T>(
  context, {
  required ScreenType screenType,
  required Widget child,
  double heightFactor = 0.66,
}) {
  if (screenType != ScreenType.desktop) {
    return showModalBottomSheet(
        clipBehavior: Clip.antiAlias,
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return FractionallySizedBox(
            heightFactor: heightFactor,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: child,
              ),
            ),
          );
        });
  } else {
    return showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: IntrinsicWidth(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [child],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ConfirmDialog extends StatefulWidget {
  final String confirmQuestion;
  final Future<dynamic> Function() onConfirm;

  const ConfirmDialog({
    super.key,
    required this.confirmQuestion,
    required this.onConfirm,
  });

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  bool _isWidgetLocked = false;

  _lockWidget() => setState(() => _isWidgetLocked = true);
  _releaseWidget() => setState(() => _isWidgetLocked = false);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SpaceHSmall(),
              H2(widget.confirmQuestion),
              const SpaceH(),
              const SpaceH(),
              FilledButton(
                onPressed: _isWidgetLocked
                    ? null
                    : () {
                        _lockWidget();
                        // On success close this dialog, on error show a message and unlock widget
                        widget.onConfirm().then((_) {
                          Navigator.pop(context);
                        }).catchError((e) {
                          showError(
                              context,
                              AppLocalizations.of(context)!
                                  .arbitrary_error(e.toString()));
                          _releaseWidget();
                        });
                      },
                child: _isWidgetLocked
                    ? const SmallProgressIndicator()
                    : Text(AppLocalizations.of(context)!.btn_confirm),
              ),
              const SpaceH(),
              FilledButton.tonal(
                onPressed: _isWidgetLocked
                    ? null
                    : () {
                        Navigator.pop(context);
                      },
                child: Text(AppLocalizations.of(context)!.btn_cancel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
