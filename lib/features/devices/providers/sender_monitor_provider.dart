import 'dart:async';
import 'package:isar/isar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/device_entity.dart';
import '../../../core/providers.dart';
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

  SenderStatus updatePairing({int? userId, String? userName}) {
    return SenderStatus(
      macAddress: macAddress,
      rssi: rssi,
      lastSeen: lastSeen,
      isMoving: isMoving,
      isOnline: isOnline,
      assignedUserId: userId,
      assignedUserName: userName,
    );
  }
}

@Riverpod(keepAlive: true)
class SenderMonitor extends _$SenderMonitor {
  @override
  List<SenderStatus> build() {
    // 1. INITIAL LOAD
    List<SenderStatus> initialList = [];
    final isar = ref.read(isarProvider).valueOrNull;

    if (isar != null) {
      final savedDevices = isar.deviceEntitys.where().findAllSync();
      initialList = savedDevices.map((e) {
        return SenderStatus(
          macAddress: e.macAddress,
          rssi: 0,
          lastSeen: e.lastSeen,
          isMoving: false,
          isOnline: false,
          assignedUserId: null,
          assignedUserName: null,
        );
      }).toList();
    }

    // 2. IMMEDIATE SYNC
    final currentUsers = ref.read(userNotifierProvider).valueOrNull ?? [];
    if (currentUsers.isNotEmpty && initialList.isNotEmpty) {
      initialList = _applyPairingLogic(initialList, currentUsers);
    }

    state = initialList;

    // 3. LISTEN TO PACKETS
    ref.listen(packetStreamProvider, (previous, next) {
      final packet = next.valueOrNull;
      if (packet != null) {
        final users = ref.read(userNotifierProvider).valueOrNull ?? [];
        _processPacket(packet, users);
      }
    });

    // 4. LISTEN TO USERS
    ref.listen(userNotifierProvider, (previous, next) {
      final users = next.valueOrNull;
      if (users != null) {
        state = _applyPairingLogic(state, users);
      }
    });

    // 5. HEARTBEAT
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkDeviceStatus();
    });
    ref.onDispose(() => timer.cancel());

    return initialList;
  }

  // --- REUSABLE LOGIC ---
  List<SenderStatus> _applyPairingLogic(
    List<SenderStatus> devices,
    List<dynamic> users,
  ) {
    return devices.map((device) {
      final owner = users
          .where((u) => u.pairedDeviceMacAddress == device.macAddress)
          .firstOrNull;

      final int? newOwnerId = owner?.id;
      final String? newOwnerName = owner != null
          ? "${owner.firstName} ${owner.lastName}"
          : null;

      if (device.assignedUserId != newOwnerId) {
        return device.updatePairing(userId: newOwnerId, userName: newOwnerName);
      }
      return device;
    }).toList();
  }

  Future<void> _processPacket(SerialPacket packet, List<dynamic> users) async {
    final currentMac = packet.sender;
    final isar = ref.read(isarProvider).valueOrNull;

    int? userId;
    String? userName;
    final owner = users
        .where((u) => u.pairedDeviceMacAddress == currentMac)
        .firstOrNull;

    if (owner != null) {
      userId = owner.id;
      userName = "${owner.firstName} ${owner.lastName}";
    }

    final index = state.indexWhere((s) => s.macAddress == currentMac);
    bool shouldSaveToDb = false; // Flag to control DB throttling

    if (index >= 0) {
      // Update existing
      final current = state[index];

      // OPTIMIZATION: Only save to DB if >2 seconds passed since last save
      // This prevents the "Application Hang" caused by writing 100x/second
      if (DateTime.now().difference(current.lastSeen).inSeconds >= 2) {
        shouldSaveToDb = true;
      }

      final newState = [...state];
      newState[index] = SenderStatus(
        macAddress: current.macAddress,
        rssi: packet.rssi,
        lastSeen: DateTime.now(),
        isMoving: packet.motion,
        isOnline: true,
        assignedUserId: userId,
        assignedUserName: userName,
      );
      state = newState;
    } else {
      // Add new
      shouldSaveToDb = true; // Always save new devices immediately
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

    // --- FIX: DB Logic with Crash Protection & Throttling ---
    if (isar != null && shouldSaveToDb) {
      // We wrap EVERYTHING in writeTxn to ensure Atomic operations.
      // This prevents two packets from trying to create the same device at once.
      await isar.writeTxn(() async {
        final existing = await isar.deviceEntitys
            .filter()
            .macAddressEqualTo(currentMac)
            .findFirst();

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
        return SenderStatus(
          macAddress: device.macAddress,
          rssi: device.rssi,
          lastSeen: device.lastSeen,
          isMoving: device.isMoving,
          isOnline: false,
          assignedUserId: device.assignedUserId,
          assignedUserName: device.assignedUserName,
        );
      }
      return device;
    }).toList();

    if (hasChanges) state = newState;
  }

  Future<void> deleteDevice(String macAddress) async {
    final device = state.firstWhere(
      (s) => s.macAddress == macAddress,
      orElse: () => SenderStatus(
        macAddress: "",
        rssi: 0,
        lastSeen: DateTime.now(),
        isMoving: false,
      ),
    );

    if (device.assignedUserId != null) {
      return;
    }

    state = state.where((s) => s.macAddress != macAddress).toList();

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
