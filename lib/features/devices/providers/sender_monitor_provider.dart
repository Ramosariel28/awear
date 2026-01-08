import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/serial/serial_packet.dart';
import '../../users/providers/user_provider.dart';
import 'connection_provider.dart';

part 'sender_monitor_provider.g.dart';

class SenderStatus {
  final String macAddress;
  final int rssi;
  final DateTime lastSeen;
  final bool isMoving;
  final int? assignedUserId;
  final String? assignedUserName;
  final bool isOnline;

  SenderStatus({
    required this.macAddress,
    required this.rssi,
    required this.lastSeen,
    required this.isMoving,
    this.assignedUserId,
    this.assignedUserName,
    this.isOnline = true,
  });

  // Helper to copy object with new values (since fields are final)
  SenderStatus copyWith({
    int? rssi,
    DateTime? lastSeen,
    bool? isMoving,
    bool? isOnline,
    int? assignedUserId,
    String? assignedUserName,
  }) {
    return SenderStatus(
      macAddress: macAddress,
      rssi: rssi ?? this.rssi,
      lastSeen: lastSeen ?? this.lastSeen,
      isMoving: isMoving ?? this.isMoving,
      isOnline: isOnline ?? this.isOnline,
      assignedUserId: assignedUserId ?? this.assignedUserId,
      assignedUserName: assignedUserName ?? this.assignedUserName,
    );
  }
}

@riverpod
class SenderMonitor extends _$SenderMonitor {
  @override
  List<SenderStatus> build() {
    // 1. Listen to the stream for new packets
    ref.listen(packetStreamProvider, (previous, next) {
      final packet = next.valueOrNull;
      if (packet != null) {
        // DEBUG: Confirm the Monitor received the packet
        print("MONITOR: Processing packet from ${packet.sender}");

        final users = ref.read(userNotifierProvider).valueOrNull ?? [];
        _processPacket(packet, users);
      }
    });

    // 2. Set up a Timer to update UI
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      checkDeviceStatus();
    });

    // 3. Ensure the timer stops when this provider is no longer used
    ref.onDispose(() {
      timer.cancel();
    });

    return [];
  }

  void _processPacket(SerialPacket packet, List<dynamic> users) {
    // Use 'packet.sender' (matches your SerialPacket class)
    final currentMac = packet.sender;

    // Find Owner
    int? userId;
    String? userName;
    final owner = users
        .where((u) => u.pairedDeviceMacAddress == currentMac)
        .firstOrNull;

    if (owner != null) {
      userId = owner.id;
      userName = "${owner.firstName} ${owner.lastName}";
    }

    // Check if device exists
    final index = state.indexWhere((s) => s.macAddress == currentMac);

    if (index >= 0) {
      // UPDATE EXISTING: Use copyWith to update timestamp and mark Online
      final newState = [...state];
      newState[index] = newState[index].copyWith(
        rssi: packet.rssi,
        isMoving: packet.motion,
        lastSeen: DateTime.now(),
        isOnline: true, // It just sent data, so it's online
        // Update user info if it changed
        assignedUserId: userId,
        assignedUserName: userName,
      );
      state = newState;
    } else {
      // ADD NEW
      final newStatus = SenderStatus(
        macAddress: currentMac,
        rssi: packet.rssi,
        lastSeen: DateTime.now(),
        isMoving: packet.motion,
        assignedUserId: userId,
        assignedUserName: userName,
        isOnline: true,
      );
      state = [...state, newStatus];
    }
  }

  void checkDeviceStatus() {
    final now = DateTime.now();
    bool hasChanges = false;

    // Create a new list mapped from the old one
    final newState = state.map((device) {
      final difference = now.difference(device.lastSeen).inSeconds;

      // If > 10 seconds and currently marked online, mark offline
      if (difference > 10 && device.isOnline) {
        hasChanges = true;
        return device.copyWith(isOnline: false);
      }
      // Note: We don't automatically mark it online here;
      // _processPacket handles that when data arrives.
      return device;
    }).toList();

    // Only update state (triggering UI rebuild) if something actually changed
    if (hasChanges) {
      state = newState;
    }
  }
}
