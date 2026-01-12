import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import '../providers/sender_monitor_provider.dart';

class SenderListWidget extends ConsumerStatefulWidget {
  const SenderListWidget({super.key});

  @override
  ConsumerState<SenderListWidget> createState() => _SenderListWidgetState();
}

class _SenderListWidgetState extends ConsumerState<SenderListWidget> {
  // Timer is no longer needed here as the Provider handles status checks internally

  @override
  Widget build(BuildContext context) {
    final senders = ref.watch(senderMonitorProvider);

    if (senders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_tethering_off, size: 48, color: Colors.grey[300]),
            const Gap(16),
            const Text(
              "No transmitters detected",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Transmitters (${senders.length})",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.circle, size: 10, color: Colors.green),
                  Gap(4),
                  Text("Paired", style: TextStyle(fontSize: 12)),
                  Gap(12),
                  Icon(Icons.circle, size: 10, color: Colors.orange),
                  Gap(4),
                  Text("New", style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: senders.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final device = senders[index];
              final isAssigned = device.assignedUserId != null;
              final isOnline = device.isOnline;

              return Opacity(
                opacity: isOnline ? 1.0 : 0.5, // Fade out if offline
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isAssigned
                        ? Colors.green[100]
                        : Colors.orange[100],
                    child: Icon(
                      isAssigned ? Icons.person : Icons.question_mark,
                      color: isAssigned
                          ? Colors.green[700]
                          : Colors.orange[700],
                    ),
                  ),
                  title: Text(
                    isAssigned ? device.assignedUserName! : "Unassigned Device",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isAssigned ? Colors.black : Colors.grey[700],
                    ),
                  ),
                  subtitle: Row(
                    children: [
                      Text("MAC: ${device.macAddress}"),
                      const Gap(8),
                      if (!isOnline)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            "OFFLINE",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Signal & Info Column
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                device.rssi > -60
                                    ? Icons.signal_wifi_4_bar
                                    : device.rssi > -70
                                    ? Icons.signal_wifi_4_bar_lock
                                    : Icons.signal_wifi_0_bar,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const Gap(4),
                              Text(
                                "${device.rssi} dBm",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const Gap(4),
                          if (device.isMoving)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                "Moving",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // Delete Button (Only if NOT paired)
                      if (!isAssigned)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () {
                            ref
                                .read(senderMonitorProvider.notifier)
                                .deleteDevice(device.macAddress);
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
