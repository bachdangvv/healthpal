import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/healthpal_theme.dart';
import '../../../theme/healthpal_brand.dart';

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: HealthPalColors.background,
      ),
      child: Scaffold(
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 410,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.topRight,
                    colors: [Color(0xFFFFBABD), Color(0xFFD9C6FF)],
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        HealthPalColors.background.withValues(alpha: 0),
                        HealthPalColors.background,
                      ],
                      stops: const [0.3, 1],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: GestureDetector(
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                behavior: HitTestBehavior.translucent,
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Brand(onBack: onBack),
                          const SizedBox(height: 30),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 34,
                              height: 1.15,
                              letterSpacing: -1.3,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: HealthPalColors.secondary,
                            ),
                          ),
                          const SizedBox(height: 28),
                          ...children,
                          const SizedBox(height: 24),
                          const Text(
                            'Bản demo · Dữ liệu chỉ lưu trong phiên chạy.\n'
                            'Khởi động lại ứng dụng sẽ đặt lại dữ liệu.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: HealthPalColors.secondary,
                              fontSize: 11,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.onBack});
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          IconButton(
            key: const Key('back-login'),
            onPressed: onBack,
            tooltip: 'Về đăng nhập',
            icon: const Icon(CupertinoIcons.arrow_left, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.65),
              minimumSize: const Size(48, 48),
            ),
          ),
          const SizedBox(width: 12),
        ] else ...[
          const HealthPalLogo(),
          const SizedBox(width: 10),
        ],
        const Expanded(
          child: Text(
            'HealthPal',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'DEMO',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class AuthCard extends StatelessWidget {
  const AuthCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F163B),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.validator,
    this.enabled = true,
    this.hint = 'Nhập mật khẩu',
    this.isNewPassword = false,
    this.onSubmitted,
    this.onChanged,
    this.textInputAction = TextInputAction.done,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final bool enabled;
  final String hint;
  final bool isNewPassword;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.fieldKey,
      controller: widget.controller,
      enabled: widget.enabled,
      validator: widget.validator,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: widget.textInputAction,
      autofillHints: [
        widget.isNewPassword
            ? AutofillHints.newPassword
            : AutofillHints.password,
      ],
      style: const TextStyle(fontSize: 14),
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(CupertinoIcons.lock, size: 19),
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
          onPressed: widget.enabled
              ? () => setState(() => _hidden = !_hidden)
              : null,
          icon: Icon(
            _hidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class AuthErrorMessage extends StatelessWidget {
  const AuthErrorMessage(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(
          message,
          key: const Key('auth-error'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class SubmitContent extends StatelessWidget {
  const SubmitContent({super.key, required this.busy, required this.label});
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          semanticsLabel: 'Đang xử lý',
        ),
      );
    }
    return Text(label, textAlign: TextAlign.center);
  }
}

abstract final class AuthValidators {
  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Vui lòng nhập email.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Email chưa đúng định dạng.';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Vui lòng nhập mật khẩu.';
    if (value.length < 8) return 'Mật khẩu cần ít nhất 8 ký tự.';
    return null;
  }
}
