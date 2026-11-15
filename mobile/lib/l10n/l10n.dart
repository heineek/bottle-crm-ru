import 'package:flutter/widgets.dart';

import '../services/app_language.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// The app's strings: `context.l10n.commonSave`.
///
/// Falls back to the current language when no [AppLocalizations] is in scope
/// (a bare `MaterialApp` in a widget test, a context above the app's own), so
/// a missing delegate shows text rather than throwing.
extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(Locale(currentLanguage));
}

/// The app's strings in the current language, for code with no
/// [BuildContext] (model labels, provider error messages). Call it where the
/// text is needed, never into a `static final`: that would freeze the
/// language it first ran in.
AppLocalizations get appL10n => lookupAppLocalizations(Locale(currentLanguage));
