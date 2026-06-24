# Performance Optimization Reference

Advanced techniques for optimizing Flutter application performance.

## Rendering Pipeline

Flutter's rendering happens in 4 phases:
1. **Animate**: Process animations
2. **Build**: Compose widget tree
3. **Layout**: Calculate positions (single pass down and up)
4. **Paint**: Rasterize to screen

Target: 16.67ms for 60 FPS, 8.33ms for 120 FPS

## Widget Optimization

### Const Constructors

```dart
// Good - Compile-time constant, no rebuild needed
const Text('Hello')
const SizedBox(width: 10)
const Icon(Icons.favorite)

// Good - Static parts use const
Column(
  children: const [
    Text('Title'),
    SizedBox(height: 10),
    Text('Body'),
  ],
)

// Good - Extract widgets to make them const
class UserProfile extends StatelessWidget {
  const UserProfile({required this.user});
  final User user;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ProfileHeader(), // Always const
        ProfileInfo(user: user), // Rebuilds when user changes
        const ProfileActions(), // Always const
      ],
    );
  }
}
```

### List Optimization

```dart
// Good - Lazy loading for large lists
ListView.builder(
  itemCount: 10000,
  itemBuilder: (context, index) => ListTile(
    title: Text('Item $index'),
  ),
)

// Good - With separator
ListView.separated(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemWidget(items[index]),
  separatorBuilder: (context, index) => const Divider(),
)

// Good - Custom scroll view with slivers
CustomScrollView(
  slivers: [
    SliverAppBar(
      expandedHeight: 200,
      flexibleSpace: FlexibleSpaceBar(...),
    ),
    SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => ItemWidget(items[index]),
        childCount: items.length,
      ),
    ),
  ],
)
```

### Image Optimization

```dart
// Use CachedNetworkImage for remote images
CachedNetworkImage(
  imageUrl: url,
  width: 200,
  height: 200,
  fit: BoxFit.cover,
  placeholder: (context, url) => CircularProgressIndicator(),
  errorWidget: (context, url, error) => Icon(Icons.error),
  memCacheWidth: 400, // Limit memory cache size
)

// Pre-resize local images
ResizeImage(
  FileImage(File(path)),
  width: 400,
  height: 400,
)

// Fade in images
FadeInImage(
  placeholder: AssetImage('assets/placeholder.png'),
  image: NetworkImage(url),
  fit: BoxFit.cover,
)
```

### Repaint Boundaries

```dart
// Wrap frequently repainting widgets
RepaintBoundary(
  child: AnimatedWidget(...),
)

// CustomPaint with optimization
CustomPaint(
  painter: MyPainter(),
  isComplex: true,        // Hint for raster cache
  willChange: false,      // Won't change frequently
)

// Isolate expensive painting
RepaintBoundary(
  child: CustomPaint(
    size: Size.infinite,
    painter: ExpensiveChartPainter(data),
  ),
)
```

## State Management Performance

### Selective Rebuilds

```dart
// Bad - Entire screen rebuilds when count changes
class BadExample extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);
    return Scaffold(
      body: Column(
        children: [
          Header(), // Rebuilds unnecessarily
          Text('$count'), // Only this needs rebuild
          Footer(), // Rebuilds unnecessarily
        ],
      ),
    );
  }
}

// Good - Only counter rebuilds
class GoodExample extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Header(),
          CounterDisplay(), // Only this rebuilds
          Footer(),
        ],
      ),
    );
  }
}

class CounterDisplay extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);
    return Text('$count');
  }
}
```

### ValueNotifier for Local State

```dart
class EfficientCounter extends StatefulWidget {
  @override
  _EfficientCounterState createState() => _EfficientCounterState();
}

class _EfficientCounterState extends State<EfficientCounter> {
  final _counter = ValueNotifier<int>(0);
  
  @override
  void dispose() {
    _counter.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Only rebuilds when value changes
        ValueListenableBuilder<int>(
          valueListenable: _counter,
          builder: (context, value, child) {
            return Text('$value');
          },
        ),
        ElevatedButton(
          onPressed: () => _counter.value++,
          child: Text('Increment'),
        ),
      ],
    );
  }
}
```

## Memory Management

### Disposal Patterns

