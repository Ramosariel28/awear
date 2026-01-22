import 'package:isar/isar.dart';

part 'user_entity.g.dart';

@collection
class UserEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String studentId; // Unique ID for school

  late String firstName;
  late String lastName;

  // Demographics
  late String yearLevel; // e.g., "Grade 12"
  late String section; // e.g., "Rizal"
  late String role; // "Student" or "Teacher"
  late DateTime dateOfBirth;

  // Medical Info
  double? weight;
  double? height;
  String? bloodType;
  String? medicalInfo;

  // --- NEW FIELDS FOR MOBILE SYNC ---
  @Index()
  String? firebaseId; // Stores the Cloud ID

  @Index()
  String? generatedPassword; // Stores the "happy-lion" code
  // ---------------------------------

  // Relationship: A user can have one active device paired (conceptually)
  // We will store the MacAddress string here for easy lookup
  @Index()
  String? pairedDeviceMacAddress;
}
