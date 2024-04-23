import 'package:Contrib/globals/dialogs.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/globals/signup_login.dart';
import 'package:Contrib/providers/responsive_provider.dart';
import 'package:Contrib/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class NotLoggedInWidget extends StatefulWidget {
  const NotLoggedInWidget({
    super.key,
  });

  @override
  State<NotLoggedInWidget> createState() => _NotLoggedInWidgetState();
}

class _NotLoggedInWidgetState extends State<NotLoggedInWidget> {
  late ResponsiveProvider _responsiveProvider;
  late ScreenType _screenType;
  late UserProvider userProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _responsiveProvider = ResponsiveProvider.of(context)!;
    _screenType = _responsiveProvider.screenType;

    userProvider = UserProvider.of(context)!;
    userProvider.user.addListener(updateState);
  }

  void updateState() {
    if (mounted) {
      setState(() {}); // Update the UI as needed if not logged in
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: SizedBox(
            width: 300,
            child: Text(AppLocalizations.of(context)!.not_logged_in,
                textAlign: TextAlign.center),
          ),
        ),
        const SpaceH(),
        Center(
          child: ElevatedButton(
              child: SizedBox(
                width: 70,
                child: Center(
                  child: Text(AppLocalizations.of(context)!.login),
                ),
              ),
              onPressed: () => showResponsiveDialog(
                    context,
                    screenType: _screenType,
                    child: const SignUpLogInTabBar(
                      popOnLogin: true,
                    ),
                    heightFactor: 1,
                    applyPadding: false,
                  )
              // GoRouter.of(context).go('/commons', extra: "DnvLyi470Q"),
              ),
        ),
      ],
    );
  }
}