```dart
class _MyWidgetState extends State<MyWidget> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _animationController = AnimationController(...);
  StreamSubscription? _subscription;
  
  @override
  void initState() {
    super.initState();
    _subscription = stream.listen((data) {
      // Always check mounted before setState
      if (mounted) {
        setState(() => _data = data);
      }
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    _subscription?.cancel();
    super.dispose();
  }
}
```

### Image Cache Control

```dart
// Limit cache size
PaintingBinding.instance.imageCache
  ..maximumSize = 100
  ..maximumSizeBytes = 50 * 1024 * 1024;

// Clear cache when memory warning
class MemoryManager {
  static void handleMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
```

## Isolate Usage

### Heavy Computation

```dart
// Parse JSON off main thread
Future<List<Model>> parseModels(String jsonString) async {
  return compute(_parseModels, jsonString);
}

List<Model> _parseModels(String jsonString) {
  final decoded = json.decode(jsonString) as List;
  return decoded.map((e) => Model.fromJson(e)).toList();
}

// Image processing
Future<Uint8List> processImage(Uint8List imageData) async {
  return compute(_processImage, imageData);
}

Uint8List _processImage(Uint8List data) {
  // Heavy image processing
  return img.encodeJpg(processedImage);
}
```

### Communication Between Isolates

```dart
// Using ports for bidirectional communication
Future<void> spawnWorker() async {
  final receivePort = ReceivePort();
  
  await Isolate.spawn(
    _workerIsolate,
    receivePort.sendPort,
  );
  
  final sendPort = await receivePort.first as SendPort;
  
  final responsePort = ReceivePort();
  sendPort.send(['task', responsePort.sendPort]);
  
  final result = await responsePort.first;
  print('Result: $result');
}

void _workerIsolate(SendPort mainSendPort) {
  final port = ReceivePort();
  mainSendPort.send(port.sendPort);
  
  port.listen((message) {
    final task = message[0] as String;
    final replyPort = message[1] as SendPort;
    
    final result = doWork(task);
    replyPort.send(result);
  });
}
```

## DevTools Profiling

### Enable Profiling

```dart
void main() {
  // Visualize widget rebuilds
  debugRepaintRainbowEnabled = true;
  
  // Show paint bounds
  debugPaintSizeEnabled = true;
  
  // Show baselines
  debugPaintBaselinesEnabled = true;
  
  // Show layer borders
  debugPaintLayerBordersEnabled = true;
  
  runApp(MyApp());
}
```

### Performance Overlay

```dart
MaterialApp(
  showPerformanceOverlay: true, // Shows FPS in top-right
  home: MyHomePage(),
)
```

### Common Performance Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Excessive rebuilds | High widget build counts | Use `const`, split widgets |
| Layout thrashing | Slow layout phase | Cache constraints, use `LayoutBuilder` |
| Shader compilation jank | Frame drops on first run | Warm up shaders, use Impeller |
| Memory leaks | Increasing memory usage | Dispose controllers, limit cache |
| Large build methods | Slow build phase | Extract widgets |

## Build Optimization

### Compilation Modes

| Mode | Use | Performance |
|------|-----|-------------|
| Debug (JIT) | Development | Slow, hot reload |
| Profile | Performance testing | Optimized, some debug |
| Release (AOT) | Production | Fastest, optimized |

### Tree Shaking

```dart
// Remove debug code in release
if (kDebugMode) {
  print('Debug info: $data');
}

// Conditional imports
import 'src/stub.dart'
    if (dart.library.io) 'src/io.dart'
    if (dart.library.html) 'src/web.dart';
```

### Code Splitting (Web)

```dart
// Deferred loading
import 'admin_panel.dart' deferred as admin;

Future<void> showAdminPanel() async {
  await admin.loadLibrary();
  runApp(admin.AdminPanel());
}
```

## Platform-Specific Optimizations

### Android

```gradle
// android/app/build.gradle
android {
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android.txt')
        }
    }
}
```

### iOS

```bash
# Build with optimizations
flutter build ios --release

# Enable Impeller (iOS 16+)
flutter build ios --dart-define=flutter.bubble.enableImpeller=true
```

### Web

```bash
# CanvasKit renderer (better performance)
flutter build web --web-renderer=canvaskit

# HTML renderer (smaller bundle)
flutter build web --web-renderer=html

# WebAssembly (experimental)
flutter build web --wasm
```
