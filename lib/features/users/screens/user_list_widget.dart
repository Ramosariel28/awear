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
    final userState = ref.watch(userNotifierProvider);
    final selectedId = ref.watch(selectedUserIdProvider);
    final viewMode = ref.watch(dashboardViewModeProvider);

    // Use a Stack to position the Floating Action Button
    return Stack(
      children: [
        Column(
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
                  OutlinedButton.icon(
                    onPressed: () {
                      ref.read(selectedUserIdProvider.notifier).clear();
                      ref
                          .read(dashboardViewModeProvider.notifier)
                          .setMode(DashboardMode.devices);
                    },
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
                    // Add padding at bottom so FAB doesn't cover last item
                    padding: const EdgeInsets.only(bottom: 80),
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
                          trailing: StreamBuilder<QuerySnapshot>(
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
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    user.section,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
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
                              user.firstName.isNotEmpty
                                  ? user.firstName[0]
                                  : "?",
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
        ),

        // --- ABOUT BUTTON ---
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.small(
            heroTag: "desktop_about_btn",
            onPressed: () => _showAboutDialog(context),
            backgroundColor: Colors.red[300],
            foregroundColor: Colors.white,
            tooltip: "About AWEAR",
            child: const Icon(Icons.question_mark),
          ),
        ),
      ],
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.indigo),
            Gap(10),
            Text("About"),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "AWEAR 1.0.0",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                "Awareness You Can Wear, Because We Care",
                style: TextStyle(
                  fontStyle: FontStyle.normal,
                  color: Colors.grey,
                ),
              ),
              Divider(height: 30),
              Text(
                "Brought to you by Group 5:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Gap(8),
              Text("Alumbro, Mary Jellianne B."),
              Text("Banio, Stephanie Grace L."),
              Text("Baylas, Kizza S."),
              Text("Diokno, Lance Gian G."),
              Text("Sagritalo, Aicee Janelle M."),
              Divider(height: 30),
              Text(
                "UPHSD Molino | A.Y. '25-'26",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Gap(4),
              Text(
                "AWear: An IoT-Enabled Wearable for Real-Time Monitoring",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
              Text(
                "of Student Health in the UPHSD Molino Campus Clinic",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }
}
