import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_js_runner/main.dart';

void main() {
  testWidgets('renders JavaScript runner controls', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('dart_qjs JavaScript Runner'), findsOneWidget);
    expect(find.text('JavaScript'), findsOneWidget);
    expect(find.text('Result'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
  });
}
