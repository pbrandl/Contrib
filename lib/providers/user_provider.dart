import 'package:flutter/material.dart';
import 'package:Contrib/l10n/l10n.dart';
import 'package:Contrib/themes/themes.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider extends InheritedWidget {
  final Themes theme;
  final User user;
  final UserLocale locale;

  const UserProvider({
    super.key,
    required this.user,
    required this.theme,
    required this.locale,
    required super.child,
  });

  static UserProvider? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UserProvider>();

  @override
  bool updateShouldNotify(covariant UserProvider oldWidget) {
    return oldWidget.theme != theme ||
        oldWidget.locale != locale ||
        oldWidget.user != user;
  }

  bool isLoggedIn() {
    return (user.getParseUser() != null);
  }
}

class UserLocale extends ChangeNotifier {
  Locale _userLocale = L10n.getLocaleByTag('en');

  UserLocale(String? localeKey) {
    if (localeKey == null) {
      setUserLocaleByTag('de-DE');
    } else {
      setUserLocaleByTag(localeKey);
    }
  }

  void setUserLocaleByTag(String tag) {
    _userLocale = L10n.getLocaleByTag(tag);
    _saveLocaleToSharedPreferences(_userLocale);
    notifyListeners(); // updates the user provider on widgets
  }

  Locale getUserLocale() {
    return _userLocale;
  }

  Future<void> _saveLocaleToSharedPreferences(Locale loc) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString('locale', loc.toLanguageTag());
  }
}

class User extends ChangeNotifier {
  ParseUser? _parseUser;

  String? id() => _parseUser!.objectId;
  String? username() => _parseUser!.username;
  ParseUser? getParseUser() => _parseUser;

  User({ParseUser? parseUser}) : _parseUser = parseUser;

  Future<ParseResponse> saveAndNotify() async {
    if (_parseUser == null) {
      return Future.error(NoUserException());
    }

    ParseResponse response = await _parseUser!.save();
    notifyListeners();
    return response;
  }

  void refetchParseUser() async {
    _parseUser = await ParseUser.currentUser() as ParseUser?;
    notifyListeners();
  }

  Future login(String username, String password) async {
    if (_parseUser != null) {
      return Future.error(AlreadyLoggedUserException());
    }

    ParseUser? user = ParseUser(username, password, null);

    final response = await user.login();

    if (response.success) {
      _parseUser = user;
      notifyListeners();
      return true;
    } else {
      return Future.error(response.error!.message);
    }
  }

  Future logout() async {
    if (_parseUser == null) return Future.error(NoUserException());

    ParseResponse response = await _parseUser!.logout();

    if (response.success) {
      _parseUser = null;
      notifyListeners();
      return true;
    } else {
      return false;
    }
  }

  Future signUp(String username, String password) async {
    final user = ParseUser.createUser(username, password);
    var response = await user.signUp(allowWithoutEmail: true);

    if (!response.success && response.error != null) {
      if (response.error!.type == "UsernameTaken") {
        return Future.error("UsernameTaken");
      } else {
        return Future.error(response.error!.message);
      }
    } else {
      login(username, password);
    }
  }
}

class AlreadyLoggedUserException implements Exception {
  AlreadyLoggedUserException() : super();

  @override
  String toString() {
    return "There is already a user logged in.";
  }
}

class UserNameTakenException implements Exception {
  UserNameTakenException() : super();

  @override
  String toString() {
    return "There is already a user logged in.";
  }
}

class NoUserException implements Exception {
  NoUserException() : super();

  @override
  String toString() {
    return 'No user found! Please log in.';
  }
}
