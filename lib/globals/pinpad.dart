import 'package:flutter/material.dart';
import 'package:Contrib/globals/global_widgets.dart';

class PinPad extends StatefulWidget {
  final PinPadController _controller;

  const PinPad(
    this._controller, {
    super.key,
  });

  @override
  PinPadState createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  int minNumber = 1;
  String showHint = "";

  @override
  void initState() {
    super.initState();
  }

  void _appendNumber(int number) {
    // No higher numbers than 99.999 are allowed. Show a message if exceeded.
    if (widget._controller.length() < 5) {
      setState(() {
        widget._controller.numberString =
            "${widget._controller.numberString}$number";
      });
    } else {
      setState(() {
        showHint = "Max. pin is 5 numbers";
      });
    }
  }

  void _deleteLastCharacter() {
    if (widget._controller.length() <= 1) {
      setState(() {
        widget._controller.numberString = "";
      });
    } else if (widget._controller.isNotEmpty()) {
      setState(() {
        widget._controller.numberString = widget._controller.numberString
            .substring(0, widget._controller.length() - 1);
      });
    }
  }

  @override
  void dispose() {
    widget._controller.dispose();
    super.dispose();
  }

  Widget _buttonContainer(btn) => Container(
      alignment: Alignment.center,
      width: 60,
      height: 60,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
      ),
      margin: const EdgeInsets.all(4),
      child: btn);

  Widget _keyButton(int num) => _buttonContainer(
        MaterialButton(
          elevation: 0,
          hoverElevation: 0,
          focusElevation: 0,
          highlightElevation: 0,
          height: 90,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(60),
          ),
          onPressed: () => _appendNumber(num),
          child: H3(
            num.toString(),
          ),
        ),
      );

  Widget deleteButton() => _buttonContainer(
        MaterialButton(
          height: 90,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(60),
          ),
          onPressed: () => _deleteLastCharacter(),
          child: const Icon(Icons.backspace),
        ),
      );

  Widget emptyButton() => _buttonContainer(
        const MaterialButton(
          height: 90,
          onPressed: null,
          child: null,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: widget._controller.numberString == ""
              ? H1(widget._controller.numberString,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white54
                      : Colors.black45)
              : H1(widget._controller.numberString),
        ),
        if (showHint != "") Center(child: SmallText(showHint)),
        const SpaceH(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _keyButton(1),
            _keyButton(2),
            _keyButton(3),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _keyButton(4),
            _keyButton(5),
            _keyButton(6),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _keyButton(7),
            _keyButton(8),
            _keyButton(9),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            emptyButton(),
            _keyButton(0),
            deleteButton(),
          ],
        ),
      ],
    );
  }
}

class PinPadController {
  String numberString = '';

  bool isNotEmpty() => numberString.isNotEmpty;
  int length() => numberString.length;
  bool greaterZero() => int.parse(numberString) > 0;

  void removeLeadingZero() {
    if (numberString.startsWith('0')) {
      numberString = numberString.substring(1, numberString.length);
    }
  }

  double getDouble() {
    return double.parse(numberString);
  }

  void dispose() {
    numberString = '0';
  }
}
