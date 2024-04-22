import 'package:flutter/material.dart';
import 'package:Contrib/globals/global_widgets.dart';
import 'package:Contrib/globals/custom_future_builder.dart';
import 'package:Contrib/globals/shimmer_widgets.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

class About extends StatefulWidget {
  final Future<List<ParseObject>> aboutFuture;

  const About({
    super.key,
    required this.aboutFuture,
  });

  @override
  State<About> createState() => _AboutState();
}

class _AboutState extends State<About> {
  Future<void> _launchUrl(url) async {
    if (!await launchUrl(Uri.parse(url))) {
      return Future.error('Could not launch $url.');
    }
  }

  Widget onLoaded(aboutData) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          H2(AppLocalizations.of(context)!.subtitle_description),
          Text(
            aboutData[0]['description'],
          ),
          const SizedBox(
            height: 16,
          ),
          Center(
              child: IconButton(
            onPressed: () => _launchUrl(aboutData[0]['websiteUrl']),
            icon: const Icon(Icons.language),
            tooltip: 'Website',
          )),
        ],
      );

  Widget onLoading() => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerH1(),
          ShimmerTextBlock(),
          SizedBox(
            height: 16,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ShimmerItem(
                height: 40,
                width: 40,
                radius: Radius.circular(40),
              ),
              ShimmerItem(
                height: 40,
                width: 40,
                radius: Radius.circular(40),
              ),
              ShimmerItem(
                height: 40,
                width: 40,
                radius: Radius.circular(40),
              ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomFutureBuilder<List<ParseObject>>(
          future: widget.aboutFuture,
          onLoaded: onLoaded,
          onLoading: onLoading(),
          onError: (msg) => Text(msg.toString()),
        )
      ],
    );
  }
}
