import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../l10n/l10n.dart';
import '../../providers/language_provider.dart';
import '../../services/app_language.dart';

/// Your interface language, mirroring the language card on the web's
/// `/profile`. One choice for every org and both clients: it is saved on your
/// account, and the token is refreshed so every client reads it.
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  bool _busy = false;

  Future<void> _choose(String? language) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final error = await ref.read(languageProvider.notifier).choose(language);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.isEmpty ? l10n.languageSaveFailed : error),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    ref.watch(languageProvider);
    final chosen = ref.read(languageProvider.notifier).chosen;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(l10n.languageScreenTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            const SizedBox(height: 12),
            _Option(
              title: l10n.languageAutomatic,
              detail: l10n.languageAutomaticDetail,
              selected: chosen == null,
              onTap: () => _choose(null),
            ),
            for (final code in supportedLanguages)
              _Option(
                title: lookupAppLocalizations(Locale(code)).languageName,
                selected: chosen == code,
                onTap: () => _choose(code),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Text(
                l10n.languageHint,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  const _Option({
    required this.title,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: selected ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.gray100)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                Icon(LucideIcons.check, size: 18, color: AppColors.primary600),
            ],
          ),
        ),
      ),
    );
  }
}
