import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/l10n.dart';
import '../../core/theme/theme.dart';
import '../../providers/auth_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/common/common.dart';

/// Second step of the OTP login flow: enter the 6-digit code we sent.
///
/// Receives the email via query param (`?email=...`). On success, routes to
/// dashboard or org selection based on whether the backend pre-selected an org.
class MagicLinkCodeScreen extends ConsumerStatefulWidget {
  final String email;

  const MagicLinkCodeScreen({super.key, required this.email});

  @override
  ConsumerState<MagicLinkCodeScreen> createState() =>
      _MagicLinkCodeScreenState();
}

class _MagicLinkCodeScreenState extends ConsumerState<MagicLinkCodeScreen> {
  static const int _codeLength = 6;
  static const int _resendCooldownSeconds = 30;

  final _codeController = TextEditingController();
  final _codeFocusNode = FocusNode();
  bool _isVerifying = false;
  bool _isResending = false;
  int _resendCooldown = _resendCooldownSeconds;
  Timer? _cooldownTimer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _codeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = _resendCooldownSeconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _handleVerify() async {
    final code = _codeController.text.trim();
    if (code.length != _codeLength) {
      setState(() => _errorMessage = context.l10n.appCodeEnterSix);
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final ok = await ref
        .read(authProvider.notifier)
        .signInWithMagicCode(email: widget.email, code: code);

    if (!mounted) return;

    if (ok) {
      final authState = ref.read(authProvider);
      // If the backend pre-selected an org, jump straight to the dashboard;
      // otherwise the user must pick one (new account or multi-org user).
      if (authState.needsOrgSelection) {
        context.go(AppRoutes.orgSelection);
      } else {
        context.go(AppRoutes.dashboard);
      }
    } else {
      final error =
          ref.read(authProvider).error ??
          context.l10n.appMsgInvalidOrExpiredCodePleaseTryAgain;
      setState(() {
        _isVerifying = false;
        _errorMessage = error;
        _codeController.clear();
      });
      _codeFocusNode.requestFocus();
    }
  }

  Future<void> _handleResend() async {
    if (_resendCooldown > 0 || _isResending) return;
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    final ok = await ref
        .read(authProvider.notifier)
        .requestMagicCode(widget.email);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (ok) {
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.appCodeResent),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _errorMessage = context.l10n.appCodeResendFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  LucideIcons.shieldCheck,
                  size: 32,
                  color: AppColors.primary600,
                ),
              ),
              const SizedBox(height: 24),
              Text(context.l10n.appCodeTitle, style: AppTypography.h1),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  children: [
                    TextSpan(text: context.l10n.appCodeSentPrefix),
                    TextSpan(
                      text: widget.email,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: context.l10n.appCodeSentSuffix),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _CodeInput(
                controller: _codeController,
                focusNode: _codeFocusNode,
                length: _codeLength,
                hasError: _errorMessage != null,
                onCompleted: (_) => _handleVerify(),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.danger600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: context.l10n.appCodeVerify,
                onPressed: _isVerifying ? null : _handleVerify,
                isLoading: _isVerifying,
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _resendCooldown == 0 && !_isResending
                      ? _handleResend
                      : null,
                  child: Text(
                    _resendCooldown > 0
                        ? context.l10n.appCodeResendIn(_resendCooldown)
                        : (_isResending
                              ? context.l10n.appSending
                              : context.l10n.appCodeResend),
                    style: AppTypography.label.copyWith(
                      color: _resendCooldown == 0 && !_isResending
                          ? AppColors.primary600
                          : AppColors.textSecondary,
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

/// Single underlying text field styled as a 6-digit code input.
///
/// One field (not six) so paste-from-email works in one shot and the platform
/// keyboard reliably surfaces autofill suggestions from SMS/email apps.
class _CodeInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool hasError;
  final ValueChanged<String>? onCompleted;

  const _CodeInput({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.hasError,
    this.onCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.oneTimeCode],
      maxLength: length,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(length),
      ],
      textAlign: TextAlign.center,
      style: AppTypography.h1.copyWith(
        letterSpacing: 12,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: '••••••',
        hintStyle: AppTypography.h1.copyWith(
          color: AppColors.gray300,
          letterSpacing: 12,
        ),
        filled: true,
        fillColor: AppColors.surfaceDim,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppLayout.borderRadiusMd,
          borderSide: BorderSide(
            color: hasError ? AppColors.danger600 : AppColors.border,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppLayout.borderRadiusMd,
          borderSide: BorderSide(
            color: hasError ? AppColors.danger600 : AppColors.primary600,
            width: 2,
          ),
        ),
      ),
      onChanged: (value) {
        if (value.length == length) {
          onCompleted?.call(value);
        }
      },
    );
  }
}
