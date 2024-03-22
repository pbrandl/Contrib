import 'package:flutter/material.dart';
import 'package:flutter_application_test/globals/global_widgets.dart';
import 'package:flutter_application_test/globals/shimmer_widgets.dart';

/// This class defines how the shimmer widget looks during loading the initial
/// common screen.
class ShimmerCommon extends StatelessWidget {
  const ShimmerCommon({super.key});

  Widget commonHeaderShimmmer() => const Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShimmerItemCircular(),
                  ResponsiveVSpace(),
                  ShimmerItemCircular(),
                  ResponsiveVSpace(),
                  ShimmerItemCircular(),
                ],
              ),
              ShimmerH1(width: 100)
            ],
          ),
          SpaceHSmall(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ShimmerH1(width: 150),
              ShimmerH1(width: 100),
            ],
          ),
        ],
      );

  Widget chartSectionShimmer() => const Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SpaceH(),
          SpaceH(),
          Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [ShimmerItem(height: 16, width: 50)]),
          SizedBox(height: 200, child: CircleChartShimmer())
        ],
      );

  Widget aboutSectionShimmer() => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SpaceH(),
          ShimmerH2(),
          ShimmerTextBlock(),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        commonHeaderShimmmer(),
        const SpaceH(),
        const SpaceH(),
        chartSectionShimmer(),
        const SpaceH(),
        const SpaceH(),
        const SpaceH(),
        aboutSectionShimmer(),
      ],
    );
  }
}
