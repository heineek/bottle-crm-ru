/// Entries from `GET /api/org/audit-log/`, mirroring `/settings/audit-log`
/// on the web.
///
/// The API sends only allow-listed `details` keys (ids, counts, and sentences
/// the server wrote) and never the stored description, so everything shown is
/// built from those.
library;

import '../../l10n/l10n.dart';
import '../api/schema.g.dart' as api;

/// One option in the event filter.
class AuditEventType {
  const AuditEventType({required this.value, required this.label});

  final String value;
  final String label;

  /// Reads an `AuditLogEventType`.
  factory AuditEventType.fromJson(Map<String, dynamic> json) {
    final w = api.AuditLogEventType.fromJson(json);
    return AuditEventType(value: w.value ?? '', label: w.label ?? '');
  }
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.eventType,
    required this.eventLabel,
    this.createdAt,
    this.success = true,
    this.actorId,
    this.actorName = '',
    this.actorEmail = '',
    this.ipAddress = '',
    this.details = const {},
  });

  final String id;
  final String eventType;
  final String eventLabel;
  final DateTime? createdAt;
  final bool success;

  /// Null for a system event, or once the user has been deleted.
  final String? actorId;
  final String actorName;
  final String actorEmail;
  final String ipAddress;
  final Map<String, dynamic> details;

  String get actorLabel {
    if (actorId == null) return appL10n.appAuditNoUser;
    if (actorName.isNotEmpty) return actorName;
    if (actorEmail.isNotEmpty) return actorEmail;
    return appL10n.appAuditNoUser;
  }

  /// One line on what happened, or '' when the label says it all. The same
  /// rules as `auditDetail` in `frontend/src/lib/v2/audit-log.ts`.
  String get detail {
    final reason = details['pause_reason'];
    if (reason != null && reason.toString().isNotEmpty) return '$reason';
    if (eventType == 'RECORD_MERGED' && details['merged_name'] != null) {
      final entity = details['entity']?.toString() ?? '';
      // Duplicates usually share a name, and "X into X" says nothing, so
      // equal names each carry the start of their id.
      final same = details['merged_name'] == details['kept_name'];
      String tag(Object? id) {
        final text = id?.toString() ?? '';
        if (!same || text.isEmpty) return '';
        return ' (${text.length > 8 ? text.substring(0, 8) : text})';
      }

      return appL10n.appAuditMerged(
        entity.isEmpty ? appL10n.appAuditRecord : entity,
        '${details['merged_name']}',
        tag(details['merged_id']),
        '${details['kept_name']}',
        tag(details['kept_id']),
      );
    }
    final prefix = details['token_prefix'];
    if ((eventType == 'API_TOKEN_CREATED' ||
            eventType == 'API_TOKEN_REVOKED') &&
        prefix != null &&
        prefix.toString().isNotEmpty) {
      // An empty scope list is a token with the owner's full access. The
      // owner is named only when someone else acted: an admin revoking it.
      final scopes = details['scopes'];
      final scopeText = scopes is List && scopes.isNotEmpty
          ? appL10n.appAuditScopes(scopes.join(', '))
          : appL10n.appAuditFullAccess;
      final ownerId = details['owner_id'];
      final owner = ownerId != null && ownerId.toString() != actorId
          ? appL10n.appAuditOwnedBy('${details['owner_name']}')
          : '';
      return appL10n.appAuditToken(
        '${details['token_name']}',
        '$prefix',
        '$scopeText$owner',
      );
    }
    if (eventType == 'WEBHOOK_REENABLED') {
      return appL10n.appAuditWebhookReenabled;
    }
    final changed = details['changed'];
    if (eventType == 'WEBHOOK_CHANGED' && changed is List) {
      return appL10n.appAuditWebhookChanged(changed.join(', '));
    }
    final action = details['action'];
    final resource = details['resource'];
    if (action != null && resource != null) {
      return appL10n.appAuditActionOn('$action', '$resource');
    }
    final deleted = details['deleted_count'];
    if (deleted != null) return appL10n.appAuditSampleLeadsRemoved('$deleted');
    return '';
  }

  /// The webhook the entry is about, for a link, or null.
  String? get webhookId {
    final id = details['endpoint_id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Reads an `AuditLogEntry`.
  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    final w = api.AuditLogEntry.fromJson(json);
    final actor = w.actor;
    return AuditEntry(
      id: w.id ?? '',
      eventType: w.eventType ?? '',
      eventLabel: w.eventLabel ?? w.eventType ?? '',
      createdAt: DateTime.tryParse(w.createdAt ?? ''),
      success: w.success != false,
      actorId: actor?.id,
      actorName: actor?.name ?? '',
      actorEmail: actor?.email ?? '',
      ipAddress: w.ipAddress ?? '',
      details: w.details ?? const {},
    );
  }
}
