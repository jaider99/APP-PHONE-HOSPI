# Testing Reference

Comprehensive testing patterns for Flutter applications.

## Test Organization

```
test/
├── unit/                    # Business logic tests
│   ├── models/
│   ├── repositories/
│   └── usecases/
├── widget/                  # UI component tests
│   ├── screens/
│   └── components/
├── integration/             # Full flow tests
│   └── flows/
└── golden/                  # Visual regression
    └── screens/
```

## Unit Testing

### Models

```dart
void main() {
  group('User Model', () {
    test('can instantiate from JSON', () {
      final json = {
        'id': '1',
        'name': 'John',
        'email': 'john@example.com',
      };
      
      final user = User.fromJson(json);
      
      expect(user.id, '1');
      expect(user.name, 'John');
      expect(user.email, 'john@example.com');
    });
    
    test('can convert to JSON', () {
      final user = User(id: '1', name: 'John', email: 'john@example.com');
      
      final json = user.toJson();
      
      expect(json['id'], '1');
      expect(json['name'], 'John');
    });
    
    test('equality works correctly', () {
      final user1 = User(id: '1', name: 'John');
      final user2 = User(id: '1', name: 'John');
      final user3 = User(id: '2', name: 'Jane');
      
      expect(user1, equals(user2));
      expect(user1, isNot(equals(user3)));
    });
  });
}
```

### Repository with Mocking

```dart
@GenerateNiceMocks([MockSpec<HttpClient>()])
import 'user_repository_test.mocks.dart';

void main() {
  late UserRepository repository;
  late MockHttpClient mockClient;
  
  setUp(() {
    mockClient = MockHttpClient();
    repository = UserRepository(client: mockClient);
  });
  
  group('getUser', () {
    test('returns user on successful response', () async {
      when(mockClient.get('/users/1')).thenAnswer(
        (_) async => Response(
          data: {'id': '1', 'name': 'John'},
          statusCode: 200,
        ),
      );
      
      final user = await repository.getUser('1');
      
      expect(user.name, 'John');
      verify(mockClient.get('/users/1')).called(1);
    });
    
    test('throws exception on error response', () async {
      when(mockClient.get(any)).thenAnswer(
        (_) async => Response(statusCode: 404),
      );
      
      expect(
        () => repository.getUser('1'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
```

### BLoC Testing

```dart
import 'package:bloc_test/bloc_test.dart';

void main() {
  group('CounterBloc', () {
    blocTest<CounterBloc, CounterState>(
      'emits [1] when CounterIncrementPressed is added',
      build: () => CounterBloc(),
      act: (bloc) => bloc.add(CounterIncrementPressed()),
      expect: () => [const CounterState(count: 1)],
    );
    
    blocTest<CounterBloc, CounterState>(
      'emits [1, 0] when increment then decrement',
      build: () => CounterBloc(),
      act: (bloc) => bloc
        ..add(CounterIncrementPressed())
        ..add(CounterDecrementPressed()),
      expect: () => [
        const CounterState(count: 1),
        const CounterState(count: 0),
      ],
    );
  });
}
```

## Widget Testing

### Basic Widget Test

```dart
void main() {
  testWidgets('Counter increments when button tapped', 
    (WidgetTester tester) async {
    // Build the widget
    await tester.pumpWidget(
      MaterialApp(
        home: CounterScreen(),
      ),
    );
    
    // Verify initial state
    expect(find.text('0'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    
    // Tap the button
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    
    // Verify new state
    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}
```

### Testing Forms

```dart
testWidgets('form validation works', (tester) async {
  await tester.pumpWidget(MaterialApp(home: LoginScreen()));
  
  // Find form fields
  final emailField = find.byKey(Key('email_field'));
  final passwordField = find.byKey(Key('password_field'));
  final submitButton = find.byType(ElevatedButton);
  
  // Enter invalid data
  await tester.enterText(emailField, 'invalid-email');
  await tester.enterText(passwordField, '123');
  await tester.tap(submitButton);
  await tester.pumpAndSettle();
  
  // Check validation messages
  expect(find.text('Invalid email'), findsOneWidget);
  expect(find.text('Password too short'), findsOneWidget);
  
  // Enter valid data
  await tester.enterText(emailField, 'valid@example.com');
  await tester.enterText(passwordField, 'password123');
  await tester.tap(submitButton);
  await tester.pumpAndSettle();
  
  // Verify navigation or success state
  expect(find.text('Welcome'), findsOneWidget);
});
```

