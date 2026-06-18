# UI/UX Guidelines: Athlete's POV (APOV)

This document maps user interface design principles, styling configurations, and Flutter widget structures across the APOV platform.

---

## 1. Core UX/UI Principles

- **Mobile-First Responsiveness**: The User App and Partner App are accessed primarily on mobile devices. Interfaces are built with single-column layouts, sticky action bars, and swipeable tabs.
- **Desktop Command Console**: The Admin Portal uses a multi-pane desktop navigation layout designed for administrative workflows.
- **State Indicators**: Interactive slot cells must clearly communicate state transitions:
  - **Available**: Colored border/background indicating action capability.
  - **Booked**: Solid color block showing reservation completion.
  - **Blocked**: Gray-striped background patterns indicating unavailability.
- **Micro-interactions**: Subtle hover states, loading skeletons, and interactive indicators must be used across all applications.

---

## 2. Design Tokens & Theme Palettes

The applications utilize Vanilla CSS custom properties declared inside root files. Generics (such as plain red, blue, or green) are avoided in favor of modern, harmonized color schemes.

### Web/CSS Theme Configurations
```css
:root {
  /* Color Palette - Vibrant Dark Mode */
  --bg-primary: #0b0f19;
  --bg-secondary: #151d30;
  --text-primary: #f3f4f6;
  --text-secondary: #9ca3af;
  
  /* Accent Colors */
  --accent-orange: #f59e0b;    /* User App Branding */
  --accent-pink: #ec4899;      /* Partner App Branding */
  --accent-blue: #3b82f6;      /* Admin Portal Branding */
  
  /* Status Colors */
  --status-success: #10b981;
  --status-warning: #f59e0b;
  --status-danger: #ef4444;
  --status-blocked: #4b5563;   /* Gray striped color code */
}
```

### Flutter/Dart Theme Configurations
```dart
class ApovTheme {
  static const Color bgPrimary = Color(0xFF0B0F19);
  static const Color bgSecondary = Color(0xFF151D30);
  static const Color textPrimary = Color(0xFFF3F4F6);
  static const Color textSecondary = Color(0xFF9CA3AF);
  
  static const Color accentOrange = Color(0xFFF59E0B);
  static const Color accentPink = Color(0xFFEC4899);
  static const Color accentBlue = Color(0xFF3B82F6);
  
  static const Color statusSuccess = Color(0xFF10B981);
  static const Color statusWarning = Color(0xFFF59E0B);
  static const Color statusDanger = Color(0xFFEF4444);
  static const Color statusBlocked = Color(0xFF4B5563);
}
```

---

## 3. Critical Flutter Widget & Rebuild Rules

To prevent rendering lag and infinite API request loops inside your Flutter apps, observe these constraints:

> [!IMPORTANT]
> **Avoid Rebuild Loops**: Never initiate API fetches directly inside the widget `build(BuildContext context)` method. Doing so triggers a new state refresh which invokes another rebuild, locking the application in an infinite loop. Always load data using state provider lifecycle hooks (e.g. `ref.read` during initialization or via an asynchronous `FutureProvider`).

### Riverpod State-Driven Widget Structure:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 1. Declare provider for slot state
final slotsProvider = FutureProvider.family<List<dynamic>, String>((ref, date) async {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getSlotsForDate(date);
});

// 2. Renders grid UI
class SlotGrid extends ConsumerWidget {
  final List<dynamic> slots;
  const SlotGrid({super.key, required this.slots});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        return SlotCell(slot: slot);
      },
    );
  }
}
```

---

## 4. Dark Mode Switch Implementation (Flutter)

Theme toggles are managed using Riverpod StateNotifier states and persisted via `shared_preferences`.

1. **State Provider**: Manages active `ThemeMode` (`ThemeMode.dark` | `ThemeMode.light`).
2. **Session Persistence**: Saves choices to device storage upon change.
3. **Execution**:
```dart
class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  void _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('is_dark_theme') ?? true;
    state = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (state == ThemeMode.dark) {
      state = ThemeMode.light;
      await prefs.setBool('is_dark_theme', false);
    } else {
      state = ThemeMode.dark;
      await prefs.setBool('is_dark_theme', true);
    }
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
```
4. **App Initialization Configuration**:
```dart
class ApovApp extends ConsumerWidget {
  const ApovApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    return MaterialApp(
      title: "Athlete's POV",
      themeMode: themeMode,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: const SplashScreen(),
    );
  }
}
```
