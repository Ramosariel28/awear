import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gap/gap.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../student/screens/student_dashboard_screen.dart';

class StudentLoginScreen extends ConsumerStatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  ConsumerState<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends ConsumerState<StudentLoginScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_person, size: 80, color: Colors.indigo),
              const Gap(24),
              const Text(
                "Student Login",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Text(
                "Enter the 2-word code given by your admin",
                style: TextStyle(color: Colors.grey),
              ),
              const Gap(32),
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: "e.g. happy-lion",
                  errorText: _error,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const Gap(24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text("Access My Data"),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    final code = _codeController.text.trim().toLowerCase();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. Query Firestore for the password
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('generatedPassword', isEqualTo: code)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        setState(() => _error = "Invalid code. Please try again.");
      } else {
        // 2. Success! Save ID locally so they stay logged in
        final doc = querySnapshot.docs.first;
        final studentId = doc.id; // This is the Document ID (String)
        final studentName = doc['name'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('student_id', studentId);
        await prefs.setString('student_name', studentName);

        if (!mounted) return;

        // 3. Navigate to Student Dashboard
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const StudentDashboardScreen()),
        );
      }
    } catch (e) {
      setState(() => _error = "Connection error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
