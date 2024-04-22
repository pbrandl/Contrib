import 'package:flutter/material.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/globals/snackbar.dart';
import 'package:Contrib/providers/responsive_provider.dart';
import 'package:Contrib/providers/user_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SignUpLogIn extends StatefulWidget {
  const SignUpLogIn({super.key});

  @override
  SignUpLogInState createState() => SignUpLogInState();
}

class SignUpLogInState extends State<SignUpLogIn> {
  final _controllerSignUpEmail = TextEditingController();
  final _controllerSignUpPassword = TextEditingController();
  final _controllerLoginEmail = TextEditingController();
  final _controllerLoginPassword = TextEditingController();

  bool _isLoggingIn = false;
  int _selectedTabBar = 0;

  late ResponsiveProvider _responsiveProvider;
  late ScreenType _screenType;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _responsiveProvider = ResponsiveProvider.of(context)!;
    _screenType = _responsiveProvider.screenType;
  }

  @override
  Widget build(BuildContext context) {
    Widget signUpWidget = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          H2(AppLocalizations.of(context)!.signup),
          const SpaceH(),
          TextInputField(
            label: AppLocalizations.of(context)!.name,
            controller: _controllerSignUpEmail,
            keyboardType: TextInputType.text,
          ),
          const SpaceH(),
          TextInputField(
            label: AppLocalizations.of(context)!.password,
            controller: _controllerSignUpPassword,
            isPasswordField: true,
          ),
          const SpaceH(),
          FilledButton(
              child: Text(AppLocalizations.of(context)!.signup),
              onPressed: () {
                // Block the UI during logging in
                if (mounted) {
                  setState(() {
                    _isLoggingIn = true;
                  });
                }

                // Sign up the user
                UserProvider.of(context)!
                    .user
                    .signUp(
                      _controllerSignUpEmail.text,
                      _controllerSignUpPassword.text,
                    )
                    .catchError(
                  (e) {
                    showError(
                        context,
                        e == "UsernameTaken"
                            ? AppLocalizations.of(context)!.user_taken
                            : AppLocalizations.of(context)!.arbitrary_error(e));
                  },
                );

                // If still mounted release the UI
                if (mounted) {
                  setState(() {
                    _isLoggingIn = false;
                  });
                }
              }),
          // const SpaceH(),
        ],
      ),
    );

    logInHandler() async {
      if (_controllerLoginEmail.text == "" ||
          _controllerLoginPassword.text == "") {
        showError(
          context,
          AppLocalizations.of(context)!.no_login_data,
        );

        return;
      }
      // Block the UI during logging in
      setState(() {
        _isLoggingIn = true;
      });

      // Log in the user
      await UserProvider.of(context)!
          .user
          .login(
            _controllerLoginEmail.text,
            _controllerLoginPassword.text,
          )
          .catchError(
        (e) {
          showError(context, e.toString());
        },
      );

      // If still mounted release the UI
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
      }
    }

    Widget logInWidget = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              H2(AppLocalizations.of(context)!.login),
              Tooltip(
                message: "Not supported for Prototype.",
                child: TextButtonAccent(
                  onPressed: () => {
                    // showBottomSheet(
                    //   context: context,
                    //   builder: (context) {
                    //     // const ResetPasswordPage();
                    //   },
                    // )
                  },
                  text: AppLocalizations.of(context)!.forgot_password,
                ),
              ),
            ],
          ),
          const SpaceH(),
          TextInputField(
            // TODO: Prototype displays name instead of mail
            label: AppLocalizations.of(context)!.name,
            controller: _controllerLoginEmail,
            keyboardType: TextInputType.text,
          ),
          const SizedBox(
            height: 16,
          ),
          TextInputField(
            label: AppLocalizations.of(context)!.password,
            isPasswordField: true,
            controller: _controllerLoginPassword,
          ),
          const SpaceH(),
          FilledButton(
            onPressed: _isLoggingIn ? null : logInHandler,
            child: Text(AppLocalizations.of(context)!.login),
          ),
        ],
      ),
    );

    Widget signUpLogInTabBar() => DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const AppLogo(height: 200, width: double.infinity),
              TabBar(
                onTap: (index) {
                  setState(() {
                    _selectedTabBar = index;
                  });
                },
                tabs: [
                  Tab(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(AppLocalizations.of(context)!.login),
                    ),
                  ),
                  Tab(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(AppLocalizations.of(context)!.signup),
                    ),
                  ),
                ],
              ),
              Builder(builder: (_) {
                return Padding(
                    padding: const EdgeInsets.all(16),
                    child: _selectedTabBar == 1 ? signUpWidget : logInWidget);
              }),
            ],
          ),
        );

    return Stack(
      children: [
        if (!_isLoggingIn)
          _screenType != ScreenType.mobile
              ? Center(
                  child: SingleChildScrollView(
                    child: Dialog(
                      backgroundColor: Theme.of(context).cardColor,
                      shadowColor: Colors.black,
                      elevation: 2,
                      child: Container(
                          width: 500,
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.only(
                                topRight: Radius.circular(30),
                                topLeft: Radius.circular(30)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: signUpLogInTabBar()),
                    ),
                  ),
                )
              : Container(
                  height: double.infinity,
                  color: Theme.of(context).cardColor,
                  child: Dialog.fullscreen(
                    child: SingleChildScrollView(child: signUpLogInTabBar()),
                  ),
                )
        else
          const Center(
            child: CircularProgressIndicator(),
          )
      ],
    );
  }
}
