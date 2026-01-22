import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // [REQUIRED] For SystemNavigator
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/screens/student_login_screen.dart';
import '../../../core/providers.dart';
import 'student_vitals_widget.dart';
import 'student_chat_widget.dart';

class StudentDashboardScreen extends ConsumerStatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  ConsumerState<StudentDashboardScreen> createState() =>
      _StudentDashboardScreenState();
}

class _StudentDashboardScreenState
    extends ConsumerState<StudentDashboardScreen> {
  String? _studentId;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _studentId = prefs.getString('student_id');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_studentId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // [NEW] Intercept Back Button
    return PopScope(
      canPop: false, // Disable default back action (closing app)
      onPopInvoked: (didPop) async {
        if (didPop) return;

        if (_selectedIndex == 1) {
          // 1. If on Chat, navigate back to Dashboard (Index 0)
          setState(() => _selectedIndex = 0);
        } else {
          // 2. If on Dashboard, ask to Exit App
          final shouldExit = await _showExitConfirm();
          if (shouldExit) {
            SystemNavigator.pop(); // Closes the app window
          }
        }
      },
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_studentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final name = userData['name'] ?? 'Student';
          final role = userData['role'] ?? 'Student';
          // final year = userData['yearLevel'] ?? '';
          final section = userData['section'] ?? '';

          final pages = [
            const StudentVitalsWidget(),
            const StudentChatWidget(),
          ];

          return Scaffold(
            backgroundColor: Colors.grey[50],
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: InkWell(
                onTap: () => _showUserInfo(userData),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "$role • $section",
                      // "$role • $year - $section",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.indigo[400],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.grey),
                  onPressed: () => _showUserInfo(userData),
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.black),
                  onPressed: _logout,
                ),
              ],
            ),
            body: pages[_selectedIndex],
            bottomNavigationBar: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(_studentId)
                  .collection('messages')
                  .where('sender', isEqualTo: 'admin')
                  .where('read', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                int unread = 0;
                if (snapshot.hasData) unread = snapshot.data!.docs.length;

                return BottomNavigationBar(
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    setState(() => _selectedIndex = index);
                    if (index == 1 && _studentId != null) {
                      ref
                          .read(syncServiceProvider)
                          .markAdminMessagesAsRead(_studentId!);
                    }
                  },
                  selectedItemColor: Colors.indigo,
                  unselectedItemColor: Colors.grey,
                  items: [
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.monitor_heart),
                      label: "My Vitals",
                    ),
                    BottomNavigationBarItem(
                      icon: Stack(
                        children: [
                          const Icon(Icons.chat_bubble_outline),
                          if (unread > 0)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 12,
                                  minHeight: 12,
                                ),
                                child: Text(
                                  unread.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                      label: "Chat",
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  // [NEW] Exit Confirmation Dialog
  Future<bool> _showExitConfirm() async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Exit App"),
            content: const Text("Do you want to close the application?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("No"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text("Yes"),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showUserInfo(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Student Information"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow("Name", data['name']),
              _infoRow("ID", data['studentId']),
              const Divider(),
              _infoRow("Role", data['role']),
              _infoRow("Year Level", data['yearLevel']),
              _infoRow("Section", data['section']),
              const Divider(),
              _infoRow(
                "Height",
                data['height'] != null ? "${data['height']} cm" : "--",
              ),
              _infoRow(
                "Weight",
                data['weight'] != null ? "${data['weight']} kg" : "--",
              ),
              _infoRow("Blood Type", data['bloodType']),
              const Divider(),
              _infoRow("Medical Info", data['medicalInfo']),
              const Divider(),
              _infoRow("Paired Device", data['pairedDevice']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              "$label:",
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value ?? "--",
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const StudentLoginScreen()),
    );
  }
}
