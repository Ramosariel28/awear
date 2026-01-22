import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../providers/selection_providers.dart';
import '../../users/providers/user_provider.dart';
import '../../../core/serial/serial_packet.dart';
import '../../vitals/providers/live_data_provider.dart';

class UserDashboard extends ConsumerWidget {
  const UserDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Watch the selected user ID
    final selectedId = ref.watch(selectedUserIdProvider);
    // 2. Watch the selected Vital
    final selectedVital = ref.watch(selectedVitalProvider);
    // 3. Watch for live data
    final liveDataAsync = ref.watch(selectedUserLiveVitalsProvider);
    final livePacket = liveDataAsync.valueOrNull;

    final userListAsync = ref.watch(userNotifierProvider);

    // Handle "No User Selected"
    if (selectedId == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey),
            Gap(16),
            Text(
              "Select a user from the list to view data",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Find the user object
    return userListAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text("Error: $err")),
      data: (users) {
        final user = users.where((u) => u.id == selectedId).firstOrNull;

        if (user == null) {
          return const Center(child: Text("User not found"));
        }

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- Header Card (With Badge) ---
              _buildUserHeader(context, ref, user),
              const Gap(24),

              // --- Vitals Grid ---
              const Text(
                "Real-time Vitals",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Gap(16),

              Expanded(
                child: _buildVitalsGrid(
                  context,
                  ref,
                  selectedVital,
                  livePacket,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserHeader(BuildContext context, WidgetRef ref, dynamic user) {
    // Listen for unread messages
    return StreamBuilder<QuerySnapshot>(
      stream: user.firebaseId == null
          ? const Stream.empty()
          : FirebaseFirestore.instance
                .collection('users')
                .doc(user.firebaseId)
                .collection('messages')
                .where('sender', isEqualTo: 'student') // From Student
                .where('read', isEqualTo: false) // Unread
                .snapshots(),
      builder: (context, snapshot) {
        bool hasUnread = false;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          hasUnread = true;
        }

        return Card(
          elevation: 2,
          clipBehavior:
              Clip.antiAlias, // Ensures badge doesn't overflow weirdly
          child: InkWell(
            onTap: () {
              ref.read(selectedVitalProvider.notifier).clear();
              ref
                  .read(userDetailViewModeProvider.notifier)
                  .set(UserDetailView.vitals);
            },
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          user.firstName.isNotEmpty ? user.firstName[0] : "?",
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Gap(20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${user.lastName}, ${user.firstName}",
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Gap(4),
                          Row(
                            children: [
                              _buildBadge(context, user.role, Colors.blue),
                              const Gap(8),
                              // _buildBadge(
                              //   context,
                              //   user.yearLevel,
                              //   Colors.orange,
                              // ),
                              // const Gap(8),
                              _buildBadge(context, user.section, Colors.green),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Chevron retained as requested
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),

                // --- THE RED DOT (Notification Badge) ---
                if (hasUnread)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildVitalsGrid(
    BuildContext context,
    WidgetRef ref,
    String? selectedVital,
    SerialPacket? packet,
  ) {
    String fmt(num? val, {int decimals = 0}) =>
        val?.toStringAsFixed(decimals) ?? "--";

    final vitals = [
      {
        "label": "Heart Rate",
        "value": fmt(packet?.heartRate),
        "unit": "bpm",
        "icon": Icons.favorite,
        "color": Colors.red,
      },
      {
        "label": "Oxygen",
        "value": fmt(packet?.oxygen),
        "unit": "%",
        "icon": Icons.air,
        "color": Colors.blue,
      },
      {
        "label": "Resp. Rate",
        "value": fmt(packet?.respirationRate),
        "unit": "rpm",
        "icon": Icons.timer,
        "color": Colors.teal,
      },
      {
        "label": "Temp",
        "value": fmt(packet?.temperature, decimals: 1),
        "unit": "°C",
        "icon": Icons.thermostat,
        "color": Colors.orange,
      },
      {
        "label": "Stress",
        "value": fmt(packet?.stress),
        "unit": "ms",
        "icon": Icons.bolt,
        "color": Colors.purple,
      },
      {
        "label": "Sleep",
        "value": "Disabled",
        "unit": "",
        "icon": Icons.bedtime,
        "color": Colors.grey,
      },
    ];

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 12,
      ),
      itemCount: vitals.length,
      itemBuilder: (context, index) {
        final v = vitals[index];
        final isEnabled = v['label'] != "Sleep";
        final isSelected = selectedVital == v['label'];

        return Card(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : (isEnabled ? Colors.white : Colors.grey[100]),
          elevation: isSelected ? 4 : (isEnabled ? 2 : 0),
          child: InkWell(
            onTap: isEnabled
                ? () {
                    ref
                        .read(selectedVitalProvider.notifier)
                        .select(v['label'] as String);
                    ref
                        .read(userDetailViewModeProvider.notifier)
                        .set(UserDetailView.vitals);
                  }
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(
                    v['icon'] as IconData,
                    size: 32,
                    color: v['color'] as Color,
                  ),
                  const Gap(16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        v['label'] as String,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      Text(
                        "${v['value']} ${v['unit']}",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? Colors.black : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
