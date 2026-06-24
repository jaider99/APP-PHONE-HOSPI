import 'package:flutter_test/flutter_test.dart';
import 'package:hospi_dash/core/bootstrap/bootstrap_error_app.dart';

void main() {
  testWidgets('BootstrapErrorApp shows startup configuration failures', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const BootstrapErrorApp(
        error: 'SUPABASE_URL is required',
      ),
    );

    expect(find.text('Startup configuration error'), findsOneWidget);
    expect(find.text('SUPABASE_URL is required'), findsOneWidget);
  });
}
