import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:Contrib/globals/global_styles.dart';
import 'package:Contrib/globals/snackbar.dart';
import 'package:Contrib/providers/responsive_provider.dart';
import 'package:go_router/go_router.dart';

class CommonLogo extends StatelessWidget {
  final String url;

  const CommonLogo({
    super.key,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(
          Radius.circular(50),
        ),
        image: DecorationImage(
          image: NetworkImage(url),
        ),
      ),
      width: 40,
      height: 40,
    );
  }
}

class CommonAvatar extends StatelessWidget {
  final String commonName;

  Color getRandomColor() {
    // Define a list of nice colors (in HEX format)
    List<String> colors = [
      'FF6347', // Tomato
      'FFA07A', // Light Salmon
      'FFD700', // Gold
      'F0E68C', // Khaki
      '90EE90', // Light Green
      '20B2AA', // Light Sea Green
      '00CED1', // Dark Turquoise
      '1E90FF', // Dodger Blue
      'DA70D6', // Orchid
      'FF69B4', // Hot Pink
      'BDB76B', // Dark Khaki
      '8FBC8F', // Dark Sea Green
      'DAA520', // Goldenrod
      'CD853F', // Peru
      'F4A460', // Sandy Brown
      '6B8E23', // Olive Drab
      '4682B4', // Steel Blue
      'D2B48C', // Tan
      '8B4513', // Saddle Brown
      '5F9EA0', // Cadet Blue
    ];

    // Create a Random object
    Random random = Random(commonName.codeUnitAt(0));
    int index = random.nextInt(colors.length);

    // Convert the HEX color string to a Color object
    int selectedColorInt =
        int.parse(colors[index], radix: 16) + 0xFF000000; // Add opacity
    Color selectedColor = Color(selectedColorInt);

    return selectedColor;
  }

  const CommonAvatar({
    super.key,
    required this.commonName,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: getRandomColor(),
      child: Text(commonName),
    );
  }
}

class CustomListTile extends StatelessWidget {
  final Widget? leadingWidget;
  final VoidCallback? onTapFunction;
  final Widget? trailingWidget;
  final bool enableHoverEffect;
  final bool enableFocusEffect;
  final Color? backgroundColor;
  final EdgeInsets? padding;

  final String? subtitleName;
  final String titleName;
  final Color? color;

  const CustomListTile({
    super.key,
    this.leadingWidget,
    this.onTapFunction,
    required this.titleName,
    this.enableHoverEffect = true,
    this.enableFocusEffect = true,
    this.backgroundColor,
    this.trailingWidget,
    this.subtitleName,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Wrap ListTile with a Container to apply the border radius
    return ListTile(
      selectedColor: enableFocusEffect ? null : Colors.transparent,
      splashColor: enableFocusEffect ? null : Colors.transparent,
      focusColor: enableFocusEffect ? null : Colors.transparent,
      hoverColor: enableHoverEffect ? null : Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(CiRadius.r1),
      ),
      contentPadding: padding,
      leading: leadingWidget,
      title: Text(
        titleName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: trailingWidget,
      subtitle: subtitleName != null
          ? Text(
              subtitleName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: color != null ? TextStyle(color: color) : null,
            )
          : null,
      onTap: onTapFunction,
    );
  }
}

class CommonNavListTile extends StatelessWidget {
  final String titleName;
  final String subtitleName;
  final String? leadingLogoUrl;
  final String commonObjectId;
  final Widget? trailingWidget;
  final bool padding;

  const CommonNavListTile(
      {super.key,
      required this.titleName,
      required this.subtitleName,
      required this.commonObjectId,
      this.leadingLogoUrl,
      this.trailingWidget,
      this.padding = true});

  void goTo(context) => GoRouter.of(context).pushNamed(
        'detail',
        pathParameters: <String, String>{'id': commonObjectId},
      );

  @override
  Widget build(BuildContext context) {
    return CustomListTile(
      leadingWidget: leadingLogoUrl == null
          ? CommonAvatar(commonName: titleName[0])
          : CommonLogo(
              url: leadingLogoUrl!,
            ),
      titleName: titleName,
      subtitleName: subtitleName,
      trailingWidget: trailingWidget ??
          CustomIconButton(
            onPressed: () => goTo(context),
            icon: Icons.chevron_right,
          ),
      onTapFunction: () => goTo(context),
      padding: padding ? null : EdgeInsets.zero,
    );
  }
}

class CustomSegmentedButton<T> extends SegmentedButton {
  CustomSegmentedButton({
    super.key,
    required bool showSelectedIcon,
    required Widget? selectedIcon,
    required List<ButtonSegment<String>> segments,
    required Set<String> selected,
    required ValueChanged<Set<dynamic>> onSelectionChanged,
  }) : super(
          showSelectedIcon: showSelectedIcon,
          selectedIcon: selectedIcon,
          segments: segments,
          selected: selected,
          onSelectionChanged: onSelectionChanged,
          style: ButtonStyle(
            visualDensity: const VisualDensity(horizontal: 0.5, vertical: 0.5),
            shape: MaterialStateProperty.resolveWith<OutlinedBorder>(
                (Set<MaterialState> states) {
              return const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(CiRadius.r1),
              );
            }),
          ),
        );
}

