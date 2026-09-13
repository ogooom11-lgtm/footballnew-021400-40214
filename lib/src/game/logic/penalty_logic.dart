import 'dart:math' as math;

import '../enums/player_role.dart';
import '../enums/team_id.dart';
import '../models/player_game.dart';
import '../models/team_game.dart';

enum PenaltyLane { leftLow, center, rightLow, leftHigh, rightHigh }

extension PenaltyLaneText on PenaltyLane {
  String get title => switch (this) {
    PenaltyLane.leftLow => 'Sol alt',
    PenaltyLane.center => 'Orta',
    PenaltyLane.rightLow => 'Sag alt',
    PenaltyLane.leftHigh => 'Sol ust',
    PenaltyLane.rightHigh => 'Sag ust',
  };

  String get sideTitle => switch (this) {
    PenaltyLane.leftLow || PenaltyLane.leftHigh => 'Sol',
    PenaltyLane.center => 'Orta',
    PenaltyLane.rightLow || PenaltyLane.rightHigh => 'Sag',
  };
}

/// What actually happened to the penalty. The visual replay reads this, so
/// the ball on the pitch always does what the verdict says
/// (Gereksinim).
enum PenaltyOutcome { goal, saved, wide, overBar }

extension PenaltyOutcomeText on PenaltyOutcome {
  String get title => switch (this) {
    PenaltyOutcome.goal => 'GOL',
    PenaltyOutcome.saved => 'KALECI KURTARDI',
    PenaltyOutcome.wide => 'DIREKTEN DISARI',
    PenaltyOutcome.overBar => 'USTTEN AVUT',
  };
}

class PenaltyKickResult {
  const PenaltyKickResult({
    required this.teamId,
    required this.shooterName,
    required this.goalkeeperName,
    required this.shotLane,
    required this.keeperLane,
    required this.heightMeters,
    required this.power,
    required this.scored,
    required this.minute,
    this.outcome = PenaltyOutcome.goal,
    this.missAmount = 0,
    this.powerQuality = 0.5,
    this.accuracyQuality = 0.5,
  });

  final TeamId teamId;
  final String shooterName;
  final String goalkeeperName;
  final PenaltyLane shotLane;
  final PenaltyLane keeperLane;
  final double heightMeters;
  final double power;
  final bool scored;
  final int minute;

  /// The exact verdict of the kick.
  final PenaltyOutcome outcome;

  /// How far outside the frame a missed kick travelled (pixels).
  final double missAmount;

  /// 0..1 — how well the ball was struck (shot power relative to the ideal
  /// band).
  final double powerQuality;

  /// 0..1 — how clean the placement was (finishing / shooting accuracy).
  final double accuracyQuality;

  String get summary =>
      '$shooterName: ${shotLane.title}, ${heightMeters.toStringAsFixed(2)} m, '
      'kaleci ${keeperLane.sideTitle} - ${outcome.title}';
}

class ActivePenalty {
  ActivePenalty({
    required this.shootingTeam,
    required this.shootout,
    required this.minute,
    required this.shooterId,
  });

  final TeamId shootingTeam;
  final bool shootout;
  final int minute;
  String shooterId;
  PenaltyLane shotDirection = PenaltyLane.center;
  PenaltyLane keeperDirection = PenaltyLane.center;
  double countdown = 0;
  double preparationTimer = 1.2;
  PenaltyKickResult? result;
}

class PenaltyShootout {
  PenaltyShootout({required this.firstTeam});

  final TeamId firstTeam;
  final List<PenaltyKickResult> results = [];

  int goalsFor(TeamId teamId) => results
      .where((result) => result.teamId == teamId && result.scored)
      .length;

  int takenBy(TeamId teamId) =>
      results.where((result) => result.teamId == teamId).length;

  TeamId get nextTeam {
    if (results.isEmpty) {
      return firstTeam;
    }
    final blueTaken = takenBy(TeamId.blue);
    final redTaken = takenBy(TeamId.red);
    if (blueTaken == redTaken) {
      return firstTeam;
    }
    return firstTeam.opponent;
  }

  bool get complete {
    final blueTaken = takenBy(TeamId.blue);
    final redTaken = takenBy(TeamId.red);
    final blueGoals = goalsFor(TeamId.blue);
    final redGoals = goalsFor(TeamId.red);
    final blueRemaining = (5 - blueTaken).clamp(0, 5);
    final redRemaining = (5 - redTaken).clamp(0, 5);

    if (blueGoals > redGoals + redRemaining) {
      return true;
    }
    if (redGoals > blueGoals + blueRemaining) {
      return true;
    }
    if (blueTaken >= 5 && redTaken >= 5 && blueTaken == redTaken) {
      return blueGoals != redGoals;
    }
    return false;
  }

  TeamId? get winner {
    if (!complete) {
      return null;
    }
    return goalsFor(TeamId.blue) > goalsFor(TeamId.red)
        ? TeamId.blue
        : TeamId.red;
  }
}

class PenaltyLogic {
  PenaltyLogic(this.random);

  final math.Random random;

