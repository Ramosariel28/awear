import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import '../../../core/database/user_entity.dart';
import '../../../core/providers.dart'; // [REQUIRED] For syncServiceProvider
import '../providers/user_provider.dart';

class UserRegistrationDialog extends ConsumerStatefulWidget {
  final UserEntity? userToEdit;

  const UserRegistrationDialog({super.key, this.userToEdit});

  @override
  ConsumerState<UserRegistrationDialog> createState() =>
      _UserRegistrationDialogState();
}

class _UserRegistrationDialogState
    extends ConsumerState<UserRegistrationDialog> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _medicalCtrl = TextEditingController();

  // --- DROPDOWN STATE ---
  String _selectedRole = 'Student';
  DateTime _dob = DateTime(2000, 1, 1);
  String? _idErrorText;

  // Strand/Year/Section State
  String? _strandError;
  String? _yearError;
  String? _sectionError;

  String? _selectedStrand;
  String? _selectedYear;
  String? _selectedSection;

  // Blood Type State
  String? _selectedBloodType;
  final List<String> _bloodTypes = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  final Map<String, Map<String, List<String>>> _strandData = {
    'STEM': {
      '11': ['01', '03', '10'],
      '12': ['02', '07', '09'],
    },
    'ICT': {
      '11': ['01', '02'],
    },
    'HUMSS': {
      '11': ['01'],
      '12': ['02'],
    },
  };

  @override
  void initState() {
    super.initState();

    _studentIdCtrl.addListener(() {
      if (_idErrorText != null) {
        setState(() => _idErrorText = null);
      }
    });

    if (widget.userToEdit != null) {
      _prefillData(widget.userToEdit!);
    }
  }

  void _prefillData(UserEntity u) {
    _firstNameCtrl.text = u.firstName;
    _lastNameCtrl.text = u.lastName;
    _studentIdCtrl.text = u.studentId;
    _heightCtrl.text = u.height?.toString() ?? '';
    _weightCtrl.text = u.weight?.toString() ?? '';
    _medicalCtrl.text = u.medicalInfo ?? '';
    _selectedRole = u.role;
    _dob = u.dateOfBirth;

    if (u.bloodType != null && _bloodTypes.contains(u.bloodType)) {
      _selectedBloodType = u.bloodType;
    }

    final parts = u.section.split(' ');
    if (parts.isNotEmpty && _strandData.containsKey(parts[0])) {
      _selectedStrand = parts[0];
      _selectedYear = u.yearLevel;
      if (parts.length > 1 && parts[1].contains('-')) {
        _selectedSection = parts[1].split('-')[1];
      }
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _studentIdCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _medicalCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _idErrorText = null;
      _strandError = null;
      _yearError = null;
      _sectionError = null;
    });

    bool isValid = _formKey.currentState!.validate();
    bool dropdownsValid = true;

    if (_selectedStrand == null) {
      setState(() => _strandError = "Required");
      dropdownsValid = false;
    }
    if (_selectedYear == null) {
      setState(() => _yearError = "Required");
      dropdownsValid = false;
    }
    if (_selectedSection == null) {
      setState(() => _sectionError = "Required");
      dropdownsValid = false;
    }

    if (isValid && dropdownsValid) {
      final fullSectionName =
          "$_selectedStrand $_selectedYear-$_selectedSection";
      final notifier = ref.read(userNotifierProvider.notifier);
      final syncService = ref.read(
        syncServiceProvider,
      ); // [NEW] Get Sync Service

      try {
        if (widget.userToEdit == null) {
          // --- CREATE MODE ---

          // 1. Add to Local Database (Generates 'happy-lion' password)
          await notifier.addUser(
            firstName: _firstNameCtrl.text,
            lastName: _lastNameCtrl.text,
            studentId: _studentIdCtrl.text,
            yearLevel: _selectedYear!,
            section: fullSectionName,
            role: _selectedRole,
            dob: _dob,
            height: double.tryParse(_heightCtrl.text),
            weight: double.tryParse(_weightCtrl.text),
            bloodType: _selectedBloodType,
            medicalInfo: _medicalCtrl.text.isEmpty ? null : _medicalCtrl.text,
          );

          // 2. [NEW] Fetch the user we just created to get the password
          final allUsers = await ref.read(userNotifierProvider.future);
          final createdUser = allUsers.firstWhere(
            (u) => u.studentId == _studentIdCtrl.text,
          );

          // 3. [NEW] Register in Cloud (Firebase)
          if (createdUser.generatedPassword != null) {
            final firebaseId = await syncService.registerUserInCloud(
              createdUser.studentId,
              "${createdUser.firstName} ${createdUser.lastName}",
              createdUser.generatedPassword!,
            );

            // 4. [NEW] Save Firebase ID back to Local DB
            await notifier.updateFirebaseId(createdUser.id, firebaseId);
          }
        } else {
          // --- EDIT MODE ---
          await notifier.updateUser(
            id: widget.userToEdit!.id,
            firstName: _firstNameCtrl.text,
            lastName: _lastNameCtrl.text,
            studentId: _studentIdCtrl.text,
            yearLevel: _selectedYear!,
            section: fullSectionName,
            role: _selectedRole,
            dob: _dob,
            height: double.tryParse(_heightCtrl.text),
            weight: double.tryParse(_weightCtrl.text),
            bloodType: _selectedBloodType,
            medicalInfo: _medicalCtrl.text.isEmpty ? null : _medicalCtrl.text,
            // currentMacAddress is handled internally by provider now
          );
        }

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("User saved & synced successfully!"),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        final errorMsg = e.toString();
        if (errorMsg.contains("Student ID")) {
          setState(() => _idErrorText = "This Student ID is already taken.");
        } else {
          if (mounted) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Error"),
                content: Text(errorMsg.replaceAll("Exception: ", "")),
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.userToEdit != null;

    final availableYears = _selectedStrand != null
        ? _strandData[_selectedStrand]!.keys.toList()
        : <String>[];

    final availableSections = (_selectedStrand != null && _selectedYear != null)
        ? _strandData[_selectedStrand]![_selectedYear] ?? []
        : <String>[];

    return AlertDialog(
      title: Text(
        isEditing ? "Edit User" : "Register User",
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Personal Details",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField("First Name", _firstNameCtrl),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _buildTextField("Last Name", _lastNameCtrl),
                    ),
                  ],
                ),
                _buildTextField(
                  "Student ID",
                  _studentIdCtrl,
                  serverError: _idErrorText,
                ),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: "Role",
                          border: OutlineInputBorder(),
                        ),
                        items: ["Student", "Faculty", "Staff"]
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedRole = val!),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Date of Birth",
                            border: OutlineInputBorder(),
                          ),
                          child: Text(DateFormat('yyyy-MM-dd').format(_dob)),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(20),

                const Text(
                  "Academic Details",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const Divider(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedStrand,
                        decoration: InputDecoration(
                          labelText: "Strand",
                          border: const OutlineInputBorder(),
                          errorText: _strandError,
                        ),
                        items: _strandData.keys
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedStrand = val;
                            _selectedYear = null;
                            _selectedSection = null;
                            _strandError = null;
                          });
                        },
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedYear,
                        decoration: InputDecoration(
                          labelText: "Year",
                          border: const OutlineInputBorder(),
                          errorText: _yearError,
                        ),
                        items: availableYears
                            .map(
                              (y) => DropdownMenuItem(value: y, child: Text(y)),
                            )
                            .toList(),
                        onChanged: (val) {
                          setState(() {
                            _selectedYear = val;
                            _selectedSection = null;
                            _yearError = null;
                          });
                        },
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedSection,
                        decoration: InputDecoration(
                          labelText: "Section",
                          border: const OutlineInputBorder(),
                          errorText: _sectionError,
                        ),
                        items: availableSections
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (val) => setState(() {
                          _selectedSection = val;
                          _sectionError = null;
                        }),
                      ),
                    ),
                  ],
                ),

                const Gap(20),
                const Text(
                  "Medical Information (Optional)",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        "Height (cm)",
                        _heightCtrl,
                        isNumber: true,
                        required: false,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _buildTextField(
                        "Weight (kg)",
                        _weightCtrl,
                        isNumber: true,
                        required: false,
                      ),
                    ),
                  ],
                ),

                // Blood Type Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedBloodType,
                  decoration: const InputDecoration(
                    labelText: "Blood Type",
                    border: OutlineInputBorder(),
                  ),
                  items: _bloodTypes
                      .map((bt) => DropdownMenuItem(value: bt, child: Text(bt)))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedBloodType = val),
                ),
                const Gap(12),

                _buildTextField(
                  "Medical Notes",
                  _medicalCtrl,
                  required: false,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(isEditing ? "Update" : "Register"),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
    bool required = true,
    int maxLines = 1,
    String? serverError,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorText: serverError,
        ),
        validator: (value) {
          if (required && (value == null || value.isEmpty)) {
            return "Required";
          }
          return null;
        },
      ),
    );
  }
}
