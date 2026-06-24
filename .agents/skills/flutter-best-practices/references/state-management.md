# State Management Reference

Complete guide to state management patterns in Flutter.

## State Categories

### Ephemeral (Local) State
- Widget-specific state
- Tab selection, form input, button pressed state
- Solution: `StatefulWidget` + `setState()`

### App (Global) State
- User authentication, shopping cart, app preferences
- Shared across multiple screens
- Solution: Riverpod, BLoC, or Provider

## Riverpod Deep Dive

### Provider Types

```dart
// Provider - Simple immutable value
final nameProvider = Provider<String>((ref) => 'John');

// StateProvider - Mutable primitive state
final counterProvider = StateProvider<int>((ref) => 0);

// FutureProvider - Async operations
final userProvider = FutureProvider<User>((ref) async {
  return await ref.watch(apiProvider).getUser();
});

// StreamProvider - Real-time data
final messagesProvider = StreamProvider<List<Message>>((ref) {
  return ref.watch(chatRepositoryProvider).messageStream();
});

// StateNotifierProvider - Complex state with logic
final todosProvider = StateNotifierProvider<TodoNotifier, List<Todo>>((ref) {
  return TodoNotifier(ref.watch(todoRepositoryProvider));
});

// AsyncNotifierProvider - Async state with logic
@riverpod
class AuthController extends _$AuthController {
  @override
  Future<AuthState> build() async {
    return _checkAuthStatus();
  }
  
  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authRepositoryProvider).signIn(email, password);
      return _checkAuthStatus();
    });
  }
}
```

### Provider Modifiers

```dart
// autoDispose - Clean up when no longer used
final tempProvider = StateProvider.autoDispose<int>((ref) => 0);

// family - Parameterized providers
final userProvider = FutureProvider.family<User, String>((ref, userId) async {
  return await ref.watch(apiProvider).getUser(userId);
});

// keepAlive - Prevent auto-disposal
@Riverpod(keepAlive: true)
String apiKey(ApiKeyRef ref) => 'secret-key';
```

### Ref Patterns

```dart
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch - Rebuild when provider changes
    final value = ref.watch(provider);
    
    // Read - One-time access (callbacks, initState)
    final notifier = ref.read(provider.notifier);
    
    // Listen - React to changes without rebuilding
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.isAuthenticated) {
        context.go('/home');
      }
    });
    
    // Refresh - Force re-fetch
    final refresh = () => ref.refresh(userProvider);
    
    // Invalidate - Mark as stale, rebuild on next access
    final invalidate = () => ref.invalidate(userProvider);
    
    return Container();
  }
}
```

### Testing Riverpod

```dart
// Unit test
void main() {
  test('counter increments', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    
    final notifier = container.read(counterProvider.notifier);
    expect(container.read(counterProvider), 0);
    
    notifier.state++;
    expect(container.read(counterProvider), 1);
  });
  
  // With overrides
  test('with mocked repository', () {
    final container = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(MockApi()),
      ],
    );
    
    // Test with mock...
  });
}

// Widget test
void main() {
  testWidgets('displays user', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: UserProfile()),
      ),
    );
    
    expect(find.text('John'), findsOneWidget);
  });
}
```

## BLoC Pattern

### Core Concepts

**Event → BLoC → State**

```dart
// Events
abstract class CounterEvent {}
class CounterIncrementPressed extends CounterEvent {}
class CounterDecrementPressed extends CounterEvent {}

// State
class CounterState extends Equatable {
  final int count;
  final Status status;
  
  const CounterState({this.count = 0, this.status = Status.initial});
  
  CounterState copyWith({int? count, Status? status}) {
    return CounterState(
      count: count ?? this.count,
      status: status ?? this.status,
    );
  }
  
  @override
  List<Object?> get props => [count, status];
}

// BLoC
class CounterBloc extends Bloc<CounterEvent, CounterState> {
  CounterBloc() : super(const CounterState()) {
    on<CounterIncrementPressed>(_onIncrement);
    on<CounterDecrementPressed>(_onDecrement);
  }
  
  void _onIncrement(
    CounterIncrementPressed event,
    Emitter<CounterState> emit,
  ) {
    emit(state.copyWith(count: state.count + 1));
  }
  
  void _onDecrement(
    CounterDecrementPressed event,
    Emitter<CounterState> emit,
  ) {
    emit(state.copyWith(count: state.count - 1));
  }
}
```

### BLoC with Repository

```dart
class UserBloc extends Bloc<UserEvent, UserState> {
  final UserRepository _repository;
  
  UserBloc(this._repository) : super(UserInitial()) {
    on<LoadUser>(_onLoadUser);
    on<UpdateUser>(_onUpdateUser);
  }
  
  Future<void> _onLoadUser(
    LoadUser event,
    Emitter<UserState> emit,
  ) async {
    emit(UserLoading());
    try {
      final user = await _repository.getUser(event.id);
      emit(UserLoaded(user));
    } catch (e) {
      emit(UserError(e.toString()));
    }
  }
}

// Usage
BlocProvider(
  create: (context) => UserBloc(repository),
  child: UserView(),
)

// View
BlocBuilder<UserBloc, UserState>(
  builder: (context, state) {
    return switch (state) {
      UserLoading() => CircularProgressIndicator(),
      UserLoaded(:final user) => Text(user.name),
      UserError(:final message) => ErrorWidget(message),
      _ => Container(),
    };
  },
)
```

## GetX (Alternative)

Note: GetX combines state management, routing, and dependency injection. While convenient for small projects, it can lead to tightly coupled code.

```dart
// Controller
class UserController extends GetxController {
  final users = <User>[].obs;
  final isLoading = false.obs;
  
  void fetchUsers() async {
    isLoading.value = true;
    users.value = await ApiService.getUsers();
    isLoading.value = false;
  }
}

// Usage
final controller = Get.put(UserController());

Obx(() => controller.isLoading.value 
  ? CircularProgressIndicator()
  : ListView.builder(
      itemCount: controller.users.length,
      itemBuilder: (context, index) => 
        Text(controller.users[index].name),
    ),
);
```
