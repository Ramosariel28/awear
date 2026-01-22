import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../dashboard/providers/selection_providers.dart';
import '../../dashboard/providers/view_mode_provider.dart';
import '../providers/user_provider.dart';
import 'user_registration_dialog.dart';

class UserListWidget extends ConsumerWidget {
  const UserListWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1. Watch the database for changes
    final userState = ref.watch(userNotifierProvider);
    // 2. Watch who is currently selected (to highlight the card)
    final selectedId = ref.watch(selectedUserIdProvider);
    // 3. Watch the current View Mode (to highlight the Devices button)
    final viewMode = ref.watch(dashboardViewModeProvider);

    return Column(
      children: [
        // --- Header Section ---
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const UserRegistrationDialog(),
                  );
                },
                icon: const Icon(Icons.person_add),
                label: const Text("Register User"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                ),
              ),
              const Gap(8),

              // --- DEVICES BUTTON ---
              OutlinedButton.icon(
                onPressed: () {
                  // 1. Clear any selected user so the UI state is clean
                  ref.read(selectedUserIdProvider.notifier).clear();

                  // 2. Switch the AppShell to "Devices Mode"
                  ref
                      .read(dashboardViewModeProvider.notifier)
                      .setMode(DashboardMode.devices);
                },
                // Highlight this button if we are currently in Devices Mode
                style: viewMode == DashboardMode.devices
                    ? OutlinedButton.styleFrom(
                        backgroundColor: Colors.blue[50],
                        side: const BorderSide(color: Colors.blue),
                      )
                    : null,
                icon: const Icon(Icons.usb),
                label: const Text("Devices"),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // --- List Section ---
        Expanded(
          child: userState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text("Error: $e")),
            data: (users) {
              if (users.isEmpty) {
                return const Center(child: Text("No users found"));
              }

              return ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  final isSelected = user.id == selectedId;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    elevation: isSelected ? 4 : 1,
                    color: isSelected ? Colors.indigo[50] : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isSelected
                          ? const BorderSide(color: Colors.indigo, width: 2)
                          : BorderSide.none,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Text(
                        "${user.firstName} ${user.lastName}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text("${user.role} • ${user.yearLevel}"),

                      // [NEW] Badge Widget
                      trailing: StreamBuilder<QuerySnapshot>(
                        stream: user.firebaseId == null
                            ? const Stream.empty()
                            : FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.firebaseId)
                                  .collection('messages')
                                  .where(
                                    'sender',
                                    isEqualTo: 'student',
                                  ) // From Student
                                  .where('read', isEqualTo: false) // Unread
                                  .snapshots(),
                        builder: (context, snapshot) {
                          int unreadCount = 0;
                          if (snapshot.hasData) {
                            unreadCount = snapshot.data!.docs.length;
                          }

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                user.section,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (unreadCount > 0) ...[
                                const Gap(8),
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    unreadCount > 9
                                        ? "9+"
                                        : unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),

                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo[100],
                        child: Text(
                          user.firstName.isNotEmpty ? user.firstName[0] : "?",
                        ),
                      ),

                      onTap: () {
                        ref.read(isPairingUserProvider.notifier).set(false);
                        ref.read(selectedVitalProvider.notifier).clear();
                        ref
                            .read(selectedUserIdProvider.notifier)
                            .select(user.id);
                        ref
                            .read(dashboardViewModeProvider.notifier)
                            .setMode(DashboardMode.users);
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
