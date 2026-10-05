import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../theme/healthpal_theme.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import 'auth_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.controller,
    required this.onLogin,
  });
  final AuthController controller;
  final VoidCallback onLogin;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.controller.isBusy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    widget.controller.signUp(
      name: _name.text,
      email: _email.text,
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.controller;
    return AuthLayout(
      onBack: () {
        if (!auth.isBusy) widget.onLogin();
      },
      title: 'Bắt đầu cùng\nHealthPal.',
      subtitle: 'Một tài khoản cho hành trình chăm sóc bản thân.',
      children: [
        AuthCard(
          child: AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: Form(
              key: _form,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tạo tài khoản',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Dùng thông tin mẫu để thử trải nghiệm.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: HealthPalColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const FieldLabel('Họ và tên'),
                  TextFormField(
                    key: const Key('register-name'),
                    controller: _name,
                    enabled: !auth.isBusy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    style: const TextStyle(fontSize: 14),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Vui lòng nhập họ và tên.'
                        : null,
                    decoration: const InputDecoration(
                      hintText: 'Tên của bạn',
                      prefixIcon: Icon(CupertinoIcons.person, size: 19),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Email'),
                  TextFormField(
                    key: const Key('register-email'),
                    controller: _email,
                    enabled: !auth.isBusy,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newUsername],
                    autocorrect: false,
                    style: const TextStyle(fontSize: 14),
                    validator: AuthValidators.email,
                    onChanged: (_) => auth.clearError(),
                    decoration: const InputDecoration(
                      hintText: 'ban@example.com',
                      prefixIcon: Icon(CupertinoIcons.mail, size: 19),
                    ),
                  ),
                  if (auth.error?.code == AuthFailure.emailAlreadyInUse)
                    const AuthErrorMessage(
                      'Email này đã được đăng ký. Hãy dùng email khác hoặc đăng nhập.',
                    ),
                  const SizedBox(height: 18),
                  const FieldLabel('Mật khẩu'),
                  PasswordField(
                    fieldKey: const Key('register-password'),
                    controller: _password,
                    enabled: !auth.isBusy,
                    validator: AuthValidators.password,
                    hint: 'Ít nhất 8 ký tự',
                    isNewPassword: true,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Xác nhận mật khẩu'),
                  PasswordField(
                    fieldKey: const Key('register-confirm'),
                    controller: _confirm,
                    enabled: !auth.isBusy,
                    hint: 'Nhập lại mật khẩu',
                    isNewPassword: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng xác nhận mật khẩu.';
                      }
                      if (value != _password.text) {
                        return 'Mật khẩu xác nhận chưa khớp.';
                      }
                      return null;
                    },
                    onSubmitted: _submit,
                  ),
                  if (auth.error != null &&
                      auth.error?.code != AuthFailure.emailAlreadyInUse)
                    AuthErrorMessage(
                      auth.error?.code == AuthFailure.network
                          ? 'Không thể kết nối máy chủ. Vui lòng thử lại.'
                          : 'Chưa thể tạo tài khoản. Vui lòng thử lại.',
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('register-submit'),
                    onPressed: auth.isBusy ? null : _submit,
                    child: SubmitContent(
                      busy: auth.isBusy,
                      label: 'Tạo tài khoản',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Đã có tài khoản?',
                        style: TextStyle(
                          fontSize: 13,
                          color: HealthPalColors.secondary,
                        ),
                      ),
                      TextButton(
                        onPressed: auth.isBusy ? null : widget.onLogin,
                        child: const Text('Đăng nhập'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
