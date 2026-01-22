import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/screens/student_login_screen.dart';
import '../../student/screens/student_dashboard_screen.dart';
import '../../devices/providers/device_discovery_provider.dart';
import 'app_shell.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();
    _initApp();
  }

  Future<void> _initApp() async {
    // 1. Minimum timer for logo animation
    final tasks = <Future>[Future.delayed(const Duration(seconds: 3))];

    // 2. ONLY wait for Hardware Scanner if we are on Desktop
    // Mobile does NOT need to scan for USB devices at startup
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      tasks.add(ref.read(deviceManagerProvider.future));
    }

    // 3. Wait for applicable tasks
    await Future.wait(tasks);

    if (!mounted) return;

    // 4. Navigation Logic
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // Desktop -> Go to Admin Dashboard
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
    } else {
      // Mobile -> Check if Student is logged in
      final prefs = await SharedPreferences.getInstance();
      final studentId = prefs.getString('student_id');

      if (studentId != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const StudentDashboardScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const StudentLoginScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.blueGrey[900],
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.monitor_heart,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                "AWEAR",
                style: GoogleFonts.montserrat(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                  color: Colors.blueGrey[900],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "AWARENESS YOU CAN WEAR, BECAUSE WE CARE",
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2,
                  color: Colors.blueGrey[400],
                ),
              ),
              const SizedBox(height: 60),
              // Only show "Initializing Hardware" text on Desktop
              if (!kIsWeb &&
                  (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
                Column(
                  children: [
                    const SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Initializing Hardware...",
                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
