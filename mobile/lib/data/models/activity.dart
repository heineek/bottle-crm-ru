import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import 'task.dart';

/// Activity type enumeration
enum ActivityType {
  call(LucideIcons.phone, AppColors.primary500),
  email(LucideIcons.mail, AppColors.purple500),
  note(LucideIcons.stickyNote, AppColors.gray500),
  meeting(LucideIcons.calendar, AppColors.warning500),
  stageChange(LucideIcons.trendingUp, AppColors.primary600),
  dealWon(LucideIcons.trophy, AppColors.success500),
  dealLost(LucideIcons.circleX, AppColors.danger500),
  taskCompleted(LucideIcons.circleCheck, AppColors.success500),
  leadCreated(LucideIcons.userPlus, AppColors.primary500),
  dealCreated(LucideIcons.circlePlus, AppColors.primary500);

  final IconData icon;
  final Color color;

  const ActivityType(this.icon, this.color);

  String get label => switch (this) {
    call => appL10n.appActivityTypeCall,
    email => appL10n.appActivityTypeEmail,
    note => appL10n.appActivityTypeNote,
    meeting => appL10n.appActivityTypeMeeting,
    stageChange => appL10n.appActivityTypeStageChange,
    dealWon => appL10n.appActivityTypeDealWon,
    dealLost => appL10n.appActivityTypeDealLost,
    taskCompleted => appL10n.appActivityTypeTaskCompleted,
    leadCreated => appL10n.appActivityTypeLeadCreated,
    dealCreated => appL10n.appActivityTypeDealCreated,
  };

  static ActivityType fromString(String value) {
    switch (value.toLowerCase().replaceAll('-', '').replaceAll('_', '')) {
      case 'call':
        return ActivityType.call;
      case 'email':
        return ActivityType.email;
      case 'note':
        return ActivityType.note;
      case 'meeting':
        return ActivityType.meeting;
      case 'stagechange':
        return ActivityType.stageChange;
      case 'dealwon':
        return ActivityType.dealWon;
      case 'deallost':
        return ActivityType.dealLost;
      case 'taskcompleted':
        return ActivityType.taskCompleted;
      case 'leadcreated':
        return ActivityType.leadCreated;
      case 'dealcreated':
        return ActivityType.dealCreated;
      default:
        return ActivityType.note;
    }
  }
}

/// Activity model for BottleCRM
class Activity {
  final String id;
  final ActivityType type;
  final String title;
  final String? description;
  final DateTime timestamp;
  final String userId;
  final String? userName;
  final RelatedEntity? relatedTo;
  final Map<String, dynamic>? metadata;

  const Activity({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    required this.timestamp,
    required this.userId,
    this.userName,
    this.relatedTo,
    this.metadata,
  });

  /// Get relative time string (e.g., "2 hours ago")
  String get relativeTime {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    final l10n = appL10n;
    if (diff.inMinutes < 1) {
      return l10n.appRelativeJustNow;
    } else if (diff.inMinutes < 60) {
      return l10n.appRelativeMinutesAgo(diff.inMinutes);
    } else if (diff.inHours < 24) {
      return l10n.appRelativeHoursAgo(diff.inHours);
    } else if (diff.inDays < 7) {
      return l10n.appRelativeDaysAgo(diff.inDays);
    } else if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return l10n.appRelativeWeeksAgo(weeks);
    } else {
      final months = (diff.inDays / 30).floor();
      return l10n.appRelativeMonthsAgo(months);
    }
  }

  /// Check if activity is from today
  bool get isToday {
    final now = DateTime.now();
    return timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day;
  }

  Activity copyWith({
    String? id,
    ActivityType? type,
    String? title,
    String? description,
    DateTime? timestamp,
    String? userId,
    String? userName,
    RelatedEntity? relatedTo,
    Map<String, dynamic>? metadata,
  }) {
    return Activity(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      timestamp: timestamp ?? this.timestamp,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      relatedTo: relatedTo ?? this.relatedTo,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Activity && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
