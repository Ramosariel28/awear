import 'dart:async';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:isar/isar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/vital_log_entity.dart';
import '../../../core/providers.dart';
import '../../../core/serial/serial_packet.dart';
import '../../dashboard/providers/selection_providers.dart';
import '../../devices/providers/connection_provider.dart';
import '../../users/providers/user_provider.dart';

part 'live_data_provider.g.dart';

// --- DASHBOARD HELPER (User B Fix) ---
@riverpod
Stream<SerialPacket> selectedUserLiveVitals(SelectedUserLiveVitalsRef ref) {
  final selectedId = ref.watch(selectedUserIdProvider);
  if (selectedId == null) return const Stream.empty();

  // Check pairing to ensure we don't show ghost data
  final userAsync = ref.watch(userNotifierProvider);
  final user = userAsync.valueOrNull?.where((u) => u.id == selectedId).firstOrNull;
  
  if (user == null || user.pairedDeviceMacAddress == null) {
    return const Stream.empty();
  }

  // ignore: deprecated_member_use
  return ref.watch(liveVitalStreamProvider(selectedId).stream);
}

// --- HISTORY FETCHING ---
@riverpod
Stream<List<VitalLogEntity>> vitalHistory(
  VitalHistoryRef ref,
  int userId,
) async* {
  // Await the FUTURE to ensure Isar is ready before querying
  final isar = await ref.watch(isarProvider.future);
  
  yield* isar.vitalLogEntitys
      .filter()
      .userIdEqualTo(userId)
      .sortByTimestampDesc()
      .limit(50)
      .watch(fireImmediately: true);
}

// --- MAIN LOGIC ---
@riverpod
Stream<SerialPacket> liveVitalStream(
  LiveVitalStreamRef ref,
  int userId,
) async* {
  // 1. Get User Info
  final userAsync = ref.watch(userNotifierProvider);
  final user = userAsync.valueOrNull?.where((u) => u.id == userId).firstOrNull;

  if (user == null || user.pairedDeviceMacAddress == null) {
    yield* Stream.empty();
    return;
  }
  final targetMac = user.pairedDeviceMacAddress!;

  // 2. Wait for Isar to be ready
  final isar = await ref.watch(isarProvider.future);

  // 3. Fetch initial history (Optional: show last known data)
  final lastLog = await isar.vitalLogEntitys
      .filter()
      .userIdEqualTo(userId)
      .sortByTimestampDesc()
      .findFirst();

  if (lastLog != null) {
    yield SerialPacket(
      sender: targetMac,
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

  // 4. Start Listening
  final packetStream = ref.watch(packetStreamProvider.notifier).stream;

  // [NEW] Cache the actual PACKET data, not just the timestamp
  SerialPacket? _lastSavedPacket;
  DateTime? _lastSavedTime;

  await for (final packet in packetStream) {
    if (packet.sender == targetMac) {
      
      bool isDuplicate = false;

      // [LOGIC] Smart De-duplication
      if (_lastSavedPacket != null && _lastSavedTime != null) {
        final msSinceLastSave = DateTime.now().difference(_lastSavedTime!).inMilliseconds;
        
        // If the packet arrived within 1 second of the last one...
        if (msSinceLastSave < 1000) {
           // ...AND the critical values are EXACTLY the same...
           if (packet.id == _lastSavedPacket!.id && // vital if you use IDs
               packet.heartRate == _lastSavedPacket!.heartRate &&
               packet.oxygen == _lastSavedPacket!.oxygen &&
               packet.stress == _lastSavedPacket!.stress &&
               packet.temperature == _lastSavedPacket!.temperature) {
             
             // ...then it is a Redundant Copy.
             isDuplicate = true; 
           }
        }
      }

      if (!isDuplicate) {
        // Update the Cache
        _lastSavedPacket = packet;
        _lastSavedTime = DateTime.now();
        
        // Save to DB
        await _saveToHistory(isar, packet, userId);
      }

      // ALWAYS yield to UI (so the graph/numbers feel responsive)
      yield packet;
    }
  }
}

// [FIX] Accept 'Isar' as an argument so we don't have to look it up again
Future<void> _saveToHistory(
  Isar isar,
  SerialPacket packet,
  int userId,
) async {
  try {
    // Filter out invalid/empty packets
    if ((packet.heartRate ?? 0) <= 0 && (packet.oxygen ?? 0) <= 0) {
      return;
    }

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
    
    // Uncomment this if you want to see confirmation in the console
    // debugPrint("SAVED: HR=${packet.heartRate} for User $userId");

  } catch (e, stack) {
    debugPrint("CRITICAL DB ERROR: $e");
    debugPrint(stack.toString());
  }
}