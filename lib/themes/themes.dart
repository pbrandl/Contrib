import 'package:flutter/material.dart';
import 'package:flutter_application_test/globals/global_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';

Color seedColor = const Color.fromARGB(255, 9, 177, 255);

class Themes with ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode getThemeMode() => _mode;

  Themes({bool? isDark}) {
    setMode(isDark);
  }

  void setMode(bool? isDark) {
    if (isDark == null) {
      _mode = ThemeMode.system;
    } else if (isDark) {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.light;
    }
    _saveThemeToSharedPreferences(isDark);
    notifyListeners();
  }

  static ThemeData _themeData(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        background: Brightness.dark == brightness ? Colors.black : Colors.white,
        onSurface: Brightness.dark == brightness ? Colors.white : Colors.black,
      ),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      brightness: brightness,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(CiRadius.r1),
          ),
        ),
      ),
    );
  }

  static final ThemeData darkTheme = _themeData(Brightness.dark);
  static final ThemeData lightTheme = _themeData(Brightness.light);

  Future<void> _saveThemeToSharedPreferences(bool? isDark) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    if (isDark == null) {
      prefs.remove('isDarkModeSet');
    } else {
      prefs.setBool('isDarkModeSet', isDark);
    }
  }
}
