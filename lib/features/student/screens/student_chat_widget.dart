import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gap/gap.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudentChatWidget extends StatefulWidget {
  const StudentChatWidget({super.key});

  @override
  State<StudentChatWidget> createState() => _StudentChatWidgetState();
}

class _StudentChatWidgetState extends State<StudentChatWidget> {
  final _messageController = TextEditingController();
  String? _studentId;

  @override
  void initState() {
    super.initState();
    _loadId();
  }

  Future<void> _loadId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentId = prefs.getString('student_id');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_studentId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final messageStream = FirebaseFirestore.instance
        .collection('users')
        .doc(_studentId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: messageStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text("Error: ${snapshot.error}"));
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text("No messages yet."));
              }

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final isMe = data['sender'] == 'student';
                  final text = data['text'] ?? '';

                  return Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.indigo : Colors.grey[200],
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: isMe
                              ? const Radius.circular(12)
                              : Radius.zero,
                          bottomRight: isMe
                              ? Radius.zero
                              : const Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        text,
                        style: TextStyle(
                          color: isMe ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: "Type a message...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
              const Gap(8),
              CircleAvatar(
                backgroundColor: Colors.indigo,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _studentId == null) return;

    _messageController.clear();

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_studentId)
          .collection('messages')
          .add({
            'text': text,
            'sender': 'student',
            'timestamp': FieldValue.serverTimestamp(),
            'read': false,
          });
    } catch (e) {
      // ignore: avoid_print
      print("Error sending message: $e");
    }
  }
}
