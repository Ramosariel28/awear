import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:badges/badges.dart' as badges;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/providers.dart';
import '../providers/user_provider.dart';
import '../../dashboard/providers/selection_providers.dart';
import 'user_registration_dialog.dart';

class UserInformationWidget extends ConsumerWidget {
  const UserInformationWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedUserIdProvider);
    final userList = ref.watch(userNotifierProvider).valueOrNull ?? [];

    if (selectedId == null) return const Center(child: Text("Select a User"));

    final user = userList.where((u) => u.id == selectedId).firstOrNull;
    if (user == null) return const Center(child: Text("User not found"));

    return Container(
      color: Colors.grey[50],
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- Header ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "User Information",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'edit') {
                    showDialog(
                      context: context,
                      builder: (_) => UserRegistrationDialog(userToEdit: user),
                    );
                  } else if (value == 'clear_history') {
                    _showClearHistoryConfirm(context, ref, user);
                  } else if (value == 'delete') {
                    _showDeleteConfirm(context, ref, user);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, color: Colors.blue),
                        Gap(10),
                        Text("Edit Info"),
                      ],
                    ),
                  ),
                  // [NEW] Clear History Option
                  const PopupMenuItem(
                    value: 'clear_history',
                    child: Row(
                      children: [
                        Icon(Icons.history, color: Colors.orange),
                        Gap(10),
                        Text("Clear Vital History"),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        Gap(10),
                        Text("Delete User"),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(),
          const Gap(10),

          // --- Details List ---
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildInfoRow(
                    "Full Name",
                    "${user.lastName}, ${user.firstName}",
                  ),
                  _buildInfoRow("Student ID", user.studentId),
                  _buildInfoRow("Role", user.role),
                  _buildInfoRow("Year & Section", user.section),
                  _buildInfoRow(
                    "Date of Birth",
                    DateFormat('yyyy-MM-dd').format(user.dateOfBirth),
                  ),
                  const Gap(20),
                  const Text(
                    "Medical Info",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _buildInfoRow("Height", "${user.height ?? '--'} cm"),
                  _buildInfoRow("Weight", "${user.weight ?? '--'} kg"),
                  _buildInfoRow("Blood Type", user.bloodType ?? '--'),
                  _buildInfoRow("Notes", user.medicalInfo ?? 'None'),
                  const Gap(20),
                  const Text(
                    "Device Connection",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _buildInfoRow(
                    "Paired MAC",
                    user.pairedDeviceMacAddress ?? "Not Paired",
                  ),
                ],
              ),
            ),
          ),

          // --- Bottom Buttons (Chat & Pair) ---
          const Divider(),
          const Gap(10),

          // StreamBuilder to get real-time unread count
          StreamBuilder<QuerySnapshot>(
            stream: user.firebaseId == null
                ? const Stream.empty()
                : FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.firebaseId)
                      .collection('messages')
                      .where('sender', isEqualTo: 'student')
                      .where('read', isEqualTo: false)
                      .snapshots(),
            builder: (context, snapshot) {
              int unreadCount = 0;
              if (snapshot.hasData) {
                unreadCount = snapshot.data!.docs.length;
              }

              return Row(
                children: [
                  // 1. Chat Button with Badge
                  Expanded(
                    child: badges.Badge(
                      position: badges.BadgePosition.topEnd(top: -10, end: -5),
                      showBadge: unreadCount > 0,
                      badgeContent: Text(
                        unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                      child: SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text("Chat"),
                          onPressed: () {
                            if (user.firebaseId != null) {
                              ref
                                  .read(syncServiceProvider)
                                  .markStudentMessagesAsRead(user.firebaseId!);
                            }
                            ref
                                .read(userDetailViewModeProvider.notifier)
                                .set(UserDetailView.chat);
                          },
                        ),
                      ),
                    ),
                  ),

                  const Gap(12),

                  // 2. Pair/Unpair Button
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: user.pairedDeviceMacAddress == null
                          ? ElevatedButton.icon(
                              onPressed: () {
                                ref
                                    .read(isPairingUserProvider.notifier)
                                    .set(true);
                              },
                              icon: const Icon(Icons.link),
                              label: const Text("Pair"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: () async {
                                await ref
                                    .read(userNotifierProvider.notifier)
                                    .unpairUser(user.id);
                              },
                              icon: const Icon(Icons.link_off),
                              label: const Text("Unpair"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  // [NEW] Clear History Confirmation Dialog
  void _showClearHistoryConfirm(
    BuildContext context,
    WidgetRef ref,
    dynamic user,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Clear Vital History?"),
        content: Text(
          "This will permanently delete all recorded vital logs for ${user.firstName} ${user.lastName}. This action cannot be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              ref.read(userNotifierProvider.notifier).clearUserHistory(user.id);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Vital history cleared")),
              );
            },
            child: const Text("Clear All", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref, dynamic user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "Delete User",
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        content: Text(
          "Are you sure you want to delete ${user.firstName} ${user.lastName}?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              ref.read(userNotifierProvider.notifier).deleteUser(user.id);
              ref.read(selectedUserIdProvider.notifier).clear();
              Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
