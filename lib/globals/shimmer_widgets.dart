import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:Contrib/globals/global_styles.dart';

class ShimmerH1 extends StatelessWidget {
  final double width;

  const ShimmerH1({
    super.key,
    this.width = 200,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ShimmerItem(
        height: 38,
        width: width,
      ),
    );
  }
}

class ShimmerH2 extends StatelessWidget {
  final double width;

  const ShimmerH2({
    super.key,
    this.width = 200,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ShimmerItem(
        height: 30,
        width: width,
      ),
    );
  }
}

class ShimmerText extends StatelessWidget {
  final double height;
  final double width;

  const ShimmerText({
    super.key,
    this.height = 16,
    this.width = 160,
  });

  @override
  Widget build(BuildContext context) {
    return const ShimmerItem(
      height: 16,
      width: 160,
    );
  }
}

class ShimmerTextBlock extends StatelessWidget {
  const ShimmerTextBlock({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        ShimmerItem(
          height: 18,
          width: double.infinity,
        ),
        SizedBox(height: 4),
        ShimmerItem(
          height: 18,
          width: double.infinity,
        ),
        SizedBox(height: 4),
        ShimmerItem(
          height: 18,
          width: double.infinity,
        ),
      ],
    );
  }
}

class ShimmerList extends StatelessWidget {
  final int itemCount;
  final bool isSliverList;

  const ShimmerList({
    super.key,
    required this.itemCount,
    this.isSliverList = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isSliverList) {
      return SliverList.builder(
        itemCount: itemCount,
        itemBuilder: (_, __) => const ShimmerListTile(),
      );
    } else {
      return ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (_, __) => const ShimmerListTile(),
      );
    }
  }
}

class ShimmerListTile extends StatelessWidget {
  const ShimmerListTile({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerItem(
            height: 40,
            width: 40,
            radius: Radius.circular(40),
          ),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerItem(
                height: 20,
                width: 140,
              ),
              SizedBox(height: 4),
              ShimmerItem(
                height: 16,
                width: 100,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShimmerItemCircular extends StatelessWidget {
  const ShimmerItemCircular({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return const ShimmerItem(
      height: 40,
      width: 40,
      radius: Radius.circular(40),
    );
  }
}

/// Makes a generic container-like item shimmer
class ShimmerItem extends StatefulWidget {
  final double height;
  final double width;
  final Radius radius;

  const ShimmerItem({
    super.key,
    required this.height,
    required this.width,
    this.radius = CiRadius.r3,
  });

  @override
  State<ShimmerItem> createState() => _ShimmerItemState();
}

class _ShimmerItemState extends State<ShimmerItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _colorAnimation = ColorTween(
      begin: Colors.grey.withOpacity(0.3),
      end: Colors.grey.withOpacity(0.8),
    ).animate(_controller);

    _controller.repeat(reverse: true);

    _controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: _colorAnimation.value,
        borderRadius: BorderRadius.all(widget.radius),
      ),
    );
  }
}

/// Makes a bar chart shimmer.
class BarChartShimmer extends StatefulWidget {
  final Radius radius;
  final bool animated;

  const BarChartShimmer({
    super.key,
    this.radius = CiRadius.r3,
    this.animated = true,
  });

  @override
  State<BarChartShimmer> createState() => _BarChartShimmerState();
}

class _BarChartShimmerState extends State<BarChartShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _colorAnimation = ColorTween(
      begin: Colors.grey.withOpacity(0.3),
      end: Colors.grey.withOpacity(0.8),
    ).animate(_controller);

    _controller.repeat(reverse: true);

    if (!widget.animated) _controller.stop();

    _controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  BarChartGroupData generateGroupData() {
    return BarChartGroupData(
      x: 0,
      groupVertically: true,
      barRods: [
        BarChartRodData(
            width: 50,
            fromY: 0,
            toY: 50,
            color: _colorAnimation.value,
            borderRadius: const BorderRadius.vertical(top: CiRadius.r3)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          BarChart(
            BarChartData(
              alignment: BarChartAlignment.center,
              titlesData: const FlTitlesData(show: false),
              barTouchData: BarTouchData(enabled: false),
              borderData: FlBorderData(
                show: true,
                border: Border(
                    bottom: BorderSide(
                  style: BorderStyle.solid,
                  width: 2,
                  color: _colorAnimation.value == null
                      ? Colors.grey
                      : _colorAnimation.value!,
                )),
              ),
              gridData: const FlGridData(show: false),
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  groupVertically: true,
                  barRods: [
                    BarChartRodData(
                        width: 50,
                        fromY: 0,
                        toY: 50,
                        color: _colorAnimation.value,
                        borderRadius:
                            const BorderRadius.vertical(top: CiRadius.r3)),
                  ],
                ),
                BarChartGroupData(
                  x: 0,
                  groupVertically: true,
                  barRods: [
                    BarChartRodData(
                        width: 50,
                        fromY: 0,
                        toY: 100,
                        color: _colorAnimation.value,
                        borderRadius:
                            const BorderRadius.vertical(top: CiRadius.r3)),
                  ],
                ),
                BarChartGroupData(
                  x: 0,
                  groupVertically: true,
                  barRods: [
                    BarChartRodData(
                        width: 50,
                        fromY: 0,
                        toY: 200,
                        color: _colorAnimation.value,
                        borderRadius:
                            const BorderRadius.vertical(top: CiRadius.r3)),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CircleChartShimmer extends StatefulWidget {
  const CircleChartShimmer({
    Key? key,
  }) : super(key: key);

  @override
  State<CircleChartShimmer> createState() => _CircleChartShimmerState();
}

class _CircleChartShimmerState extends State<CircleChartShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _colorAnimation = ColorTween(
      begin: Colors.grey.withOpacity(0.3),
      end: Colors.grey.withOpacity(0.8),
    ).animate(_controller);

    _controller.repeat(reverse: true);

    _controller.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center, // Centers the text within the stack
      children: [
        PieChart(
          PieChartData(
            pieTouchData: PieTouchData(enabled: false),
            borderData: FlBorderData(show: false),
            sectionsSpace: 0,
            centerSpaceRadius: 70, // Adjust for the size of the hole
            startDegreeOffset: -90,
            sections: _buildSections(),
          ),
        ),
        const ShimmerItem(height: 30, width: 30),
      ],
    );
  }

  List<PieChartSectionData> _buildSections() {
    return [
      PieChartSectionData(
        color: _colorAnimation.value,
        value: 100,
        showTitle: false,
        radius: 30,
      ),
    ];
  }
}
