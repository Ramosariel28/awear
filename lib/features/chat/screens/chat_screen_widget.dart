import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/providers.dart';
import '../../users/providers/user_provider.dart';
import '../../dashboard/providers/selection_providers.dart';
import '../providers/chat_providers.dart';

class ChatScreenWidget extends ConsumerStatefulWidget {
  const ChatScreenWidget({super.key});

  @override
  ConsumerState<ChatScreenWidget> createState() => _ChatScreenWidgetState();
}

class _ChatScreenWidgetState extends ConsumerState<ChatScreenWidget> {
  final TextEditingController _msgController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final selectedId = ref.watch(selectedUserIdProvider);
    final userList = ref.watch(userNotifierProvider).valueOrNull ?? [];

    if (selectedId == null) return const Center(child: Text("Select a User"));

    final user = userList.where((u) => u.id == selectedId).firstOrNull;
    if (user == null) return const SizedBox();

    // Use firebaseId if available, otherwise fallback
    final uploadId = user.firebaseId ?? user.id.toString();
    final messagesAsync = ref.watch(chatMessagesProvider(uploadId));

    // [NEW] Automatically mark messages as read while viewing this screen
    ref.listen(chatMessagesProvider(uploadId), (previous, next) {
      if (next.valueOrNull != null && next.value!.isNotEmpty) {
        // If we received data, tell the sync service to clear unread status
        ref.read(syncServiceProvider).markStudentMessagesAsRead(uploadId);
      }
    });

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // --- HEADER ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 5,
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.indigo,
                  child: Text(
                    user.firstName[0],
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "${user.firstName} ${user.lastName}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      // --- PASSWORD ROW ---
                      Row(
                        children: [
                          const Icon(
                            Icons.vpn_key,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const Gap(4),
                          SelectableText(
                            user.generatedPassword ?? "No Code",
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo[700],
                              fontSize: 13,
                            ),
                          ),
                          const Gap(8),
                          // REGENERATE BUTTON
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.refresh,
                                size: 16,
                                color: Colors.grey,
                              ),
                              tooltip: "Regenerate & Sync",
                              onPressed: () {
                                _confirmRegenerate(context, ref, user.id);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    ref
                        .read(userDetailViewModeProvider.notifier)
                        .set(UserDetailView.vitals);
                  },
                ),
              ],
            ),
          ),

          // --- MESSAGE LIST ---
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text("No messages yet"));
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final data = msg.data() as Map<String, dynamic>;
                    final sender = data['sender'] ?? 'unknown';
                    final text = data['text'] ?? '';

                    final timestamp = data['timestamp'] as Timestamp?;
                    final timeStr = timestamp != null
                        ? "${timestamp.toDate().hour}:${timestamp.toDate().minute.toString().padLeft(2, '0')}"
                        : "";

                    final isMe = sender == 'admin';

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue[100] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(text),
                            if (timeStr.isNotEmpty)
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // --- INPUT AREA ---
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[50],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      hintText: "Type a message...",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(uploadId),
                  ),
                ),
                const Gap(8),
                IconButton.filled(
                  onPressed: () => _sendMessage(uploadId),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(String userId) {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    ref.read(syncServiceProvider).sendAdminMessage(userId, text);
    _msgController.clear();
  }

  void _confirmRegenerate(BuildContext context, WidgetRef ref, int userId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reset Student Password?"),
        content: const Text(
          "This will disconnect the student from their mobile app.\n\n"
          "If this user was created before the cloud feature, clicking this will register them to the cloud now.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(userNotifierProvider.notifier)
                  .regenerateUserPassword(userId);
              Navigator.of(ctx).pop();
            },
            child: const Text(
              "Regenerate & Register",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
