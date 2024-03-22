import 'package:flutter/material.dart';

class L10n {
  static Locale selectedLocale = locales.values.elementAt(0);

  static final Map<String, Locale> locales = {
    'en-US': const Locale('en', 'US'),
    'de-DE': const Locale('de', 'DE'),
    'fr-FR': const Locale('fr', 'FR'),
  };

  static final Map<Locale, String> localesName = {
    const Locale('en', 'US'): 'English',
    const Locale('de', 'DE'): 'Deutsch',
    const Locale('fr', 'FR'): 'Français'
  };

  static Locale getLocaleByTag(String tag) {
    return locales[tag] ?? locales['en-US']!;
  }
}
