class Profile {
  const Profile({required this.id, required this.displayName});

  final String id;
  final String displayName;

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        displayName: map['display_name'] as String,
      );
}
