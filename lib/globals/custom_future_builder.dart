import 'package:flutter/material.dart';

class CustomFutureBuilder<T> extends StatelessWidget {
  const CustomFutureBuilder({
    super.key,
    required this.future,
    required this.onLoaded,
    required this.onError,
    this.onLoading,
  });

  final Future<T?> future;
  final Widget? onLoading;
  final Widget Function(T data) onLoaded;
  final Widget Function(Object?) onError;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T?>(
      future: future,
      builder: (context, futureData) {
        if (futureData.hasData) {
          return onLoaded(futureData.data as T);
        } else if (futureData.hasError) {
          return onError(futureData.error);
        } else {
          return onLoading ?? Container();
        }
      },
    );
  }
}
