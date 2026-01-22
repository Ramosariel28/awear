import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gap/gap.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'student_history_screen.dart'; // [NEW] We will create this next

class StudentVitalsWidget extends StatefulWidget {
  const StudentVitalsWidget({super.key});

  @override
  State<StudentVitalsWidget> createState() => _StudentVitalsWidgetState();
}

class _StudentVitalsWidgetState extends State<StudentVitalsWidget> {
  String? _studentId;

  @override
  void initState() {
    super.initState();
    _loadId();
  }

  Future<void> _loadId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentId = prefs.getString('student_id');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_studentId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_studentId)
          .collection('vitals')
          .doc('latest')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text("Waiting for device data..."));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;

        // Helper to format as Integer (No decimals)
        String fmt(dynamic val) {
          if (val == null) return "--";
          if (val is num) {
            return val.round().toString(); // [FIX] Round to Integer
          }
          return val.toString();
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Live Vitals",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Gap(4),
              const Text(
                "Tap a card to view history",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Gap(20),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 1.3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: [
                    _buildCard(
                      "Heart Rate",
                      fmt(data['hr']),
                      "bpm",
                      Icons.favorite,
                      Colors.red,
                      'hr',
                    ),
                    _buildCard(
                      "Oxygen",
                      fmt(data['oxy']),
                      "%",
                      Icons.air,
                      Colors.blue,
                      'oxy',
                    ),
                    _buildCard(
                      "Respiration",
                      fmt(data['rr']),
                      "rpm",
                      Icons.timer,
                      Colors.green,
                      'rr',
                    ), // [NEW] Added RR
                    _buildCard(
                      "Temp",
                      fmt(data['temp']),
                      "°C",
                      Icons.thermostat,
                      Colors.orange,
                      'temp',
                    ),
                    _buildCard(
                      "Stress",
                      fmt(data['stress']),
                      "ms",
                      Icons.bolt,
                      Colors.purple,
                      'stress',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(
    String label,
    String value,
    String unit,
    IconData icon,
    Color color,
    String dataKey,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // [NEW] Navigate to History
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StudentHistoryScreen(
                studentId: _studentId!,
                label: label,
                dataKey: dataKey,
                unit: unit,
                color: color,
              ),
            ),
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const Gap(8),
            Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(unit, style: TextStyle(color: Colors.grey[400])),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
