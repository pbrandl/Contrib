import 'package:flutter/material.dart';

import 'package:flutter_application_test/l10n/l10n.dart';
import 'package:flutter_application_test/providers/user_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:flutter_application_test/router/app_router.dart';

import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'themes/themes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Try reading device settings. If it doesn't exist, returns null.
  final SharedPreferences devicePref = await SharedPreferences.getInstance();
  final bool? themeMode = devicePref.getBool('isDarkModeSet');
  final String? locale = devicePref.getString('locale');

  // Connect to Parse Server Backend and get current user
  const keyApplicationId = 'jh0lx2J0iEiUd5vciubOTTkbOUCwP2PELMSfOK38';
  const keyClient = 'xAIMPMU3p9HY2lIydYSLR4BgssaQXceWgnBwG9Av';
  const parseServerUrl = 'https://parseapi.back4app.com';
  const liveQueryUrl = 'https://commons-test.b4a.io';

  await Parse().initialize(
    keyApplicationId,
    parseServerUrl,
    clientKey: keyClient,
    liveQueryUrl: liveQueryUrl,
    autoSendSessionId: true,
    debug: true,
  );

  final ParseUser? currentUser = await ParseUser.currentUser() as ParseUser?;

  runApp(
    UserProvider(
      user: User(parseUser: currentUser),
      theme: Themes(isDark: themeMode),
      locale: UserLocale(locale),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    Key? key,
  }) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  UserProvider? userProvider;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    userProvider = UserProvider.of(context);
    userProvider?.theme.addListener(updateState);
    userProvider?.locale.addListener(updateState);
  }

  void updateState() {
    setState(() {});
  }

  @override
  void dispose() {
    super.dispose();
    userProvider?.theme.removeListener(updateState);
    userProvider?.locale.removeListener(updateState);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: MaterialApp.router(
        title: 'Commons',
        themeMode: userProvider!.theme.getThemeMode(),
        theme: Themes.lightTheme,
        darkTheme: Themes.darkTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        locale: userProvider!.locale.getUserLocale(),
        supportedLocales: L10n.locales.values,
        routerConfig: getAppRouter(),
      ),
    );
  }
}
