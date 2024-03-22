import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test("", () {
    final Map<String, Object> values = <String, Object>{'counter': 1};
    SharedPreferences.setMockInitialValues(values);
  });
}
