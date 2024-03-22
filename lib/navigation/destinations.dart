import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class Destination {
  final String title;
  final IconData icon;

  const Destination(this.title, this.icon);
}

List<Destination> getAllDestinations(BuildContext context) {
  AppLocalizations l10n = AppLocalizations.of(context)!;

  return <Destination>[
    Destination(l10n.nav_commons, Icons.home),
    Destination(l10n.title_search, Icons.search),
    Destination(l10n.title_map, Icons.map_outlined),
    Destination(l10n.title_profile, Icons.person),
  ];
}