  PenaltyKickResult takeKick({
    required TeamGame shootingTeam,
    required TeamGame defendingTeam,
    required int kickIndex,
    required int minute,
  }) {
    final shooters =
        shootingTeam.players
            .where((player) => !player.isGoalkeeper && !player.isSentOff)
            .toList()
          ..sort((a, b) => _shooterValue(b).compareTo(_shooterValue(a)));
    final shooter = shooters[kickIndex % shooters.length];
    final keeper = defendingTeam.goalkeeper;
    final shotLane = _chooseShotLane(shooter);
    final keeperLane = _chooseKeeperLane(keeper, shotLane);
    return takeSelectedKick(
      shootingTeam: shootingTeam,
      defendingTeam: defendingTeam,
      kickIndex: kickIndex,
      minute: minute,
      shotDirection: shotLane,
      keeperDirection: keeperLane,
      power: 1.05 + random.nextDouble() * 0.45,
    );
  }

  PenaltyKickResult takeSelectedKick({
    required TeamGame shootingTeam,
    required TeamGame defendingTeam,
    required int kickIndex,
    required int minute,
    required PenaltyLane shotDirection,
    required PenaltyLane keeperDirection,
    required double power,
    PlayerGame? selectedShooter,
  }) {
    final shooters =
        shootingTeam.players
            .where((player) => !player.isGoalkeeper && !player.isSentOff)
            .toList()
          ..sort((a, b) => _shooterValue(b).compareTo(_shooterValue(a)));
    final shooter =
        selectedShooter != null &&
            selectedShooter.teamId == shootingTeam.id &&
            !selectedShooter.isGoalkeeper
        ? selectedShooter
        : shooters[kickIndex % shooters.length];
    final keeper = defendingTeam.goalkeeper;
    final clampedPower = power.clamp(0.55, 1.65).toDouble();
    final profile = shooter.profile;

    // -------------------------------------------------------------------
    // 1) The shooter: finishing (bitiricilik), shooting accuracy and the
    //    strike itself decide WHERE the ball goes.
    // -------------------------------------------------------------------
    final careerAccuracy = (profile.shootingAccuracyPercent / 100)
        .clamp(0.0, 1.0)
        .toDouble();
    final accuracyQuality =
        (profile.finishingSkill * 0.40 +
                profile.composureSkill * 0.24 +
                profile.shotSkill * 0.18 +
                careerAccuracy * 0.18)
            .clamp(0.05, 0.99)
            .toDouble();
    // Power band: below 0.80 the keeper eats it, above 1.40 the strike
    // sprays. 0.95–1.35 is the sweet spot.
    final powerQuality =
        (1.0 - ((clampedPower - 1.15).abs() / 0.55).clamp(0.0, 1.0))
            .toDouble();
    final overhit =
        (clampedPower - 1.35).clamp(0.0, 0.30).toDouble();
    final underhit = (0.85 - clampedPower).clamp(0.0, 0.30).toDouble();
    final cornerAim = shotDirection == PenaltyLane.center ? 0.0 : 1.0;
    // The spread of the strike in "goal units": 1.0 is a full goal width
    // off target (i.e. a hopeless miss).
    final spread = ((1 - accuracyQuality) * 0.62 +
            overhit * 1.15 +
            underhit * 0.18 +
            cornerAim * 0.10 -
            0.06)
        .clamp(0.05, 0.95)
        .toDouble();
    final error = (random.nextDouble() + random.nextDouble() - 1.0) * spread;
    // Height follows the aim and the power: a hard low corner stays low, a
    // hard strike aimed high can climb over the bar.
    var height = shotDirection == PenaltyLane.center
        ? 0.45 + powerQuality * 0.55
        : 0.60 + powerQuality * 0.95 + overhit * 1.6;
    height += (random.nextDouble() - 0.5) * 0.35;

    var shotLane = _laneWithHeight(shotDirection, height);
    final keeperStats = keeper.profile.goalkeeperStats;
    final saveSkill = (keeperStats.reaction * 0.34 +
            keeperStats.diving * 0.28 +
            keeperStats.oneVsOne * 0.24 +
            keeperStats.positioning * 0.14 +
            (keeper.profile.heightMeters - 1.70) * 0.25)
        .clamp(0.0, 1.0)
        .toDouble();

    // -------------------------------------------------------------------
    // 2) The verdict.
    // -------------------------------------------------------------------
    PenaltyOutcome outcome;
    var missAmount = 0.0;
    if (height > 2.44) {
      outcome = PenaltyOutcome.overBar;
      missAmount = 14 + error.abs() * 30;
    } else if (error > 0.58) {
      // Pushed wide of the post: the worse the strike, the further out.
      outcome = PenaltyOutcome.wide;
      missAmount = 8 + (error - 0.58) * 46 + (1 - accuracyQuality) * 10;
    } else {
      final guessedSameSide = _sameSide(shotLane, keeperDirection);
      var saveChance = guessedSameSide
          ? 0.26 + saveSkill * 0.34
          : 0.025 + saveSkill * 0.10;
      if (shotLane == PenaltyLane.center) {
        // A central penalty is a gift to any keeper who stands still.
        saveChance += 0.16;
      }
      if (keeperDirection == PenaltyLane.center &&
          shotLane != PenaltyLane.center) {
        saveChance -= 0.05;
      }
      // Hard, well-placed strikes are much harder to stop.
      saveChance *= 1.30 - powerQuality * 0.45;
      saveChance *= 1.0 - accuracyQuality * 0.22;
      // Nerves: a composed shooter adds % to the kick.
      saveChance *= 1.12 - profile.composureSkill * 0.20;
      saveChance = saveChance.clamp(0.02, 0.78).toDouble();
      outcome = random.nextDouble() < saveChance
          ? PenaltyOutcome.saved
          : PenaltyOutcome.goal;
    }

    // -------------------------------------------------------------------
    // 3) Keep the picture honest: if it is a goal the keeper went the wrong
    //    way (or was beaten by the pace), if it is a save he gets there.
    // -------------------------------------------------------------------
    var keeperLane = keeperDirection;
    if (outcome == PenaltyOutcome.goal &&
        _sameSide(shotLane, keeperDirection)) {
      keeperLane = _oppositeSideOf(shotLane);
    } else if (outcome == PenaltyOutcome.saved) {
      keeperLane = shotLane;
    }
    if (outcome == PenaltyOutcome.saved || outcome == PenaltyOutcome.goal) {
      // Nothing above the bar in a scored/kept penalty.
      height = height.clamp(0.30, 2.40).toDouble();
      shotLane = _laneWithHeight(shotLane, height);
    }

    return PenaltyKickResult(
      teamId: shootingTeam.id,
      shooterName: profile.name,
      goalkeeperName: keeper.profile.name,
      shotLane: shotLane,
      keeperLane: keeperLane,
      heightMeters: height,
      power: clampedPower,
      scored: outcome == PenaltyOutcome.goal,
      minute: minute,
      outcome: outcome,
      missAmount: missAmount,
      powerQuality: powerQuality,
      accuracyQuality: accuracyQuality,
    );
  }

