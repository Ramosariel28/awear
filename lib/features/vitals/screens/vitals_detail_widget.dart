import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../dashboard/providers/selection_providers.dart';
import '../../users/providers/user_provider.dart';
import '../providers/live_data_provider.dart';
import '../../../core/database/vital_log_entity.dart';

class VitalsDetailWidget extends ConsumerStatefulWidget {
  const VitalsDetailWidget({super.key});

  @override
  ConsumerState<VitalsDetailWidget> createState() => _VitalsDetailWidgetState();
}

class _VitalsDetailWidgetState extends ConsumerState<VitalsDetailWidget> {
  bool _hideMotionData = true;

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedUserIdProvider);
    final selectedVital = ref.watch(selectedVitalProvider);
    final userList = ref.watch(userNotifierProvider).valueOrNull ?? [];

    if (selectedId == null) return const Center(child: Text("Select a User"));
    if (selectedVital == null) {
      return const Center(child: Text("Select a Vital"));
    }

    final historyAsync = ref.watch(vitalHistoryProvider(selectedId));
    final user = userList.where((u) => u.id == selectedId).firstOrNull;

    if (user == null) return const SizedBox();

    Color color;
    switch (selectedVital) {
      case 'Heart Rate':
        color = Colors.red;
        break;
      case 'Oxygen':
        color = Colors.blue;
        break;
      case 'Temp':
        color = Colors.orange;
        break;
      default:
        color = Colors.teal;
    }

    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Header ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedVital,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "History for ${user.firstName}",
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    "Filter Motion:",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  Switch(
                    value: _hideMotionData,
                    activeThumbColor: color,
                    onChanged: (val) => setState(() => _hideMotionData = val),
                  ),
                  const Gap(8),
                  IconButton(
                    onPressed: () =>
                        ref.refresh(vitalHistoryProvider(selectedId)),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
          const Gap(24),

          // --- Graph Section ---
          SizedBox(
            height: 250,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: historyAsync.when(
                  data: (logs) => _buildChart(logs, selectedVital, color),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text("Error loading graph: $e")),
                ),
              ),
            ),
          ),
          const Gap(24),

          // --- History List ---
          const Text(
            "Recent Records",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Gap(8),
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text("Error: $e")),
              data: (logs) {
                if (logs.isEmpty) return const Text("No records found.");

                return ListView.separated(
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final value = _getValue(log, selectedVital);

                    // [FIX] Handle nullable boolean safely
                    final isMoving = log.motion ?? false;

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      tileColor: isMoving ? Colors.grey[100] : null,
                      title: Row(
                        children: [
                          Text(
                            "Value: ${value?.toStringAsFixed(1) ?? '--'}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: isMoving
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isMoving ? Colors.grey : Colors.black,
                            ),
                          ),
                          if (isMoving)
                            const Text(
                              " (Motion)",
                              style: TextStyle(fontSize: 10, color: Colors.red),
                            ),
                        ],
                      ),
                      subtitle: Text(log.timestamp.toString().substring(0, 19)),
                      leading: Icon(
                        isMoving ? Icons.directions_run : Icons.circle,
                        size: 12,
                        color: isMoving ? Colors.grey : color,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<VitalLogEntity> logs, String vitalType, Color color) {
    if (logs.isEmpty) return const Center(child: Text("No Data Available"));

    final sortedLogs = logs.reversed.toList();
    final spots = <FlSpot>[];

    for (int i = 0; i < sortedLogs.length; i++) {
      final log = sortedLogs[i];

      // [FIX] Handle nullable boolean in condition
      if (_hideMotionData && (log.motion ?? false)) {
        continue;
      }

      final val = _getValue(log, vitalType);
      if (val != null && val > 0) {
        spots.add(FlSpot(i.toDouble(), val));
      }
    }

    if (spots.isEmpty) {
      return const Center(child: Text("Data hidden due to motion filter"));
    }

    return LineChart(
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
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  double? _getValue(VitalLogEntity log, String vitalType) {
    switch (vitalType) {
      case 'Heart Rate':
        return log.hr;
      case 'Oxygen':
        return log.oxy;
      case 'Temp':
        return log.temp;
      case 'Resp. Rate':
        return log.rr;
      case 'Stress':
        return log.stress;
      default:
        return 0;
    }
  }
}