### Testing Lists

```dart
testWidgets('displays list of items', (tester) async {
  final items = List.generate(100, (i) => 'Item $i');
  
  await tester.pumpWidget(
    MaterialApp(
      home: ItemList(items: items),
    ),
  );
  
  // Verify first item visible
  expect(find.text('Item 0'), findsOneWidget);
  
  // Scroll down
  await tester.fling(find.byType(ListView), Offset(0, -300), 3000);
  await tester.pumpAndSettle();
  
  // Verify scrolled items
  expect(find.text('Item 0'), findsNothing);
  expect(find.text('Item 10'), findsOneWidget);
  
  // Scroll to end
  await tester.scrollUntilVisible(
    find.text('Item 99'),
    500,
    scrollable: find.byType(ListView),
  );
  
  expect(find.text('Item 99'), findsOneWidget);
});
```

### Testing with Riverpod

```dart
testWidgets('displays user from provider', (tester) async {
  final container = ProviderContainer(
    overrides: [
      userProvider.overrideWith((ref) => User(id: '1', name: 'Test')),
    ],
  );
  
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: UserProfile()),
    ),
  );
  
  expect(find.text('Test'), findsOneWidget);
});
```

## Golden Tests

```dart
testGoldens('User profile renders correctly', (tester) async {
  final builder = GoldenBuilder.grid(
    columns: 2,
    widthToHeightRatio: 1,
  )
    ..addScenario('Default', UserProfile(user: mockUser))
    ..addScenario('With long name', UserProfile(user: longNameUser))
    ..addScenario('Dark mode', Theme(
      data: darkTheme,
      child: UserProfile(user: mockUser),
    ))
    ..addScenario('Loading', UserProfileLoading());
  
  await tester.pumpWidgetBuilder(builder.build());
  
  await screenMatchesGolden(tester, 'user_profile');
});

// Multi-screen golden
testGoldens('responsive layouts', (tester) async {
  final deviceBuilder = DeviceBuilder()
    ..overrideDevicesForAllScenarios(devices: [
      Device.phone,
      Device.iphone11,
      Device.tabletPortrait,
      Device.tabletLandscape,
    ])
    ..addScenario(widget: HomeScreen());
  
  await tester.pumpDeviceBuilder(deviceBuilder);
  await screenMatchesGolden(tester, 'home_responsive');
});
```

## Integration Testing

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('End-to-end test', () {
    testWidgets('complete purchase flow', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Login
      await tester.enterText(
        find.byKey(Key('email')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(Key('password')),
        'password',
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      
      // Navigate to products
      await tester.tap(find.text('Products'));
      await tester.pumpAndSettle();
      
      // Add item to cart
      await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
      await tester.pumpAndSettle();
      
      // Go to cart
      await tester.tap(find.byIcon(Icons.shopping_cart));
      await tester.pumpAndSettle();
      
      // Checkout
      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();
      
      // Verify success
      expect(find.text('Order confirmed'), findsOneWidget);
    });
  });
}
```

## Test Utilities

```dart
// Custom matchers
Matcher hasText(String text) => finds.widgetWithText(Widget, text);

Matcher hasIcon(IconData icon) => finds.byIcon(icon);

Matcher hasButton(String text) => 
  finds.widgetWithText(ElevatedButton, text);

// Pump helpers
extension PumpExtensions on WidgetTester {
  Future<void> pumpApp(Widget widget) async {
    await pumpWidget(
      MaterialApp(
        home: widget,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }
}

// Mock helpers
class MockNavigatorObserver extends Mock implements NavigatorObserver {}

// Test data
final mockUser = User(
  id: '1',
  name: 'John Doe',
  email: 'john@example.com',
);

final mockUsers = [
  User(id: '1', name: 'User 1'),
  User(id: '2', name: 'User 2'),
];
```

## Running Tests

```bash
# All tests
flutter test

# Specific file
flutter test test/unit/user_test.dart

# With coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html

# Integration tests
flutter test integration_test/app_test.dart

# Update goldens
flutter test --update-goldens --tags=golden

# Watch mode
flutter test --watch
```
