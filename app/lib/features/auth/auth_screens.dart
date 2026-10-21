import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/widgets/common.dart';
import '../../data/providers.dart';
import 'google_auth.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _validateEmail(String? v) =>
    (v == null || !_emailPattern.hasMatch(v.trim())) ? 'Enter a valid email address' : null;

String? _validatePassword(String? v) =>
    (v == null || v.length < 8) ? 'Use at least 8 characters' : null;

/// Shared frame: logo, title and a centered, width-capped card.
class _AuthFrame extends StatelessWidget {
  const _AuthFrame({required this.title, required this.subtitle, required this.children, this.showBack = false});

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: showBack ? AppBar() : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Image.asset('assets/logo.png', width: 72, height: 72, semanticLabel: 'FinTrack')),
                const SizedBox(height: 20),
                Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 28),
                ...children,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, this.label = 'Password', this.validator, this.onSubmitted});

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: const Icon(Symbols.lock_rounded),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Symbols.visibility_rounded : Symbols.visibility_off_rounded),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- sign in

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    await _run(() => ref
        .read(supabaseProvider)
        .auth
        .signInWithPassword(email: _email.text.trim(), password: _password.text));
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      title: 'Welcome back',
      subtitle: 'Sign in to keep track of your money.',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: _validateEmail,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Symbols.mail_rounded)),
              ),
              const SizedBox(height: 12),
              _PasswordField(
                controller: _password,
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                onSubmitted: (_) => _signIn(),
              ),
            ]),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: () => context.push('/auth/forgot-password'), child: const Text('Forgot password?')),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign in'),
        ),
        if (Env.googleSignInEnabled) ...[
          const SizedBox(height: 16),
          const Row(children: [
            Expanded(child: Divider()),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or')),
            Expanded(child: Divider()),
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(() => signInWithGoogle(ref.read(supabaseProvider))),
            icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            label: const Text('Continue with Google'),
          ),
        ],
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text("Don't have an account?"),
          TextButton(onPressed: () => context.push('/auth/sign-up'), child: const Text('Create one')),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------- sign up

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final res = await ref.read(supabaseProvider).auth.signUp(
            email: _email.text.trim(),
            password: _password.text,
            emailRedirectTo: Env.authRedirectUrl,
            data: {'full_name': _name.text.trim()},
          );
      if (!mounted) return;
      if (res.session == null) {
        // Email confirmation is enabled: the user must click the link first.
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Symbols.mark_email_read_rounded),
            title: const Text('Check your email'),
            content: Text('We sent a confirmation link to ${_email.text.trim()}. '
                'Open it on this device to finish creating your account.'),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        if (mounted) context.go('/auth/sign-in');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      title: 'Create your account',
      subtitle: 'Start tracking income, expenses and goals.',
      showBack: true,
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
                decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Symbols.person_rounded)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                validator: _validateEmail,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Symbols.mail_rounded)),
              ),
              const SizedBox(height: 12),
              _PasswordField(controller: _password, validator: _validatePassword),
              const SizedBox(height: 12),
              _PasswordField(
                controller: _confirm,
                label: 'Confirm password',
                validator: (v) => v != _password.text ? 'Passwords do not match' : null,
                onSubmitted: (_) => _signUp(),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _signUp,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create account'),
        ),
      ],
    );
  }
}

// -------------------------------------------------------- forgot password

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(supabaseProvider).auth.resetPasswordForEmail(_email.text.trim(), redirectTo: Env.authRedirectUrl);
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      title: 'Reset your password',
      subtitle: _sent
          ? 'If an account exists for ${_email.text.trim()}, a reset link is on its way. Open it on this device.'
          : "Enter your email and we'll send you a reset link.",
      showBack: true,
      children: [
        if (!_sent) ...[
          Form(
            key: _form,
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
              onFieldSubmitted: (_) => _send(),
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Symbols.mail_rounded)),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _send, child: const Text('Send reset link')),
        ] else
          OutlinedButton(onPressed: () => context.go('/auth/sign-in'), child: const Text('Back to sign in')),
      ],
    );
  }
}

// -------------------------------------------------------- update password

class UpdatePasswordScreen extends ConsumerStatefulWidget {
  const UpdatePasswordScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends ConsumerState<UpdatePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(supabaseProvider).auth.updateUser(UserAttributes(password: _password.text));
      widget.onDone();
      if (!mounted) return;
      showSnack(context, 'Password updated');
      context.go('/dashboard');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      title: 'Choose a new password',
      subtitle: 'You will use it the next time you sign in.',
      children: [
        Form(
          key: _form,
          child: Column(children: [
            _PasswordField(controller: _password, label: 'New password', validator: _validatePassword),
            const SizedBox(height: 12),
            _PasswordField(
              controller: _confirm,
              label: 'Confirm new password',
              validator: (v) => v != _password.text ? 'Passwords do not match' : null,
              onSubmitted: (_) => _save(),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Update password')),
      ],
    );
  }
}
