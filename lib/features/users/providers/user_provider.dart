import 'dart:async';
import 'package:isar/isar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/user_entity.dart';
import '../../../core/providers.dart';

part 'user_provider.g.dart';

@riverpod
class UserNotifier extends _$UserNotifier {
  @override
  Stream<List<UserEntity>> build() async* {
    // 1. Get the database
    final db = await ref.watch(isarProvider.future);

    // 2. Yield the stream directly
    // This is the cleanest way to watch DB changes
    yield* db.userEntitys.where().watch(fireImmediately: true);
  }

  /// Add a new User
  Future<void> addUser({
    required String firstName,
    required String lastName,
    required String studentId,
    required String yearLevel,
    required String section,
    required String role,
    required DateTime dob,
    double? height,
    double? weight,
    String? bloodType,
    String? medicalInfo,
  }) async {
    final db = await ref.read(isarProvider.future);

    // 1. VALIDATION: Check if ID exists
    final duplicate = await db.userEntitys
        .filter()
        .studentIdEqualTo(studentId)
        .findFirst();
    if (duplicate != null) {
      throw Exception("Student ID '$studentId' is already taken.");
    }

    // 2. Proceed if safe
    final newUser = UserEntity()
      ..firstName = firstName
      ..lastName = lastName
      ..studentId = studentId
      ..yearLevel = yearLevel
      ..section = section
      ..role = role
      ..dateOfBirth = dob
      ..height = height
      ..weight = weight
      ..bloodType = bloodType
      ..medicalInfo = medicalInfo;

    await db.writeTxn(() async {
      await db.userEntitys.put(newUser);
    });
  }

  /// Update an existing User
  Future<void> updateUser({
    required int id, // <--- ID is required to find the specific user
    required String firstName,
    required String lastName,
    required String studentId,
    required String yearLevel,
    required String section,
    required String role,
    required DateTime dob,
    double? height,
    double? weight,
    String? bloodType,
    String? medicalInfo,
    String? currentMacAddress, // Preserve the pairing!
  }) async {
    final db = await ref.read(isarProvider.future);

    // 1. VALIDATION: Check if ID exists AND belongs to someone else
    final duplicate = await db.userEntitys
        .filter()
        .studentIdEqualTo(studentId)
        .findFirst();

    // Logic: If we found a user with this Student ID, AND it is NOT the user we are currently editing
    if (duplicate != null && duplicate.id != id) {
      throw Exception(
        "Student ID '$studentId' is already taken by another user.",
      );
    }

    final updatedUser = UserEntity()
      ..id =
          id // Set the ID so Isar knows to UPDATE, not Insert
      ..firstName = firstName
      ..lastName = lastName
      ..studentId = studentId
      ..yearLevel = yearLevel
      ..section = section
      ..role = role
      ..dateOfBirth = dob
      ..height = height
      ..weight = weight
      ..bloodType = bloodType
      ..medicalInfo = medicalInfo
      ..pairedDeviceMacAddress = currentMacAddress; // Keep connection

    await db.writeTxn(() async {
      await db.userEntitys.put(updatedUser);
    });
  }

  /// Delete a User
  Future<void> deleteUser(int id) async {
    final db = await ref.read(isarProvider.future);
    await db.writeTxn(() async {
      await db.userEntitys.delete(id);
    });
  }

  // Unpair User
  Future<void> unpairUser(int userId) async {
    final db = await ref.read(isarProvider.future);
    await db.writeTxn(() async {
      final user = await db.userEntitys.get(userId);
      if (user != null) {
        user.pairedDeviceMacAddress = null;
        await db.userEntitys.put(user);
      }
    });
  }

  // Pair User
  Future<void> pairUserWithDevice(int userId, String macAddress) async {
    final db = await ref.read(isarProvider.future);
    await db.writeTxn(() async {
      final user = await db.userEntitys.get(userId);
      if (user != null) {
        user.pairedDeviceMacAddress = macAddress;
        await db.userEntitys.put(user);
      }
    });
  }
}
