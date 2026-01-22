import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/vital_log_entity.dart';
import '../../../core/providers.dart';
import '../../../core/serial/serial_packet.dart';
import '../../dashboard/providers/selection_providers.dart';
import '../../devices/providers/connection_provider.dart';
import '../../users/providers/user_provider.dart';

part 'live_data_provider.g.dart';

// [HELPER] Create a default empty packet to prevent null errors
SerialPacket _createEmptyPacket() {
  return SerialPacket(
    id: 0,
    heartRate: 0,
    oxygen: 0,
    temperature: 0,
    stress: 0,
    motion: false,
    rssi: 0,
    sender: '',
  );
}

// --- DASHBOARD HELPER ---
@riverpod
Stream<SerialPacket> selectedUserLiveVitals(SelectedUserLiveVitalsRef ref) {
  final selectedId = ref.watch(selectedUserIdProvider);

  if (selectedId == null) return Stream.value(_createEmptyPacket());

  final userAsync = ref.watch(userNotifierProvider);
  final user = userAsync.valueOrNull
      ?.where((u) => u.id == selectedId)
      .firstOrNull;

  if (user == null || user.pairedDeviceMacAddress == null) {
    return Stream.value(_createEmptyPacket());
  }

  // Watch the provider for the specific User ID
  final asyncValue = ref.watch(liveVitalStreamProvider(selectedId));

  return Stream.value(asyncValue.value ?? _createEmptyPacket());
}

// --- HISTORY FETCHING ---
@riverpod
Stream<List<VitalLogEntity>> vitalHistory(
  VitalHistoryRef ref,
  int userId,
) async* {
  final isar = await ref.watch(isarProvider.future);

  final stream = isar.vitalLogEntitys
      .filter()
      .userIdEqualTo(userId)
      .sortByTimestampDesc()
      .limit(50)
      .watch(fireImmediately: true);

  yield* stream;
}

// --- LIVE DATA LOGIC ---
@riverpod
class LiveVitalStream extends _$LiveVitalStream {
  DateTime? _lastCloudUploadTime;
  DateTime? _lastLocalSaveTime; // [NEW] Throttle for local DB too

  SerialPacket? _lastValidPacket;
  SerialPacket?
  _lastProcessedPacket; // [NEW] Prevents duplicate saves on rebuild

  @override
  Stream<SerialPacket> build(int userId) async* {
    // 1. Validate User
    final userList = ref.watch(userNotifierProvider).valueOrNull ?? [];
    final user = userList.where((u) => u.id == userId).firstOrNull;

    if (user == null || user.pairedDeviceMacAddress == null) {
      yield _createEmptyPacket();
      return;
    }

    final isar = await ref.watch(isarProvider.future);
    final syncService = ref.read(syncServiceProvider);

    // 2. Watch Serial Stream
    final packetAsync = ref.watch(packetStreamProvider);
    final packet = packetAsync.valueOrNull;

    // 3. Filter Packet
    if (packet != null && packet.sender == user.pairedDeviceMacAddress) {
      _lastValidPacket = packet;

      // [CRITICAL FIX] Check if we already processed this specific packet instance
      // This prevents double-saving when 'userNotifierProvider' triggers a rebuild
      if (packet != _lastProcessedPacket) {
        _lastProcessedPacket = packet;

        final now = DateTime.now();

        // A. Save to Local History (Throttled to 1 second)
        // This prevents creating 100 records/sec on Desktop
        if (_lastLocalSaveTime == null ||
            now.difference(_lastLocalSaveTime!).inSeconds >= 1) {
          _lastLocalSaveTime = now;
          await _saveToHistory(isar, packet, userId);
        }

        // B. Upload to Cloud (Throttled to 5 seconds)
        if (_lastCloudUploadTime == null ||
            now.difference(_lastCloudUploadTime!).inSeconds >= 5) {
          _lastCloudUploadTime = now;

          final uploadId = user.firebaseId ?? userId.toString();
          syncService.uploadVital(uploadId, packet);
        }
      }
    }

    // 4. Yield Data
    yield _lastValidPacket ?? _createEmptyPacket();
  }
}

// [HELPER] Save to Local Database
Future<void> _saveToHistory(Isar isar, SerialPacket packet, int userId) async {
  try {
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
  } catch (e) {
    debugPrint("History Save Error: $e");
  }
}

// [NEW] Manually clear history for a user
@riverpod
Future<void> clearUserHistory(ClearUserHistoryRef ref, int userId) async {
  final isar = await ref.read(isarProvider.future);
  await isar.writeTxn(() async {
    await isar.vitalLogEntitys.filter().userIdEqualTo(userId).deleteAll();
  });
}
