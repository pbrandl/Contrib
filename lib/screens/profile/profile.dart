import 'package:flutter/material.dart';
import 'package:flutter_application_test/globals/dialogs.dart';
import 'package:flutter_application_test/globals/global_widgets.dart';
import 'package:flutter_application_test/l10n/l10n.dart';
import 'package:flutter_application_test/providers/responsive_provider.dart';
import 'package:flutter_application_test/providers/user_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class ProfileWidget extends StatefulWidget {
  const ProfileWidget({super.key});

  @override
  State<ProfileWidget> createState() => _ProfileWidgetState();
}

class _ProfileWidgetState extends State<ProfileWidget> {
  late ResponsiveProvider _responsiveProvider;
  late ScreenType _screenType;
  late UserProvider _userProvider;

  bool isThemeChoice = false;
  bool isPasswordChanged = false;
  bool isMailChanged = false;
  bool isNameChanged = false;
  bool isIbanChanged = false;
  bool isMobile = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _userProvider = UserProvider.of(context)!;
    _userProvider.user.addListener(() {
      setState(() {});
    });

    _responsiveProvider = ResponsiveProvider.of(context)!;
    _screenType = _responsiveProvider.screenType;
  }

  Widget logoutTile(context) => CustomListTile(
        leadingWidget: const Icon(Icons.logout, color: Colors.red),
        titleName: AppLocalizations.of(context)!.logout,
        subtitleName: AppLocalizations.of(context)!.logout_subtitle,
        color: Colors.red,
        onTapFunction: () {
          showResponsiveDialog(context,
              screenType: _screenType,
              child: ConfirmDialog(
                confirmQuestion:
                    AppLocalizations.of(context)!.dialog_logout_header,
                onConfirm: () => UserProvider.of(context)!.user.logout(),
              ));
        },
      );

  // changePassword(String password) async {
  //   ParseUser? user = _userProvider.user.getParseUser();

  //   if (user == null) {
  //     return Future.error(NoUserException());
  //   }

  //   user.set('password', password);

  //   ParseResponse response = await user.save();

  //   if (response.success) {
  //     showSuccessPasswordChange();
  //   } else if (response.error != null) {
  //     showErrorPasswordChange();
  //   }
  // }

  // The email as list tile
  Widget emailTile() => CustomListTile(
        enableHoverEffect: false,
        // TODO: Prototype displays username instead of name
        leadingWidget: const Icon(Icons.person),
        titleName: AppLocalizations.of(context)!.name,
        subtitleName: UserProvider.of(context)!.user.username()!,
      );

  // The email as list tile
  Widget deleteUserTile() => CustomListTile(
        leadingWidget: const Icon(Icons.cancel_presentation, color: Colors.red),
        titleName: AppLocalizations.of(context)!.delete,
        subtitleName: AppLocalizations.of(context)!.delete_account,
        color: Colors.red,
        enableHoverEffect: false,
        onTapFunction: () {
          showResponsiveDialog(
            context,
            screenType: _screenType,
            child: ConfirmDialog(
              confirmQuestion:
                  AppLocalizations.of(context)!.confirm_delete_account,
              // TODO: Prototype status only logs users out instead delete user
              onConfirm: () => UserProvider.of(context)!.user.logout(),
            ),
          );
        },
      );

  /// Displays a column of options available to change the theme
  showThemeDialog() async {
    Widget options({required popOnSelect}) {
      ThemeMode currentTheme = UserProvider.of(context)!.theme.getThemeMode();
      return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              H2(AppLocalizations.of(context)!.theme_desc),
              const SpaceH(),
              CustomListTile(
                titleName: AppLocalizations.of(context)!.system,
                trailingWidget: currentTheme == ThemeMode.system
                    ? const Icon(Icons.check)
                    : null,
                onTapFunction: () {
                  UserProvider.of(context)!.theme.setMode(null);
                  setState(() {}); // update UI to display the 'check' icon
                  if (popOnSelect) Navigator.pop(context);
                },
              ),
              CustomListTile(
                titleName: AppLocalizations.of(context)!.light,
                trailingWidget: currentTheme == ThemeMode.light
                    ? const Icon(Icons.check)
                    : null,
                onTapFunction: () {
                  UserProvider.of(context)!.theme.setMode(false);
                  setState(() {}); // update UI to display the 'check' icon
                  if (popOnSelect) Navigator.pop(context);
                },
              ),
              CustomListTile(
                titleName: AppLocalizations.of(context)!.dark,
                trailingWidget: currentTheme == ThemeMode.dark
                    ? const Icon(Icons.check)
                    : null,
                onTapFunction: () {
                  UserProvider.of(context)!.theme.setMode(true);
                  setState(() {}); // update UI to display the 'check' icon
                  if (popOnSelect) Navigator.pop(context);
                },
              ),
              const SpaceHSmall()
            ],
          ));
    }

    if (isMobile) {
      showModalBottomSheet(
        showDragHandle: true,
        context: context,
        builder: (context) => options(popOnSelect: true),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context)!.btn_confirm),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
          content: SizedBox(
            width: 500,
            height: 300,
            child: options(popOnSelect: false),
          ),
        ),
      );
    }
  }

  /// Displays a column of options available to change the theme
  showLocaleDialog() async {
    Widget options({required popOnSelect}) {
      Locale currentLocale = UserProvider.of(context)!.locale.getUserLocale();
      return Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              H2(AppLocalizations.of(context)!.language),
              const SpaceH(),
              for (var locale in L10n.locales.values)
                CustomListTile(
                  titleName: L10n.localesName[locale]!,
                  trailingWidget:
                      currentLocale == locale ? const Icon(Icons.check) : null,
                  onTapFunction: () {
                    UserProvider.of(context)!
                        .locale
                        .setUserLocaleByTag(locale.toLanguageTag());
                    setState(() {}); // update UI to display the 'check' icon
                    if (popOnSelect) Navigator.pop(context);
                  },
                ),
              const SpaceHSmall()
            ],
          ));
    }

    if (isMobile) {
      showModalBottomSheet(
        showDragHandle: true,
        context: context,
        builder: (context) => options(popOnSelect: true),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context)!.btn_confirm),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
          content: SizedBox(
            width: 500,
            height: 300,
            child: options(popOnSelect: false),
          ),
        ),
      );
    }
  }

  Widget passwordTile() => CustomListTile(
        enableHoverEffect: false,
        leadingWidget: const Icon(Icons.https_sharp),
        titleName: AppLocalizations.of(context)!.password,
        subtitleName: "********",
      );

  Widget themeTile(context) => CustomListTile(
        enableHoverEffect: false,
        leadingWidget: const Icon(Icons.light_mode),
        titleName: AppLocalizations.of(context)!.theme,
        subtitleName: AppLocalizations.of(context)!.theme_desc,
        onTapFunction: showThemeDialog,
        trailingWidget: const Icon(Icons.chevron_right),
      );

  Widget languageTile(context) => CustomListTile(
        enableHoverEffect: false,
        leadingWidget: const Icon(Icons.flag),
        titleName: AppLocalizations.of(context)!.language,
        subtitleName: AppLocalizations.of(context)!.language_desc,
        onTapFunction: showLocaleDialog,
        trailingWidget: const Icon(Icons.chevron_right),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32),
            constraints: const BoxConstraints(
              maxWidth: 600,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SpaceH(),
                const SpaceH(),
                Padding(
                  padding: const EdgeInsets.only(left: 16.0),
                  child: H1(AppLocalizations.of(context)!.title_profile),
                ),
                const SpaceHSmall(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (UserProvider.of(context)!.isLoggedIn())
                      CustomContainer(
                        child: Column(children: [
                          emailTile(),
                          passwordTile(),
                          // deleteUserTile(), TODO: finalize delete process
                        ]),
                      ),
                    if (!UserProvider.of(context)!.isLoggedIn())
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: FilledButton.tonal(
                              child: Text(AppLocalizations.of(context)!.login),
                              onPressed: () =>
                                  GoRouter.of(context).go('/commons'),
                            ),
                          ),
                          const SizedBox(
                            width: 32,
                          ),
                          Expanded(
                            child: FilledButton.tonal(
                              child: Text(AppLocalizations.of(context)!.signup),
                              onPressed: () =>
                                  GoRouter.of(context).go('/commons'),
                            ),
                          )
                        ],
                      ),
                    const SpaceH(),
                    const SpaceH(),
                    Padding(
                        padding: const EdgeInsets.only(left: 16.0),
                        child: H2(
                            AppLocalizations.of(context)!.subtitle_settings)),
                    const SpaceHSmall(),
                    CustomContainer(
                        child: Column(children: [
                      themeTile(context),
                      languageTile(context),
                      if (UserProvider.of(context)!.isLoggedIn())
                        Column(children: [logoutTile(context)]),
                    ])),
                  ],
                ),
                const SpaceH(),
                const SpaceH(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
