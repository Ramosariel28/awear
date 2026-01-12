import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

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
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              // --- UPDATED MENU BUTTON ---
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'edit') {
                    // Open Dialog in Edit Mode
                    showDialog(
                      context: context,
                      builder: (_) => UserRegistrationDialog(userToEdit: user),
                    );
                  } else if (value == 'delete') {
                    // Confirm Delete
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Delete User"),
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
                              // 1. Delete user
                              ref
                                  .read(userNotifierProvider.notifier)
                                  .deleteUser(user.id);
                              // 2. Clear selection (so Dashboard goes back to empty state)
                              ref.read(selectedUserIdProvider.notifier).clear();
                              // 3. Close dialog
                              Navigator.pop(ctx);
                            },
                            child: const Text(
                              "Delete",
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
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
              // ---------------------------
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

          // --- Bottom Buttons (Pair/Unpair) ---
          const Divider(),
          const Gap(10),
          if (user.pairedDeviceMacAddress == null)
            ElevatedButton.icon(
              onPressed: () {
                // Switch Column 3 to the "Pair User Screen"
                ref.read(isPairingUserProvider.notifier).set(true);
              },
              icon: const Icon(Icons.link),
              label: const Text("Pair User"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(userNotifierProvider.notifier)
                    .unpairUser(user.id);
              },
              icon: const Icon(Icons.link_off),
              label: const Text("Unpair User"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
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
}
