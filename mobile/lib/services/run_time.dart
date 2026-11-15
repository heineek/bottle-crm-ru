import 'package:timezone/timezone.dart' as tz;

import '../l10n/l10n.dart';
import 'app_language.dart';
import 'auth_service.dart';
import 'org_date.dart';

/// An instant in the org's zone, 24-hour: "Today 10:42", "Yesterday 18:03",
/// "21 Oct 18:03", "21 Oct 2025 18:03". The twin of `runTime` in
/// `frontend/src/lib/v2/format.js`. A null or unknown [zone] reads the org's
/// zone from the access token, then UTC.
String runTimeLabel(DateTime at, {String? zone, DateTime? now}) {
  loadTimeZones();
  final name = zone ?? orgTimeZoneOf(AuthService().accessToken);
  tz.Location location;
  try {
    location = tz.getLocation(name);
  } catch (_) {
    location = tz.UTC;
  }
  final t = tz.TZDateTime.from(at, location);
  final today = tz.TZDateTime.from(now ?? DateTime.now(), location);
  final gap = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
  final clock =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final l10n = appL10n;
  if (gap == 0) return '${l10n.appTimeToday} $clock';
  if (gap == 1) return '${l10n.appTimeYesterday} $clock';
  final day = DateTime(t.year, t.month, t.day);
  final date = t.year == today.year
      ? localDateFormat('d MMM', 'MMMd').format(day)
      : localDateFormat('d MMM y', 'yMMMd').format(day);
  return '$date $clock';
}
