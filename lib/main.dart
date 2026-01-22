import 'dart:io'; // Import for Platform check
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'package:awear/features/dashboard/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // --- FIX FOR WINDOWS THREAD ERROR ---
  // Disable persistence on Windows to prevent "Non-Platform Thread" crashes
  if (!kIsWeb && Platform.isWindows) {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      // print(
      //   "WINDOWS: Firestore persistence disabled to prevent threading issues.",
      // );
    } catch (e) {
      // print("WINDOWS WARNING: Could not disable persistence: $e");
    }
  }
  // ------------------------------------

  await clearFirestoreCache();

  runApp(const ProviderScope(child: MyApp()));
}

Future clearFirestoreCache() async {
  try {
    await FirebaseFirestore.instance.clearPersistence();
    //print("Firestore cache cleared successfully.");
  } catch (e) {
    // print("Failed to clear Firestore cache: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AWear',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
      //home: const AppShell(),
    );
  }
}
