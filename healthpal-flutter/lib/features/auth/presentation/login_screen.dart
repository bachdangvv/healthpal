import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../theme/healthpal_theme.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import '../data/demo_auth_repository.dart';
import 'auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.controller,
    required this.onRegister,
  });

  final AuthController controller;
  final VoidCallback onRegister;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.controller.isBusy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    widget.controller.signIn(email: _email.text, password: _password.text);
  }

  void _fillDemo() {
    widget.controller.clearError();
    _form.currentState!.reset();
    _email.text = DemoAuthRepository.demoEmail;
    _password.text = DemoAuthRepository.demoPassword;
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.controller;
    return AuthLayout(
      title: 'Chào mừng\ntrở lại.',
      subtitle: 'Tiếp tục hành trình khỏe hơn cùng HealthPal.',
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
                    'Đăng nhập',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const FieldLabel('Email'),
                  TextFormField(
                    key: const Key('login-email'),
                    controller: _email,
                    enabled: !auth.isBusy,
                    validator: AuthValidators.email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.username],
                    autocorrect: false,
                    style: const TextStyle(fontSize: 14),
                    onChanged: (_) => auth.clearError(),
                    decoration: const InputDecoration(
                      hintText: 'ban@example.com',
                      prefixIcon: Icon(CupertinoIcons.mail, size: 19),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Mật khẩu'),
                  PasswordField(
                    fieldKey: const Key('login-password'),
                    controller: _password,
                    enabled: !auth.isBusy,
                    validator: AuthValidators.password,
                    onChanged: (_) => auth.clearError(),
                    onSubmitted: _submit,
                  ),
                  if (auth.error != null)
                    AuthErrorMessage(
                      auth.error?.code == AuthFailure.invalidCredentials
                          ? 'Email hoặc mật khẩu chưa đúng. Vui lòng thử lại.'
                          : auth.error?.code == AuthFailure.network
                          ? 'Không thể kết nối máy chủ. Vui lòng thử lại.'
                          : 'Chưa thể đăng nhập. Vui lòng thử lại.',
                    ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('login-submit'),
                    onPressed: auth.isBusy ? null : _submit,
                    child: SubmitContent(busy: auth.isBusy, label: 'Đăng nhập'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Chưa có tài khoản?',
                        style: TextStyle(
                          fontSize: 13,
                          color: HealthPalColors.secondary,
                        ),
                      ),
                      TextButton(
                        key: const Key('open-register'),
                        onPressed: auth.isBusy ? null : widget.onRegister,
                        child: const Text('Đăng ký'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton(
          key: const Key('fill-demo'),
          onPressed: auth.isBusy ? null : _fillDemo,
          style: OutlinedButton.styleFrom(
            foregroundColor: HealthPalColors.blue,
            backgroundColor: const Color(0xFFEEF3FF),
            side: const BorderSide(color: Color(0xFFDFE8FE)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: const Row(
            children: [
              Icon(CupertinoIcons.sparkles, size: 24),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Điền tài khoản mẫu',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Trải nghiệm trước, khám phá sau',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: HealthPalColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(CupertinoIcons.arrow_right, size: 18),
            ],
          ),
        ),
      ],
    );
  }
}