class NumberTextFieldButton extends StatelessWidget {
  final String buttonLabel;
  final String textLabel;
  final Widget? buttonSuffixWidget;
  final Widget? buttonPrefixWidget;
  final Icon? textPrefixIcon;
  final Function(double)? onClick;

  final TextEditingController _textController = TextEditingController();

  NumberTextFieldButton(
      {super.key,
      required this.onClick,
      required this.buttonLabel,
      required this.textLabel,
      this.buttonSuffixWidget,
      this.buttonPrefixWidget,
      this.textPrefixIcon});

  final String _onErrorText = "Enter a number between 1 and 99.999.";

  String? validate(String? input) {
    if (input != null && input.isNotEmpty) {
      if (int.tryParse(input) == null || input.length > 5) {
        return _onErrorText;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _textController,
      keyboardType: const TextInputType.numberWithOptions(),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^[1-9]\d*$')),
      ],
      validator: validate,
      onChanged: (input) {
        String? error = validate(input);
        if (error != null) {
          showError(context, error);
          _textController.text = _textController.text.substring(0, 5);
        }
      },
      onEditingComplete: () {
        // Triggered when the user presses the "Done" or "Enter" key
        String input = _textController.text;
        if (input.isNotEmpty && validate(input) == null) {
          double number = double.parse(_textController.text);
          if (onClick != null) {
            onClick!(number);
          }
        }
      },
      decoration: InputDecoration(
        filled: true,
        fillColor: Theme.of(context).colorScheme.background.withOpacity(0.8),
        focusColor: Theme.of(context).colorScheme.background,
        hoverColor: Colors.transparent,
        prefixIcon: textPrefixIcon,
        label: Text(
          textLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(CiRadius.r3),
            borderSide:
                BorderSide(width: 1, color: Theme.of(context).splashColor)),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(width: 1, color: Colors.grey.withOpacity(0.5)),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        suffixIcon: IntrinsicWidth(
          child: Container(
            margin: const EdgeInsets.all(8),
            child: TextButton(
              onPressed: onClick == null
                  ? null
                  : () {
                      String input = _textController.text;
                      if (input.isNotEmpty && validate(input) == null) {
                        double number = double.parse(_textController.text);
                        onClick!(number);
                      } else {
                        showError(context, _onErrorText);
                      }
                    },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (buttonPrefixWidget != null) buttonPrefixWidget!,
                  Text(buttonLabel),
                  if (buttonSuffixWidget != null) const SizedBox(width: 10),
                  if (buttonSuffixWidget != null) buttonSuffixWidget!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TextButtonAccent extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const TextButtonAccent({
    super.key,
    required this.onPressed,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      hoverColor: Theme.of(context).cardColor,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      borderRadius: const BorderRadius.all(CiRadius.r3),
      onTap: onPressed,
      child: EllipsisText(
        text,
        color: onPressed == null
            ? Theme.of(context).disabledColor
            : Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class SpaceHSmall extends SizedBox {
  const SpaceHSmall({
    super.key,
  }) : super(height: 8);
}

class SpaceH extends SizedBox {
  const SpaceH({
    super.key,
  }) : super(height: 16);
}

class H1 extends Text {
  H1(super.text, {super.key, Color? color})
      : super(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 32.0,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        );
}

class H2 extends Text {
  H2(super.text, {super.key, Color? color})
      : super(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 22.0,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        );
}

class H3 extends Text {
  H3(super.text, {super.key, Color? color})
      : super(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        );
}

class SmallText extends Text {
  SmallText(super.text, {super.key, Color? color})
      : super(
          style: TextStyle(
            fontSize: 12.0,
            color: color,
          ),
        );
}

class BoldText extends Text {
  BoldText(super.text, {super.key, Color? color})
      : super(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        );
}

class EllipsisText extends Text {
  EllipsisText(super.text, {super.key, Color? color})
      : super(
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color, fontSize: 14),
        );
}

class TextInputField extends StatefulWidget {
  final String label;
  final bool isFocused;
  final TextEditingController controller;
  final TextInputFormatter? formatter;
  final TextInputType? keyboardType;
  final int? maxLength;
  final String? prefixText;
  final dynamic validator;
  final bool enabled;
  final bool isPasswordField;
  final int maxLines;
  final String? hintText;

  const TextInputField({
    super.key,
    this.isFocused = false,
    required this.label,
    required this.controller,
    this.enabled = true,
    this.keyboardType,
    this.formatter,
    this.validator,
    this.prefixText,
    this.maxLength,
    this.hintText,
    this.isPasswordField = false,
    this.maxLines = 1,
  });

  @override
  State<TextInputField> createState() => _TextInputFieldState();
}

class _TextInputFieldState extends State<TextInputField> {
  late bool _obscureText;

  @override
  initState() {
    super.initState();
    _obscureText = widget.isPasswordField;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      enabled: widget.enabled,
      maxLength: widget.maxLength,
      maxLines: widget.maxLines,
      controller: widget.controller,
      inputFormatters: widget.formatter != null ? [widget.formatter!] : null,
      keyboardType: widget.keyboardType,
      decoration: InputDecoration(
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        alignLabelWithHint: true,
        hintText: widget.hintText,
        filled: true,
        fillColor: Theme.of(context).colorScheme.background.withOpacity(0.4),
        focusColor: Theme.of(context).colorScheme.background,
        enabledBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(CiRadius.r3),
            borderSide:
                BorderSide(width: 1, color: Theme.of(context).splashColor)),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(width: 1, color: Colors.grey.withOpacity(0.5)),
        ),
        border: const OutlineInputBorder(
          borderSide: BorderSide(width: 1),
          borderRadius: BorderRadius.all(CiRadius.r1),
        ),
        prefixText: widget.prefixText,
        label: EllipsisText(widget.label),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        suffixIcon: !widget.isPasswordField
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: IconButton(
                  icon: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  },
                ),
              ),
      ),
      validator: widget.validator,
      autofocus: widget.isFocused,
      obscureText: _obscureText,
    );
  }
}

class AppLogo extends StatelessWidget {
  final double height;
  final double width;

  const AppLogo({
    required this.height,
    required this.width,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      color: const Color(0xFF0055ab),
      child: Center(
        child: Image(
          image: const AssetImage('assets/img/commons.png'),
          height: height / 2,
        ),
      ),
    );
  }
}

class LoadingWidget extends StatelessWidget {
  final String loadingText;

  const LoadingWidget({super.key, required this.loadingText});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Center(
        child: IntrinsicWidth(
          child: IntrinsicHeight(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.inversePrimary,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.inverseSurface,
                    ),
                    const SizedBox(width: 25, height: 15),
                    Text(
                      loadingText,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.inverseSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomDivider extends StatelessWidget {
  const CustomDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1.0,
      thickness: 1,
      color: Theme.of(context).splashColor.withOpacity(0.3),
    );
  }
}

class CustomContainer extends StatelessWidget {
  final Widget child;
  final double? padding;

  const CustomContainer({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(padding ?? 0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          width: 1.0,
          color: Theme.of(context).disabledColor.withOpacity(0.15),
        ),
        borderRadius: const BorderRadius.all(CiRadius.r1),
      ),
      child: child,
    );
  }
}

class CustomIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final double? iconSize;
  final String? tooltipMessage;

  const CustomIconButton({
    Key? key,
    required this.onPressed,
    required this.icon,
    this.iconSize,
    this.tooltipMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        tooltip: tooltipMessage,
        iconSize: iconSize ?? Theme.of(context).iconTheme.size ?? 24.0,
        color: Theme.of(context).colorScheme.onBackground,
        style: ButtonStyle(backgroundColor:
            MaterialStateProperty.resolveWith<Color>(
                (Set<MaterialState> states) {
          return Colors.grey.withOpacity(0.20);
        })));
  }
}

class CustomInvertedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String text;

  const CustomInvertedButton({
    Key? key,
    required this.onPressed,
    required this.text,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.transparent, // Transparent background
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary, // Border color
          width: 2, // Border width
        ),
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class SmallProgressIndicator extends StatelessWidget {
  final double size;

  const SmallProgressIndicator({
    super.key,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: const CircularProgressIndicator(
        strokeWidth: 2,
      ),
    );
  }
}

class ResponsivePadding extends StatelessWidget {
  final Widget child;

  const ResponsivePadding({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (ResponsiveProvider.of(context)!.screenType == ScreenType.desktop) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: child,
      );
    } else if (ResponsiveProvider.of(context)!.screenType ==
        ScreenType.tablet) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: child,
      );
    } else {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      );
    }
  }
}

class ResponsiveVSpace extends StatelessWidget {
  const ResponsiveVSpace({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (ResponsiveProvider.of(context)!.screenType == ScreenType.desktop) {
      return const SizedBox(width: 16);
    } else if (ResponsiveProvider.of(context)!.screenType ==
        ScreenType.tablet) {
      return const SizedBox(width: 12);
    } else {
      return const SizedBox(width: 8);
    }
  }
}
