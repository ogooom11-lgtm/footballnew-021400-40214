import '../enums/team_id.dart';

/// Frozen snapshot of a goal for the VAR front-camera split view
/// (مطلب الفار: شاشة مقسومة لنصفين، كل نصف مرمى فريق من الأمام، يظهر
/// من وين دخلت الكرة وكيف قفز الحارس).
class GoalVarView {
  GoalVarView({
    required this.concedingSide,
    required this.scoringTeamName,
    required this.concedingTeamName,
    required this.scorerName,
    required this.minute,
    required this.entryRatio,
    required this.entryHeightRatio,
    required this.keeperOffsetRatio,
    required this.keeperDiveDir,
    required this.keeperReachRatio,
  });

  /// Which goal was hit (the side the conceding team defends).
  final TeamSide concedingSide;
  final String scoringTeamName;
  final String concedingTeamName;
  final String scorerName;
  final int minute;

  /// Where the ball crossed the goal line, across the mouth: 0 = one post,
  /// 1 = the other post (as seen from the front camera).
  final double entryRatio;

  /// How high the ball crossed, 0 = ground, 1 = crossbar.
  final double entryHeightRatio;

  /// Where the keeper ended up along the line relative to the goal centre:
  /// -1 = full left post, 0 = centre, +1 = full right post.
  final double keeperOffsetRatio;

  /// Which way the keeper dove: -1 left, 0 stayed central, +1 right.
  final int keeperDiveDir;

  /// How high the keeper reached in the dive, 0 = ground, 1 = crossbar.
  final double keeperReachRatio;
}
