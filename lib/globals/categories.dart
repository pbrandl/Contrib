import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Categories held in the database are stored in english. And therefore
/// need to be translated according to which language the user chose. In
/// order to get the right translation the category is translated with
/// AppLocalization.
String translateCategory(context, category) {
  Map<String, String> categories = getCategoryTranslations(context);

  return categories[category] ?? AppLocalizations.of(context)!.missing_category;
}

Map<String, String> getCategoryTranslations(context) {
  return {
    'Agriculture': AppLocalizations.of(context)!.agriculture,
    'Coworking Space': AppLocalizations.of(context)!.spaces,
    'Shop': AppLocalizations.of(context)!.shops,
    'Education': AppLocalizations.of(context)!.education,
    'Events': AppLocalizations.of(context)!.events,
    'Other': AppLocalizations.of(context)!.others,
  };
}

/// A global list of all categories
Map<String, String> categoryImages = {
  'Agriculture': 'assets/img/agriculture.webp',
  'Coworking Space': 'assets/img/coworking.webp',
  'Shop': 'assets/img/shops.webp',
  'Education': 'assets/img/education.webp',
  'Events': 'assets/img/events.webp',
  'Others': 'assets/img/others.webp'
};
