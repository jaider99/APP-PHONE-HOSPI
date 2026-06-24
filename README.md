# HospiDash - Hospitality Business Management

A multi-tenant SaaS mobile application for hospitality businesses (bars & restaurants) built with Flutter and Supabase.

## Features

- 📊 **Financial Dashboard** - Real-time KPIs and revenue analytics
- 💰 **Sales Management** - Track transactions and sales history
- 📄 **Document Processing** - Invoice OCR and receipt management
- 📦 **Order Management** - Track supplier orders and deliveries
- 🚚 **Provider Management** - Manage supplier relationships

## Architecture

### Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter 3+ |
| State Management | Riverpod |
| Navigation | go_router |
| Backend | Supabase (PostgreSQL + Auth + Storage) |
| Local Storage | shared_preferences, flutter_secure_storage |
| HTTP Client | Dio |
| Code Generation | freezed, json_serializable |

### Folder Structure

```
lib/
├── main.dart                    # App entry point
├── core/                        # Core infrastructure
│   ├── config/                  # Environment configuration
│   │   └── env_config.dart
│   ├── router/                  # Navigation setup
│   │   └── app_router.dart
│   ├── services/                # Core services
│   │   ├── api_service.dart
│   │   ├── auth_service.dart
│   │   ├── storage_service.dart
│   │   └── supabase_service.dart
│   ├── theme/                   # Design system
│   │   ├── app_colors.dart
│   │   ├── app_radius.dart
│   │   ├── app_spacing.dart
│   │   ├── app_theme.dart
│   │   └── app_typography.dart
│   └── utils/                   # Utilities
│       ├── app_logger.dart
│       ├── extensions.dart
│       └── result.dart
├── data/                        # Data layer
│   ├── models/                  # Domain models
│   │   └── user_profile.dart
│   └── repositories/            # Data repositories
│       └── base_repository.dart
├── features/                    # Feature modules
│   ├── auth/
│   │   └── presentation/screens/
│   ├── dashboard/
│   │   └── presentation/screens/
│   ├── documents/
│   │   └── presentation/screens/
│   ├── orders/
│   │   └── presentation/screens/
│   ├── providers/
│   │   └── presentation/screens/
│   └── sales/
│       └── presentation/screens/
└── shared/                      # Shared components
    └── widgets/
        ├── empty_state.dart
        ├── main_scaffold.dart
        └── screen_header.dart
```

### Layer Responsibilities

| Layer | Purpose |
|-------|---------|
| **Presentation** | Widgets, screens, UI logic |
| **Domain** | Business logic, use cases, entities |
| **Data** | Repositories, data sources, models |

## Getting Started

### Prerequisites

- Flutter SDK 3.2+
- Dart SDK 3.2+
- Supabase account
- iOS: Xcode 15+ (for iOS development)
- Android: Android Studio with SDK 34+

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd hospi_dash
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Generate code**
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Configure environment**

  Copy the example file and fill in your local Supabase project values:
  ```bash
  copy env\example.json env\dev.json
  ```

  `env/dev.json` is ignored by git and must not contain service-role keys.

  Run with the local define file:
  ```bash
  flutter run --dart-define-from-file=env/dev.json
  ```

  You can also pass values directly for quick debugging:
   ```bash
   flutter run \
     --dart-define=APP_ENV=development \
     --dart-define=SUPABASE_URL=your-project-url \
     --dart-define=SUPABASE_ANON_KEY=your-anon-key
   ```

5. **Run the app**
   ```bash
  flutter run --dart-define-from-file=env/dev.json
   ```

## Local development setup

Create `env/dev.json` from `env/example.json`:

```json
{
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_ANON_KEY": "your-anon-key"
}
```

Run:

```bash
flutter run --dart-define-from-file=env/dev.json
```

Required Flutter dart defines:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Optional if Edge Functions are used:

OpenRouter keys are configured in Supabase secrets, not in Flutter.

For one-off debugging only, you can pass client-safe values directly:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

Do not commit `env/dev.json`, put a service-role key in Flutter, or put OpenRouter API keys in Flutter.

### Supabase Setup

1. Create a new Supabase project
2. Enable Row Level Security (RLS) on all tables
3. Create the following tables with `company_id` column for multi-tenancy:

```sql
-- Enable RLS
ALTER TABLE your_table ENABLE ROW LEVEL SECURITY;

-- Create policy for multi-tenant isolation
CREATE POLICY "Users can only access their company data"
ON your_table
FOR ALL
USING (company_id = auth.jwt() ->> 'company_id');
```

