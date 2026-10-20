import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/quiz_provider.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _showSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _toggleMode() {
    _fadeCtrl.forward(from: 0);
    setState(() => _showSignUp = !_showSignUp);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 800)); // Simulate auth
    if (!mounted) return;
    final name = _showSignUp ? _nameCtrl.text.trim() : _emailCtrl.text.split('@').first;
    context.read<QuizProvider>().completeLogin(
      name: name,
      email: _emailCtrl.text.trim(),
    );
  }

  Future<void> _googleSignIn() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    context.read<QuizProvider>().completeLogin(
      name: 'Trader',
      email: 'user@gmail.com',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<QuizProvider>().isDarkMode;
    final textColor = isDark ? Colors.white : AppColors.lightTextPrimary;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    // Logo mark
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.emerald, AppColors.emeraldDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.emerald.withOpacity(0.35),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('Q',
                          style: TextStyle(
                            fontSize: 30, fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic, color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _showSignUp ? 'Create Account' : 'Welcome Back',
                      style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic, color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _showSignUp
                          ? 'Start your quant journey today'
                          : 'Sign in to your QuantEdge workspace',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Google SSO ────────────────────────────────────────────
              _GoogleButton(onTap: _isLoading ? null : _googleSignIn, isDark: isDark),
              const SizedBox(height: 16),

              // ── Divider ───────────────────────────────────────────────
              Row(children: [
                Expanded(child: Divider(
                  color: isDark ? Colors.white12 : AppColors.lightBorder, height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                    ),
                  ),
                ),
                Expanded(child: Divider(
                  color: isDark ? Colors.white12 : AppColors.lightBorder, height: 1)),
              ]),
              const SizedBox(height: 16),

              // ── Name field (sign up only) ──────────────────────────────
              if (_showSignUp) ...[
                _InputField(
                  controller: _nameCtrl,
                  label: 'Full Name',
                  hint: 'Shreya Mehta',
                  icon: Icons.person_outline_rounded,
                  isDark: isDark,
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 12),
              ],

              // ── Email field ───────────────────────────────────────────
              _InputField(
                controller: _emailCtrl,
                label: 'Email',
                hint: 'you@example.com',
                icon: Icons.mail_outline_rounded,
                isDark: isDark,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v?.trim().isEmpty ?? true) return 'Enter your email';
                  if (!v!.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ── Password field ────────────────────────────────────────
              _InputField(
                controller: _passwordCtrl,
                label: 'Password',
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                isDark: isDark,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18,
                    color: isDark ? Colors.white38 : AppColors.lightTextMuted,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (v) => (v?.length ?? 0) < 6 ? 'Min 6 characters' : null,
              ),

              // ── Forgot password ───────────────────────────────────────
              if (!_showSignUp) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () {},
                    child: Text('Forgot password?',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.emeraldLight : AppColors.emeraldDark,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // ── Submit button ─────────────────────────────────────────
              ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                  elevation: 10,
                  shadowColor: AppColors.emerald.withOpacity(0.4),
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _showSignUp ? 'CREATE ACCOUNT' : 'SIGN IN',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0, fontSize: 13,
                        ),
                      ),
              ),
              const SizedBox(height: 20),

              // ── Toggle login/signup ───────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: _toggleMode,
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : AppColors.lightTextMuted,
                      ),
                      children: [
                        TextSpan(
                          text: _showSignUp
                              ? 'Already have an account? '
                              : "Don't have an account? ",
                        ),
                        TextSpan(
                          text: _showSignUp ? 'Sign In' : 'Sign Up',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: isDark ? AppColors.emeraldLight : AppColors.emeraldDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Google button ─────────────────────────────────────────────────────────────

class _GoogleButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isDark;

  const _GoogleButton({this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : AppColors.lightBorder, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google G icon (drawn simply)
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade300, width: 1),
              ),
              child: const Center(
                child: Text('G',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900,
                    color: Color(0xFF4285F4),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Continue with Google',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Input field ───────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool isDark;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.isDark,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? Colors.white12 : AppColors.lightBorder;
    final fillColor   = isDark ? AppColors.darkCard.withOpacity(0.4) : Colors.white;
    final textColor   = isDark ? Colors.white : AppColors.lightTextPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: isDark ? Colors.white60 : AppColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          style: TextStyle(fontSize: 14, color: textColor, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white24 : AppColors.lightTextMuted,
              fontSize: 13,
            ),
            prefixIcon: Icon(icon, size: 18,
              color: isDark ? Colors.white38 : AppColors.lightTextMuted),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: fillColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: borderColor, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: borderColor, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.emerald, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.rose, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.rose, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }
}
