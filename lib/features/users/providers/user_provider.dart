import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:english_words/english_words.dart';
import 'package:isar/isar.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/user_entity.dart';
import '../../../core/database/vital_log_entity.dart';
import '../../../core/providers.dart';

part 'user_provider.g.dart';

@riverpod
class UserNotifier extends _$UserNotifier {
  @override
  Stream<List<UserEntity>> build() async* {
    final db = await ref.watch(isarProvider.future);
    yield* db.userEntitys.where().watch(fireImmediately: true);
  }

  String _generateTwoWordCode() {
    final pair = WordPair.random();
    return "${pair.first.toLowerCase()}-${pair.second.toLowerCase()}";
  }

  // --- 1. ADD USER (Returns the created user now) ---
  Future<UserEntity> addUser({
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

    final duplicate = await db.userEntitys
        .filter()
        .studentIdEqualTo(studentId)
        .findFirst();
    if (duplicate != null) {
      throw Exception("Student ID '$studentId' is already taken.");
    }

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
      ..medicalInfo = medicalInfo
      ..generatedPassword = _generateTwoWordCode()
      ..pairedDeviceMacAddress = null;

    await db.writeTxn(() async {
      await db.userEntitys.put(newUser);
    });

    // [FIX] Return the user object so UI doesn't have to search for it
    return newUser;
  }

  // --- 2. UPDATE USER ---
  Future<void> updateUser({
    required int id,
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

    final existingUser = await db.userEntitys.get(id);
    final currentMac = existingUser?.pairedDeviceMacAddress;
    final currentPass =
        existingUser?.generatedPassword ?? _generateTwoWordCode();
    final currentFirebaseId = existingUser?.firebaseId;

    final duplicate = await db.userEntitys
        .filter()
        .studentIdEqualTo(studentId)
        .findFirst();

    if (duplicate != null && duplicate.id != id) {
      throw Exception("Student ID '$studentId' is already taken.");
    }

    final updatedUser = UserEntity()
      ..id = id
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
      ..generatedPassword = currentPass
      ..firebaseId = currentFirebaseId
      ..pairedDeviceMacAddress = currentMac;

    await db.writeTxn(() async {
      await db.userEntitys.put(updatedUser);
    });

    if (currentFirebaseId != null) {
      await _syncProfileToCloud(updatedUser, currentFirebaseId);
    }
  }

  // --- DELETE USER ---
  Future<void> deleteUser(int id) async {
    final db = await ref.read(isarProvider.future);

    final userToDelete = await db.userEntitys.get(id);
    if (userToDelete == null) return;

    final firebaseId = userToDelete.firebaseId;

    await db.writeTxn(() async {
      await db.vitalLogEntitys.filter().userIdEqualTo(id).deleteAll();

      await db.userEntitys.delete(id);
    });

    if (firebaseId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseId)
            .delete();
      } catch (e) {
        // ignore: avoid_print
        print("Cloud delete failed: $e");
      }
    }
  }

  // --- CLEAR HISTORY ---
  Future<void> clearUserHistory(int userId) async {
    final db = await ref.read(isarProvider.future);
    final user = await db.userEntitys.get(userId);

    await db.writeTxn(() async {
      await db.vitalLogEntitys.filter().userIdEqualTo(userId).deleteAll();
    });

    if (user?.firebaseId != null) {
      try {
        final userDoc = FirebaseFirestore.instance
            .collection('users')
            .doc(user!.firebaseId);
        await userDoc.collection('vitals').doc('latest').delete();

        final historySnapshot = await userDoc.collection('history').get();
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in historySnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } catch (e) {
        // ignore: avoid_print
        print("Cloud history clear failed: $e");
      }
    }
  }

  // --- HELPERS ---
  Future<void> updateFirebaseId(int localId, String fId) async {
    final db = await ref.read(isarProvider.future);
    UserEntity? user;

    await db.writeTxn(() async {
      user = await db.userEntitys.get(localId);
      if (user != null) {
        user!.firebaseId = fId;
        await db.userEntitys.put(user!);
      }
    });

    if (user != null) {
      await _syncProfileToCloud(user!, fId);
    }
  }

  Future<void> _syncProfileToCloud(UserEntity user, String fId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(fId).update({
        'name': "${user.firstName} ${user.lastName}",
        'role': user.role,
        'yearLevel': user.yearLevel,
        'section': user.section,
        'studentId': user.studentId,
        'height': user.height,
        'weight': user.weight,
        'bloodType': user.bloodType,
        'medicalInfo': user.medicalInfo,
      });
    } catch (e) {
      // ignore: avoid_print
      print("Error syncing profile to cloud: $e");
    }
  }

  // --- PAIRING ---
  Future<void> unpairUser(int userId) async {
    final db = await ref.read(isarProvider.future);
    await db.writeTxn(() async {
      final user = await db.userEntitys.get(userId);
      if (user != null) {
        user.pairedDeviceMacAddress = null;
        await db.userEntitys.put(user);

        if (user.firebaseId != null) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.firebaseId)
                .update({'pairedDevice': null});
          } catch (e) {
            // ignore: avoid_print
            print("Cloud unpair failed: $e");
          }
        }
      }
    });
  }

  Future<void> pairUserWithDevice(int userId, String macAddress) async {
    final db = await ref.read(isarProvider.future);
    await db.writeTxn(() async {
      final user = await db.userEntitys.get(userId);
      if (user != null) {
        user.pairedDeviceMacAddress = macAddress;
        await db.userEntitys.put(user);

        if (user.firebaseId != null) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.firebaseId)
                .update({'pairedDevice': macAddress});
          } catch (e) {
            // ignore: avoid_print
            print("Cloud pair failed: $e");
          }
        }
      }
    });
  }

  // --- REGENERATE PASSWORD ---
  Future<void> regenerateUserPassword(int userId) async {
    final db = await ref.read(isarProvider.future);
    final syncService = ref.read(syncServiceProvider);
    final user = await db.userEntitys.get(userId);

    if (user != null) {
      final newPassword = _generateTwoWordCode();
      user.generatedPassword = newPassword;

      await db.writeTxn(() async {
        await db.userEntitys.put(user);
      });

      if (user.firebaseId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.firebaseId)
              .update({'generatedPassword': newPassword});
        } catch (e) {
          // ignore: avoid_print
          print("Cloud update failed: $e");
        }
      } else {
        try {
          final newFirebaseId = await syncService.registerUserInCloud(
            user.studentId,
            "${user.firstName} ${user.lastName}",
            newPassword,
          );
          await updateFirebaseId(user.id, newFirebaseId);
        } catch (e) {
          // ignore: avoid_print
          print("Cloud registration failed: $e");
        }
      }
    }
  }
}