## Development

### Code Generation

After modifying freezed/json_serializable models:
```bash
dart run build_runner build --delete-conflicting-outputs
```

For continuous generation during development:
```bash
dart run build_runner watch --delete-conflicting-outputs
```

### Running Tests

```bash
# Unit tests
flutter test

# Widget tests
flutter test test/widget_test.dart

# Integration tests
flutter test integration_test/

# Test with coverage
flutter test --coverage
```

### Building for Production

```bash
# Android
flutter build appbundle --release --obfuscate --split-debug-info=symbols/ \
  --dart-define=APP_ENV=production \
  --dart-define=SUPABASE_URL=https://your-prod-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-prod-anon-key

# iOS
flutter build ios --release \
  --dart-define=APP_ENV=production \
  --dart-define=SUPABASE_URL=https://your-prod-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-prod-anon-key

# Web
flutter build web --release \
  --dart-define=APP_ENV=production \
  --dart-define=SUPABASE_URL=https://your-prod-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-prod-anon-key
```

## Architecture Patterns

### State Management with Riverpod

```dart
// Define a provider
final userProvider = FutureProvider<User>((ref) async {
  final authService = ref.watch(authServiceProvider);
  return authService.getCurrentUserProfile();
});

// Consume in widget
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userProvider);
    
    return userAsync.when(
      data: (user) => Text(user.name),
      loading: () => CircularProgressIndicator(),
      error: (e, _) => Text('Error: $e'),
    );
  }
}
```

### Multi-Tenant Data Access

All repositories extend `BaseRepository` which automatically filters by `company_id`:

```dart
class SalesRepository extends BaseRepository {
  Future<Result<List<Sale>>> getAllSales() async {
    final result = await getAll(table: 'sales');
    return result.mapSuccess(
      (data) => data.map((e) => Sale.fromJson(e)).toList(),
    );
  }
}
```

### Error Handling with Result Type

```dart
final result = await repository.createSale(sale);

result.when(
  success: (sale) => context.showSuccessSnackBar('Sale created'),
  failure: (error) => context.showErrorSnackBar(error.toString()),
);
```

## Best Practices

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Files | snake_case | `user_profile.dart` |
| Classes | PascalCase | `UserProfile` |
| Variables | camelCase | `userName` |
| Constants | camelCase | `maxRetries` |
| Providers | camelCase + Provider | `userProvider` |

### Widget Rules

1. **Use `const` constructors** wherever possible
2. **Never build widgets inside `build()`** - extract to separate classes
3. **Use `ConsumerWidget`** for state management, not `StatefulWidget`
4. **Follow single responsibility** - one widget, one purpose
5. **Use keys** for lists and interactive widgets

### File Organization

1. **One class per file** (except for related small classes)
2. **Feature-first organization** - group by feature, not by type
3. **Barrel files** for clean imports (`core.dart`)
4. **Keep files under 300 lines** - split if larger

### Performance

1. Use `ListView.builder` for lists > 10 items
2. Wrap animations in `RepaintBoundary`
3. Use `compute()` for heavy JSON parsing
4. Check `mounted` before async `setState`
5. Dispose controllers in `dispose()`

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `APP_ENV` | Runtime environment: `development`, `staging`, or `production` | Required for release builds |
| `SUPABASE_URL` | Supabase project URL | Yes |
| `SUPABASE_ANON_KEY` | Supabase anonymous key | Yes |

| Environment | Expected values |
|-------------|-----------------|
| Development | `APP_ENV=development`, dev Supabase URL, dev anon key |
| Staging | `APP_ENV=staging`, staging Supabase URL, staging anon key |
| Production | `APP_ENV=production`, production Supabase URL, production anon key |

Release builds fail startup unless `APP_ENV` is explicitly set to `staging` or `production`. Staging and production Supabase URLs must use HTTPS.

For local development, create `env/dev.json` from `env/example.json` and run:

```bash
flutter run --dart-define-from-file=env/dev.json
```

Do not add OpenRouter keys to Flutter environment files. OpenRouter access belongs in Supabase Edge Function secrets.

**Never commit real environment files or secrets to version control.**

## Contributing

1. Create a feature branch
2. Follow the coding standards
3. Write tests for new features
4. Run `flutter analyze` before committing
5. Create a pull request

## License

Proprietary - All rights reserved.
