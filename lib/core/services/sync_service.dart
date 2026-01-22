import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../serial/serial_packet.dart';

class SyncService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. Silent Admin Login
  Future<void> loginAsAdmin() async {
    try {
      if (_auth.currentUser == null) {
        await _auth.signInWithEmailAndPassword(
          email: "admin@awear.system",
          password: "admin123",
        );
        print("SYNC: Admin Logged In");
      }
    } catch (e) {
      print("SYNC: Admin login failed: $e");
    }
  }

  // 2. Register Student
  Future<String> registerUserInCloud(
    String studentId,
    String fullName,
    String password,
  ) async {
    final docRef = await _db.collection('users').add({
      'studentId': studentId,
      'name': fullName,
      'generatedPassword': password,
      'createdAt': FieldValue.serverTimestamp(),
      'isOnline': false,
      // Default fields to prevent null errors on mobile
      'role': 'Student',
      'yearLevel': 'Grade 11',
      'section': 'General',
    });
    return docRef.id;
  }

  // 3. Upload Vital (Now with History & RR)
  Future<void> uploadVital(String studentId, SerialPacket packet) async {
    try {
      final data = {
        'hr': packet.heartRate,
        'oxy': packet.oxygen,
        'rr': packet.respirationRate,
        'temp': packet.temperature,
        'stress': packet.stress,
        'motion': packet.motion,
        'timestamp': FieldValue.serverTimestamp(),
      };

      // A. Update "Latest" (For the live cards)
      await _db
          .collection('users')
          .doc(studentId)
          .collection('vitals')
          .doc('latest')
          .set(data);

      // B. Add to "History" (For the graph)
      // We perform this write to allow the mobile app to show trends
      await _db
          .collection('users')
          .doc(studentId)
          .collection('history')
          .add(data);
    } catch (e) {
      print("SYNC: Upload failed: $e");
    }
  }

  // 4. Send Message
  Future<void> sendAdminMessage(String studentId, String message) async {
    await _db.collection('users').doc(studentId).collection('messages').add({
      'sender': 'admin',
      'text': message,
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  // 5. Admin reads Student's messages
  Future<void> markStudentMessagesAsRead(String studentId) async {
    final snapshot = await _db
        .collection('users')
        .doc(studentId)
        .collection('messages')
        .where('sender', isEqualTo: 'student')
        .where('read', isEqualTo: false)
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.update({'read': true});
    }
  }

  // 6. Student reads Admin's messages
  Future<void> markAdminMessagesAsRead(String studentId) async {
    final snapshot = await _db
        .collection('users')
        .doc(studentId)
        .collection('messages')
        .where('sender', isEqualTo: 'admin')
        .where('read', isEqualTo: false)
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.update({'read': true});
    }
  }
}
