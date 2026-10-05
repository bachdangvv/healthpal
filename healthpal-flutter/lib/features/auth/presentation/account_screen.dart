import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../theme/healthpal_theme.dart';
import '../application/auth_controller.dart';
import '../domain/auth_user.dart';
import 'auth_widgets.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({
    super.key,
    required this.controller,
    required this.user,
  });
  final AuthController controller;
  final AuthUser user;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _confirming = false;

  Future<void> _logout() async {
    if (_confirming || widget.controller.isBusy) return;
    _confirming = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text(
          'Bạn có thể đăng nhập lại bằng tài khoản này trong phiên chạy hiện tại.',
        ),
        actions: [
          TextButton(
            key: const Key('cancel-logout'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm-logout'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    _confirming = false;
    if (!mounted || confirmed != true) return;
    await widget.controller.signOut();
  }

  String get _initials {
    final words = widget.user.name.trim().split(RegExp(r'\s+'));
    return words.reversed
        .take(2)
        .toList()
        .reversed
        .map((word) => word.characters.first.toUpperCase())
        .join();
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.controller;
    return AuthLayout(
      title: 'Tài khoản\ncủa bạn.',
      subtitle: 'Thật vui khi có bạn ở đây.',
      children: [
        AuthCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFD7DA), Color(0xFFE0D5FF)],
                    ),
                  ),
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF62448E),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.user.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7F0),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        size: 15,
                        color: Color(0xFF24734B),
                      ),
                      Text(
                        'Đã đăng nhập',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF24734B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Divider(color: HealthPalColors.border, height: 1),
              const SizedBox(height: 24),
              const FieldLabel('Email tài khoản'),
              Text(
                widget.user.email,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 22),
              const FieldLabel('Chế độ trải nghiệm'),
              const Text(
                'Tài khoản demo',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: HealthPalColors.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          key: const Key('logout'),
          onPressed: auth.isBusy ? null : _logout,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 56),
            foregroundColor: const Color(0xFFB3263A),
            backgroundColor: Colors.white,
            side: const BorderSide(color: HealthPalColors.border),
            padding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          child: SubmitContent(busy: auth.isBusy, label: 'Đăng xuất'),
        ),
        if (auth.error != null)
          const AuthErrorMessage('Chưa thể đăng xuất. Vui lòng thử lại.'),
      ],
    );
  }
}
