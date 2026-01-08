import 'dart:async';
import 'package:isar/isar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/device_entity.dart';
import '../../../core/providers.dart'; // For isarProvider
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
    this.isOnline = false,
  });

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

// 1. KEEP ALIVE: Prevents clearing when navigating away
@Riverpod(keepAlive: true)
class SenderMonitor extends _$SenderMonitor {
  @override
  List<SenderStatus> build() {
    // 2. LOAD FROM DB: Initialize state with saved devices
    final isar = ref.watch(isarProvider).valueOrNull;
    List<SenderStatus> initialState = [];

    if (isar != null) {
      final savedDevices = isar.deviceEntitys.where().findAllSync();
      initialState = savedDevices.map((e) {
        // Check if this device is assigned to a user
        final user = ref
            .read(userNotifierProvider)
            .valueOrNull
            ?.where((u) => u.pairedDeviceMacAddress == e.macAddress)
            .firstOrNull;

        return SenderStatus(
          macAddress: e.macAddress,
          rssi: 0,
          lastSeen: e.lastSeen,
          isMoving: false,
          isOnline: false, // Initially offline until we hear a packet
          assignedUserId: user?.id,
          assignedUserName: user != null
              ? "${user.firstName} ${user.lastName}"
              : null,
        );
      }).toList();
    }

    // 3. LISTEN TO PACKETS
    ref.listen(packetStreamProvider, (previous, next) {
      final packet = next.valueOrNull;
      if (packet != null) {
        final users = ref.read(userNotifierProvider).valueOrNull ?? [];
        _processPacket(packet, users);
      }
    });

    // 4. HEARTBEAT TIMER (Check Offline)
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkDeviceStatus();
    });
    ref.onDispose(() => timer.cancel());

    return initialState;
  }

  Future<void> _processPacket(SerialPacket packet, List<dynamic> users) async {
    final currentMac = packet.sender;
    final isar = ref.read(isarProvider).valueOrNull;

    // A. Find Owner
    int? userId;
    String? userName;
    final owner = users
        .where((u) => u.pairedDeviceMacAddress == currentMac)
        .firstOrNull;

    if (owner != null) {
      userId = owner.id;
      userName = "${owner.firstName} ${owner.lastName}";
    }

    // B. Update In-Memory State
    final index = state.indexWhere((s) => s.macAddress == currentMac);

    if (index >= 0) {
      final newState = [...state];
      newState[index] = newState[index].copyWith(
        rssi: packet.rssi,
        isMoving: packet.motion,
        lastSeen: DateTime.now(),
        isOnline: true,
        assignedUserId: userId,
        assignedUserName: userName,
      );
      state = newState;
    } else {
      // New Device Found
      final newStatus = SenderStatus(
        macAddress: currentMac,
        rssi: packet.rssi,
        lastSeen: DateTime.now(),
        isMoving: packet.motion,
        isOnline: true,
        assignedUserId: userId,
        assignedUserName: userName,
      );
      state = [...state, newStatus];
    }

    // C. Save to Database (Persist Discovery)
    if (isar != null) {
      final existing = await isar.deviceEntitys
          .filter()
          .macAddressEqualTo(currentMac)
          .findFirst();

      await isar.writeTxn(() async {
        if (existing != null) {
          existing.lastSeen = DateTime.now();
          await isar.deviceEntitys.put(existing);
        } else {
          final newEntity = DeviceEntity()
            ..macAddress = currentMac
            ..lastSeen = DateTime.now()
            ..isPaired = (userId != null);
          await isar.deviceEntitys.put(newEntity);
        }
      });
    }
  }

  void _checkDeviceStatus() {
    final now = DateTime.now();
    bool hasChanges = false;

    final newState = state.map((device) {
      final difference = now.difference(device.lastSeen).inSeconds;
      if (difference > 10 && device.isOnline) {
        hasChanges = true;
        return device.copyWith(isOnline: false);
      }
      return device;
    }).toList();

    if (hasChanges) state = newState;
  }

  // DELETE DEVICE (Only if unpaired)
  Future<void> deleteDevice(String macAddress) async {
    final device = state.firstWhere((s) => s.macAddress == macAddress);

    if (device.assignedUserId != null) {
      // Prevent deletion if paired
      return;
    }

    // 1. Remove from UI
    state = state.where((s) => s.macAddress != macAddress).toList();

    // 2. Remove from DB
    final isar = ref.read(isarProvider).valueOrNull;
    if (isar != null) {
      await isar.writeTxn(() async {
        await isar.deviceEntitys
            .filter()
            .macAddressEqualTo(macAddress)
            .deleteAll();
      });
    }
  }
}