  /// The mirrored lane used when the keeper is beaten.
  PenaltyLane _oppositeSideOf(PenaltyLane lane) => switch (lane) {
    PenaltyLane.leftLow => PenaltyLane.rightLow,
    PenaltyLane.leftHigh => PenaltyLane.rightHigh,
    PenaltyLane.rightLow => PenaltyLane.leftLow,
    PenaltyLane.rightHigh => PenaltyLane.leftHigh,
    PenaltyLane.center => PenaltyLane.center,
  };

  double _shooterValue(PlayerGame player) {
    final roleBonus = player.role.isAttacker
        ? 0.35
        : player.role.isWide
        ? 0.18
        : 0.08;
    return roleBonus +
        player.profile.heightMeters +
        player.profile.finishingSkill * 0.34 +
        player.profile.composureSkill * 0.26 +
        random.nextDouble() * 0.18;
  }

  PenaltyLane _chooseShotLane(PlayerGame shooter) {
    final highChance =
        (shooter.role.isAttacker ? 0.18 : 0.10) +
        shooter.profile.shotSkill * 0.08;
    if (random.nextDouble() < highChance) {
      return random.nextBool() ? PenaltyLane.leftHigh : PenaltyLane.rightHigh;
    }
    final roll = random.nextDouble();
    if (roll < 0.42) {
      return PenaltyLane.leftLow;
    }
    if (roll < 0.84) {
      return PenaltyLane.rightLow;
    }
    return PenaltyLane.center;
  }

  PenaltyLane _chooseKeeperLane(PlayerGame keeper, PenaltyLane shotLane) {
    final stats = keeper.profile.goalkeeperStats;
    final readSkill = stats.reaction * 0.40 +
        stats.anticipation * 0.34 +
        stats.oneVsOne * 0.26;
    final readChance =
        0.10 +
        (keeper.profile.heightMeters - 1.70) * 0.35 +
        readSkill * 0.36;
    if (random.nextDouble() < readChance) {
      return shotLane;
    }
    return PenaltyLane.values[random.nextInt(PenaltyLane.values.length)];
  }

  bool _sameSide(PenaltyLane a, PenaltyLane b) {
    if (a == PenaltyLane.center || b == PenaltyLane.center) {
      return a == b;
    }
    final aLeft = a == PenaltyLane.leftLow || a == PenaltyLane.leftHigh;
    final bLeft = b == PenaltyLane.leftLow || b == PenaltyLane.leftHigh;
    return aLeft == bLeft;
  }

  double _heightFromPower(double power, PenaltyLane direction) {
    if (direction == PenaltyLane.center) {
      return 0.35 + (power - 0.55) / 1.10 * 1.05;
    }
    return 0.45 + (power - 0.55) / 1.10 * 2.25;
  }

  PenaltyLane _laneWithHeight(PenaltyLane direction, double height) {
    if (direction == PenaltyLane.center) {
      return PenaltyLane.center;
    }
    final left =
        direction == PenaltyLane.leftLow || direction == PenaltyLane.leftHigh;
    if (height > 1.50) {
      return left ? PenaltyLane.leftHigh : PenaltyLane.rightHigh;
    }
    return left ? PenaltyLane.leftLow : PenaltyLane.rightLow;
  }
}
