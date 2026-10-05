/// The signed-in profile, independent of the authentication provider.
class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;
}
