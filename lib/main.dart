import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home.dart';
import 'screens/login.dart';
import 'state.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  appState = AppState(prefs);
  runApp(const OutletApp());
  appState.init();
}

class OutletApp extends StatelessWidget {
  const OutletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        const seed = Color(0xFF4F46E5);
        return MaterialApp(
          title: 'Salon OS',
          debugShowCheckedModeBanner: false,
          themeMode: appState.themeMode,
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true),
          darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark), useMaterial3: true),
          home: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: appState.booting
                ? const Scaffold(key: ValueKey('boot'), body: Loading())
                : appState.me == null
                    ? const LoginScreen(key: ValueKey('login'))
                    : const HomeScreen(key: ValueKey('home')),
          ),
        );
      },
    );
  }
}
