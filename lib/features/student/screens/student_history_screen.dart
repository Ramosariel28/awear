import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class StudentHistoryScreen extends StatefulWidget {
  final String studentId;
  final String label;
  final String dataKey;
  final String unit;
  final Color color;

  const StudentHistoryScreen({
    super.key,
    required this.studentId,
    required this.label,
    required this.dataKey,
    required this.unit,
    required this.color,
  });

  @override
  State<StudentHistoryScreen> createState() => _StudentHistoryScreenState();
}

class _StudentHistoryScreenState extends State<StudentHistoryScreen> {
  bool _hideMotionData = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.label} History"),
        backgroundColor: widget.color,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _hideMotionData ? Icons.filter_alt : Icons.filter_alt_off,
            ),
            tooltip: "Toggle Motion Filter",
            onPressed: () {
              setState(() {
                _hideMotionData = !_hideMotionData;
              });
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.studentId)
            .collection('history')
            .orderBy('timestamp', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text("No history available yet."));
          }

          List<FlSpot> spots = [];
          final reversedDocs = docs.reversed.toList();

          for (int i = 0; i < reversedDocs.length; i++) {
            final data = reversedDocs[i].data() as Map<String, dynamic>;
            final isMoving = data['motion'] == true;

            if (_hideMotionData && isMoving) continue;

            final rawVal = data[widget.dataKey];
            if (rawVal is num) {
              spots.add(FlSpot(i.toDouble(), rawVal.toDouble()));
            }
          }

          return Column(
            children: [
              Container(
                height: 200,
                padding: const EdgeInsets.all(16),
                color: widget.color.withValues(alpha: 0.05),
                child: spots.isEmpty
                    ? const Center(child: Text("No clean data available"))
                    : LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) => Colors.blueGrey,
                            ),
                          ),
                          lineBarsData: [
                            LineChartBarData(
                              spots: spots,
                              isCurved: true,
                              color: widget.color,
                              barWidth: 3,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: widget.color.withValues(alpha: 0.2),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final rawVal = data[widget.dataKey];
                    final value = rawVal is num
                        ? rawVal.round().toString()
                        : "--";
                    final isMoving = data['motion'] == true;

                    final ts = data['timestamp'] as Timestamp?;
                    final timeStr = ts != null
                        ? DateFormat('MMM d, h:mm a').format(ts.toDate())
                        : "Unknown Time";

                    return ListTile(
                      tileColor: isMoving ? Colors.grey[100] : null,
                      leading: Icon(
                        isMoving ? Icons.directions_run : Icons.circle,
                        color: isMoving ? Colors.grey : widget.color,
                        size: isMoving ? 16 : 12,
                      ),
                      title: Text(
                        "$value ${widget.unit}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration: isMoving
                              ? TextDecoration.lineThrough
                              : null,
                          color: isMoving ? Colors.grey : Colors.black,
                        ),
                      ),
                      subtitle: Text(timeStr),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
