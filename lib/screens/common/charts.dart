import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:parse_server_sdk_flutter/parse_server_sdk_flutter.dart';

class Chart extends StatelessWidget {
  final List<ParseObject> rounds;

  const Chart({
    super.key,
    required this.rounds,
  });

  LinearGradient get _barsRedGradient => LinearGradient(
        colors: [
          Colors.red.shade400,
          Colors.red,
        ],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      );

  LinearGradient get _barsGreenGradient => LinearGradient(
        colors: [
          Colors.green.shade300,
          Colors.green,
        ],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      );

  // Stack of bars, i.e. contribution (colored) and target (grey)
  BarChartGroupData generateStackedBars(
      int x, double target, double contribution,
      {double barWidth = 50}) {
    return BarChartGroupData(
      x: x,
      groupVertically: true,
      barRods: [
        // Target
        BarChartRodData(
          width: barWidth,
          fromY: min(contribution, target),
          toY: target,
          color: Colors.grey.withOpacity(0.5),
          borderRadius: const BorderRadius.all(Radius.zero),
        ),
        // Contribution lower than target
        BarChartRodData(
          width: barWidth,
          fromY: 0,
          toY: min(contribution, target),
          gradient: _barsRedGradient,
          borderRadius: const BorderRadius.all(Radius.zero),
        ),
        // Contribution higher than target
        if (contribution > target)
          BarChartRodData(
            width: barWidth,
            fromY: target,
            toY: max(contribution, target),
            gradient: _barsGreenGradient,
            borderRadius: const BorderRadius.all(Radius.zero),
          ),
        // Target
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    FlBorderData border = FlBorderData(
      show: true,
      border: Border(
        bottom: BorderSide(
            style: BorderStyle.solid,
            width: 2,
            color: Theme.of(context).brightness == Brightness.light
                ? Colors.black
                : Colors.white54),
      ),
    );

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.center,
          titlesData: const FlTitlesData(show: false),
          barTouchData: BarTouchData(enabled: true),
          borderData: border,
          gridData: const FlGridData(
            drawHorizontalLine: true,
            drawVerticalLine: false,
          ),
          barGroups: rounds.map((round) {
            return generateStackedBars(0, round['target'].toDouble(),
                round['contribution'].toDouble());
          }).toList(),
        ),
      ),
    );
  }
}

class CircleChart extends StatelessWidget {
  final double percentage;
  final Widget? centerWidget;

  const CircleChart({
    Key? key,
    required this.percentage,
    this.centerWidget,
  }) : super(key: key);

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
        if (centerWidget != null) centerWidget!
      ],
    );
  }

  List<PieChartSectionData> _buildSections() {
    double greenPercentage = 0;
    double redPercentage = 0;
    double greyPercentage = 100;

    if (percentage < 100) {
      redPercentage = percentage;
      greyPercentage = greyPercentage - redPercentage;
    } else if (percentage >= 100) {
      greenPercentage = 100;
      greyPercentage = 0;
      redPercentage = 0;
    }

    double radius = 30;
    return [
      PieChartSectionData(
        color: Colors.grey.withOpacity(0.4),
        value: greyPercentage,
        showTitle: false,
        radius: radius,
      ),
      PieChartSectionData(
        color: Colors.red,
        value: redPercentage,
        showTitle: false,
        radius: radius,
      ),
      PieChartSectionData(
        color: Colors.green,
        value: greenPercentage,
        showTitle: false,
        radius: radius,
      ),
    ];
  }
}
