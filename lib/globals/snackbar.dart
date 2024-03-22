import 'package:flutter/material.dart';
import 'package:flutter_application_test/globals/global_styles.dart';

void showSuccess(context, String text) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      CustomSnackBar(
        icon: Icons.check_circle,
        backgroundColor: infoColor,
        text: text,
      ),
    );
}

void showError(context, String text) {
  ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(
      CustomSnackBar(
        icon: Icons.error,
        backgroundColor: warnColor,
        text: text,
      ),
    );
}

class CustomSnackBar extends SnackBar {
  CustomSnackBar({
    Key? key,
    required String text,
    required IconData icon,
    required Color backgroundColor,
  }) : super(
          key: key,
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 4),
          content: SizedBox(
            height: 150,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
}
