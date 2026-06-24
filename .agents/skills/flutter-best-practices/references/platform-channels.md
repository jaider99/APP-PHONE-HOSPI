# Platform Channels Reference

Guide for integrating native platform functionality with Flutter.

## Overview

Platform channels enable communication between Dart and platform-specific code (Kotlin/Java for Android, Swift/Objective-C for iOS).

**Communication Types:**
- **MethodChannel**: Invoke methods with arguments and return values
- **EventChannel**: Stream data from platform to Flutter
- **BasicMessageChannel**: Send/receive raw messages

## MethodChannel

### Flutter Side

```dart
class BatteryService {
  static const MethodChannel _channel = 
      MethodChannel('com.example.app/battery');
  
  // Get battery level
  Future<int> getBatteryLevel() async {
    try {
      final level = await _channel.invokeMethod<int>('getBatteryLevel');
      return level ?? -1;
    } on PlatformException catch (e) {
      print('Failed to get battery level: ${e.message}');
      return -1;
    } on MissingPluginException {
      print('Method not implemented on platform');
      return -1;
    }
  }
  
  // Pass arguments
  Future<void> showNotification(String title, String body) async {
    await _channel.invokeMethod('showNotification', {
      'title': title,
      'body': body,
      'priority': 'high',
    });
  }
}
```

### Android (Kotlin)

```kotlin
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.app/battery"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBatteryLevel" -> {
                    val level = getBatteryLevel()
                    result.success(level)
                }
                "showNotification" -> {
                    val title = call.argument<String>("title")
                    val body = call.argument<String>("body")
                    showNotification(title, body)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun getBatteryLevel(): Int {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }
}
```

### iOS (Swift)

```swift
import Flutter
import UIKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController
        let batteryChannel = FlutterMethodChannel(
            name: "com.example.app/battery",
            binaryMessenger: controller.binaryMessenger
        )
        
        batteryChannel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "getBatteryLevel":
                let level = self.getBatteryLevel()
                result(level)
            case "showNotification":
                guard let args = call.arguments as? [String: Any],
                      let title = args["title"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENT", 
                                       message: nil, details: nil))
                    return
                }
                self.showNotification(title: title)
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    private func getBatteryLevel() -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Int(UIDevice.current.batteryLevel * 100)
    }
}
```

## EventChannel

### Flutter Side

```dart
class SensorService {
  static const EventChannel _channel = 
      EventChannel('com.example.app/sensors');
  
  Stream<AccelerometerEvent> get accelerometerEvents {
    return _channel.receiveBroadcastStream().map((event) {
      return AccelerometerEvent(
        x: event['x'] as double,
        y: event['y'] as double,
        z: event['z'] as double,
      );
    });
  }
}

// Usage
class SensorWidget extends StatefulWidget {
  @override
  _SensorWidgetState createState() => _SensorWidgetState();
}

class _SensorWidgetState extends State<SensorWidget> {
  StreamSubscription? _subscription;
  AccelerometerEvent? _event;
  
  @override
  void initState() {
    super.initState();
    _subscription = SensorService().accelerometerEvents.listen((event) {
      setState(() => _event = event);
    });
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Text('X: ${_event?.x ?? 0}');
  }
}
```

### Android (Kotlin)

```kotlin
class MainActivity : FlutterActivity() {
    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var eventSink: EventChannel.EventSink? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.app/sensors"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                sensorManager?.registerListener(
                    sensorListener,
                    accelerometer,
                    SensorManager.SENSOR_DELAY_NORMAL
                )
            }
            
            override fun onCancel(arguments: Any?) {
                sensorManager?.unregisterListener(sensorListener)
                eventSink = null
            }
        })
    }
    
    private val sensorListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent?) {
            event?.let {
                val data = mapOf(
                    "x" to it.values[0],
                    "y" to it.values[1],
                    "z" to it.values[2]
                )
                eventSink?.success(data)
            }
        }
        
        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
    }
}
```

## Federated Plugins

For reusable platform plugins, use the federated plugin pattern:

```
my_plugin/
├── my_plugin/              # App-facing package
│   └── lib/
│       └── my_plugin.dart
├── my_plugin_platform_interface/  # Platform interface
│   └── lib/
│       └── my_plugin_platform.dart
├── my_plugin_android/      # Android implementation
├── my_plugin_ios/          # iOS implementation
└── my_plugin_web/          # Web implementation
```

### Platform Interface

```dart
abstract class MyPluginPlatform extends PlatformInterface {
  MyPluginPlatform() : super(token: _token);
  
  static final Object _token = Object();
  static MyPluginPlatform _instance = MethodChannelMyPlugin();
  
  static MyPluginPlatform get instance => _instance;
  
  static set instance(MyPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }
  
  Future<String> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }
}
```

### Implementation

```dart
class MethodChannelMyPlugin extends MyPluginPlatform {
  final methodChannel = const MethodChannel('my_plugin');
  
  @override
  Future<String> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version ?? 'Unknown';
  }
}
```

## Pigeon (Type-Safe Channels)

Use pigeon for type-safe platform channel communication:

```yaml
# pubspec.yaml
dev_dependencies:
  pigeon: ^latest
```

```dart
// Define API in pigeon file (messages.dart)
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  kotlinOut: 'android/src/main/kotlin/Messages.g.kt',
  swiftOut: 'ios/Classes/Messages.g.swift',
))

class BatteryInfo {
  int? level;
  String? status;
}

@HostApi()
abstract class BatteryApi {
  BatteryInfo getBatteryInfo();
}
```

```bash
# Generate code
dart run pigeon --input messages.dart
```

## Best Practices

### Error Handling

```dart
// Always handle PlatformException
try {
  final result = await channel.invokeMethod('riskyOperation');
} on PlatformException catch (e) {
  if (e.code == 'PERMISSION_DENIED') {
    // Handle permission denied
  } else if (e.code == 'NOT_AVAILABLE') {
    // Handle feature not available
  }
} on MissingPluginException {
  // Platform implementation not found
}
```

### Threading

```kotlin
// Android - Run on background thread for heavy operations
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "heavyOperation" -> {
                GlobalScope.launch(Dispatchers.IO) {
                    val data = doHeavyWork()
                    withContext(Dispatchers.Main) {
                        result.success(data)
                    }
                }
            }
        }
    }
```

### Testing

```dart
// Mock platform channels in tests
const MethodChannel channel = MethodChannel('com.example.app/battery');

setUp(() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getBatteryLevel') {
      return 42;
    }
    return null;
  });
});

tearDown(() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null);
});
```
