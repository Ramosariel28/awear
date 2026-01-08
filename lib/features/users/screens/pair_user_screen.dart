import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../devices/providers/sender_monitor_provider.dart'; // <--- IMPORT THIS
import '../providers/user_provider.dart';
import '../../dashboard/providers/selection_providers.dart';

class PairUserScreen extends ConsumerWidget {
  const PairUserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedUserId = ref.watch(selectedUserIdProvider);

    // 1. USE THE PERSISTENT MONITOR
    final allDevices = ref.watch(senderMonitorProvider);

    // 2. Filter: Only show devices that are NOT assigned to a user
    final availableDevices = allDevices
        .where((device) => device.assignedUserId == null)
        .toList();

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          AppBar(
            title: const Text("Select Device"),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () {
                ref.read(isPairingUserProvider.notifier).set(false);
              },
            ),
          ),
          Expanded(
            child: availableDevices.isEmpty
                ? const Center(child: Text("No available devices found."))
                : ListView.builder(
                    itemCount: availableDevices.length,
                    itemBuilder: (context, index) {
                      final device = availableDevices[index];
                      return ListTile(
                        leading: Icon(
                          Icons.watch,
                          color: device.isOnline ? Colors.green : Colors.grey,
                        ),
                        title: Text(device.macAddress),
                        // Show if it's Live or just Saved
                        subtitle: Text(
                          device.isOnline ? "Online Now" : "Offline (Saved)",
                        ),
                        onTap: () {
                          if (selectedUserId != null) {
                            ref
                                .read(userNotifierProvider.notifier)
                                .pairUserWithDevice(
                                  selectedUserId,
                                  device.macAddress,
                                );
                            ref.read(isPairingUserProvider.notifier).set(false);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
