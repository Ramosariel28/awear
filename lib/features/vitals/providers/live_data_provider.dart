import 'dart:async';
import 'package:isar/isar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/vital_log_entity.dart';
import '../../../core/providers.dart';
import '../../../core/serial/serial_packet.dart';
import '../../dashboard/providers/selection_providers.dart';
import '../../devices/providers/connection_provider.dart';
import '../../users/providers/user_provider.dart';

part 'live_data_provider.g.dart';

// --- HISTORY PROVIDER ---
@riverpod
Stream<List<VitalLogEntity>> vitalHistory(
  VitalHistoryRef ref,
  int userId,
) async* {
  final isar = await ref.watch(isarProvider.future);
  // Watch the database for changes so the list updates automatically
  yield* isar.vitalLogEntitys
      .filter()
      .userIdEqualTo(userId)
      .sortByTimestampDesc()
      .limit(50) // Limit to recent 50 records
      .watch(fireImmediately: true);
}

// --- DASHBOARD HELPERS ---
@riverpod
Stream<SerialPacket> selectedUserLiveVitals(
  SelectedUserLiveVitalsRef ref,
) async* {
  final selectedId = ref.watch(selectedUserIdProvider);
  if (selectedId == null) return;

  // Ensure we only proceed if User has a paired MAC
  final userAsync = ref.watch(userNotifierProvider);
  final user = userAsync.valueOrNull
      ?.where((u) => u.id == selectedId)
      .firstOrNull;
  if (user?.pairedDeviceMacAddress == null) return;

  // Use the underlying packet stream and filter it here directly
  // to avoid the provider-to-provider .stream deprecation.
  final packetStream = ref.watch(packetStreamProvider.notifier).stream;

  await for (final packet in packetStream) {
    if (packet.sender == user!.pairedDeviceMacAddress) {
      yield packet;
    }
  }
}

@riverpod
Stream<SerialPacket> liveVitalStream(
  LiveVitalStreamRef ref,
  int userId,
) async* {
  // 1. Fetch the User to get Pairing Info (UNCHANGED)
  final userAsync = ref.watch(userNotifierProvider);
  final user = userAsync.valueOrNull?.where((u) => u.id == userId).firstOrNull;

  // 2. PERSISTENCE STRATEGY (UNCHANGED)
  final isar = ref.read(isarProvider).valueOrNull;
  if (isar != null) {
    final lastLog = await isar.vitalLogEntitys
        .filter()
        .userIdEqualTo(userId)
        .sortByTimestampDesc()
        .findFirst();

    if (lastLog != null) {
      yield SerialPacket(
        sender: user?.pairedDeviceMacAddress ?? "HISTORY",
        rssi: 0,
        id: 0,
        heartRate: lastLog.hr,
        oxygen: lastLog.oxy,
        respirationRate: lastLog.rr,
        temperature: lastLog.temp,
        stress: lastLog.stress,
        motion: lastLog.motion ?? false,
      );
    }
  }

  // 3. PAIRING CHECK (UNCHANGED)
  if (user == null || user.pairedDeviceMacAddress == null) {
    return;
  }

  final targetMac = user.pairedDeviceMacAddress!;

  // 4. LIVE STREAM LISTENING (UPDATED)
  final packetStream = ref.watch(packetStreamProvider.notifier).stream;

  // [NEW] Local variable to track the last time we ACTUALLY saved to the DB.
  // This lives only as long as this specific stream connection is alive.
  DateTime? lastSavedTimestamp;

  await for (final packet in packetStream) {
    // Only process packets from the paired device
    if (packet.sender == targetMac) {
      final now = DateTime.now();

      // [NEW] THROTTLE CHECK
      // If we saved a record less than 2 seconds ago, SKIP saving.
      // We still 'yield' to update the UI immediately, but we protect the DB.
      bool shouldSave = true;
      if (lastSavedTimestamp != null &&
          now.difference(lastSavedTimestamp).inMilliseconds < 2000) {
        shouldSave = false;
      }

      if (shouldSave) {
        lastSavedTimestamp = now; // Update the lock immediately
        _saveToHistory(ref, packet, userId);
      }

      // Update UI (Always show the user that data is alive)
      yield packet;
    }
  }
}

Future<void> _saveToHistory(
  LiveVitalStreamRef ref,
  SerialPacket packet,
  int userId,
) async {
  try {
    final isar = ref.read(isarProvider).valueOrNull;
    if (isar == null) return;

    if ((packet.heartRate ?? 0) > 0 || (packet.oxygen ?? 0) > 0) {
      // --- STEP 1: Fetch the most recent log ---
      final lastLog = await isar.vitalLogEntitys
          .filter()
          .userIdEqualTo(userId)
          .sortByTimestampDesc()
          .findFirst();

      // --- STEP 2: The Guard Clause ---
      // If we have a last record...
      if (lastLog != null) {
        final timeDiff = DateTime.now().difference(lastLog.timestamp);

        // ...and it was saved less than 2 seconds ago...
        if (timeDiff.inSeconds < 2) {
          // ...and the values are identical...
          if (lastLog.hr == packet.heartRate &&
              lastLog.oxy == packet.oxygen &&
              lastLog.temp == packet.temperature) {
            // ...STOP. This is a duplicate.
            return;
          }
        }
      }

      // --- STEP 3: Proceed to Save ---
      final log = VitalLogEntity()
        ..userId = userId
        ..timestamp = DateTime.now()
        ..hr = packet.heartRate
        ..oxy = packet.oxygen
        ..rr = packet.respirationRate
        ..temp = packet.temperature
        ..stress = packet.stress
        ..motion = packet.motion;

      await isar.writeTxn(() async {
        await isar.vitalLogEntitys.put(log);
      });
    }
  } catch (e) {
    // Handle error
  }
}
