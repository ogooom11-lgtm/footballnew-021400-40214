import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:new_football/src/game/config/game_constants.dart';
import 'package:new_football/src/game/enums/kick_type.dart';
import 'package:new_football/src/game/enums/match_mode.dart';
import 'package:new_football/src/game/enums/player_role.dart';
import 'package:new_football/src/game/enums/team_id.dart';
import 'package:new_football/src/game/logic/ball_physics.dart';
import 'package:new_football/src/game/logic/goalkeeper_prediction.dart';
import 'package:new_football/src/game/logic/match_engine.dart';
import 'package:new_football/src/game/logic/shot_calculator.dart';
import 'package:new_football/src/game/math/vec2.dart';
import 'package:new_football/src/game/models/ball_game.dart';
import 'package:new_football/src/game/models/formation.dart';
import 'package:new_football/src/game/models/goalkeeper.dart';
import 'package:new_football/src/game/models/jersey_kit.dart';
import 'package:new_football/src/game/models/match_event.dart';
import 'package:new_football/src/game/models/player_game.dart';
import 'package:new_football/src/game/models/player_profile.dart';
import 'package:new_football/src/game/models/shooting.dart';
import 'package:new_football/src/game/models/team_profile.dart';
import 'package:new_football/src/game/models/team_setup.dart';
import 'package:new_football/src/game/logic/penalty_logic.dart';
import 'package:new_football/src/game/tactics/tactical_engine.dart';
import 'package:new_football/src/game/tactics/team_play_state.dart';
import 'package:new_football/src/game/tactics/team_shape_kind.dart';
import 'package:new_football/src/storage/roster_storage.dart';

/// Builds a match setup from the default saved game (LIG MODU removed).
MatchSetup _testMatchSetup() {
  final data = SavedGameData.defaults();
  return MatchSetup(
    mode: MatchMode.knockout,
    blue: TeamSetup(
      id: TeamId.blue,
      name: data.blueName,
      formation: data.blueFormation,
      players: data.players
          .where((player) => data.bluePlayerIds.contains(player.id))
          .toList(),
      starterPlayerIds: data.blueTeam.starterPlayerIds,
      roleByPlayerId: data.blueTeam.roleByPlayerId,
      slotByPlayerId: data.blueTeam.slotByPlayerId,
      storageTeamId: data.blueTeam.id,
      rating: data.blueTeam.rating,
      jerseyKit: data.blueTeam.activeKit,
      goalkeeperKit: data.blueTeam.goalkeeperKit,
    ),
    red: TeamSetup(
      id: TeamId.red,
      name: data.redName,
      formation: data.redFormation,
      players: data.players
          .where((player) => data.redPlayerIds.contains(player.id))
          .toList(),
      starterPlayerIds: data.redTeam.starterPlayerIds,
      roleByPlayerId: data.redTeam.roleByPlayerId,
      slotByPlayerId: data.redTeam.slotByPlayerId,
      storageTeamId: data.redTeam.id,
      rating: data.redTeam.rating,
      jerseyKit: data.redTeam.activeKit,
      goalkeeperKit: data.redTeam.goalkeeperKit,
    ),
  );
}

void main() {
  group('match modes', () {
    test('both Eleme and Lig maci exist', () {
      expect(MatchMode.values.length, 2);
      expect(MatchMode.league.title, 'Lig maci');
      expect(MatchMode.knockout.title, 'Eleme');
    });
  });

  group('local account security', () {
    test('different passwords produce different hashes', () {
      expect(localPasswordHash('alpha'), isNot(localPasswordHash('bravo')));
      expect(localPasswordHash('alpha'), localPasswordHash(' alpha '));
    });
  });

  group('player availability', () {
    test('cards and match suspension survive JSON round trip', () {
      final player = PlayerProfile.generated(
        name: 'Test Player',
        isGoalkeeper: false,
      )
        ..dayaniklilikGucu = 88
        ..finishingRating = 84
        ..shotPowerRating = 91
        ..longShotsRating = 79
        ..curveRating = 82
        ..composureRating = 86
        ..balanceRating = 77
        ..goalkeeperReactionRating = 89
        ..goalkeeperPositioningRating = 87
        ..goalkeeperCatchingRating = 84
        ..goalkeeperParryingRating = 86
        ..preferredFoot = PreferredFoot.left
        ..weakFootRating = 4
        ..yellowCards = 4
        ..redCards = 1
        ..suspendedMatchesRemaining = 3
        ..injuredDaysRemaining = 14;

      final restored = PlayerProfile.fromJson(player.toJson());
      expect(restored.dayaniklilikGucu, 88);
      expect(restored.finishingRating, 84);
      expect(restored.shotPowerRating, 91);
      expect(restored.longShotsRating, 79);
      expect(restored.curveRating, 82);
      expect(restored.composureRating, 86);
      expect(restored.balanceRating, 77);
      expect(restored.goalkeeperReactionRating, 89);
      expect(restored.goalkeeperPositioningRating, 87);
      expect(restored.goalkeeperCatchingRating, 84);
      expect(restored.goalkeeperParryingRating, 86);
      expect(restored.preferredFoot, PreferredFoot.left);
      expect(restored.weakFootRating, 4);
      expect(restored.yellowCards, 4);
      expect(restored.redCards, 1);
      expect(restored.suspendedMatchesRemaining, 3);
      expect(restored.isUnavailable, isTrue);

      restored.advanceUnavailableStatusAfterTeamMatch();
      expect(restored.suspendedMatchesRemaining, 2);
      // A played match burns one real day of the injury, and one real day is
      // worth 3-5 injury days (Gereksinim).
      expect(
        restored.injuredDaysRemaining,
        math.max(0, 14 - player.injuryDaysPerRealDay),
      );
      expect(restored.injuryDaysPerRealDay, inInclusiveRange(3, 5));
    });
  });

  group('jersey kits', () {
    test('ships a wide palette of ready made kits', () {
      final kits = JerseyFactory.defaultKits();
      expect(kits.length, greaterThanOrEqualTo(13));
      expect(kits.map((kit) => kit.name).toSet().length, kits.length);
    });

    test('old saved kits are expanded without duplicates', () {
      final oldKits = JerseyFactory.defaultKits().take(3);
      final expanded = JerseyFactory.completeKits(oldKits);
      final expected = JerseyFactory.defaultKits().length;
      expect(expanded.length, expected);
      expect(expanded.map((kit) => kit.name).toSet().length, expected);
    });

    test('a deleted virtual kit never comes back', () {
      final deleted = JerseyFactory.defaultKits().first.name;
      final expanded = JerseyFactory.completeKits(
        JerseyFactory.defaultKits().skip(1).take(2),
        removed: [deleted],
      );
      expect(expanded.any((kit) => kit.name == deleted), isFalse);
      expect(expanded.length, JerseyFactory.defaultKits().length - 1);
    });

    test('a team always keeps at least one kit when everything is deleted',
        () {
      final expanded = JerseyFactory.completeKits(const [], removed: [
        'Ic Saha (Ev)',
        'Dis Saha (Deplasman)',
        'Alternatif',
      ]);
      expect(expanded, isNotEmpty);
    });

    test('the shirt palette offers extra colors for new kits', () {
      expect(JerseyFactory.kitColorPalette.length, greaterThanOrEqualTo(20));
      expect(JerseyFactory.kitColorPalette.contains(const Color(0xff101820)),
          isTrue);
    });

    test('removed kit names survive the JSON round trip', () {
      final team = SavedTeamProfile.create(
        ownerAccountId: 'owner',
        name: 'Kitspor',
        playerIds: const [],
      )..removedKitNames = ['Alternatif'];
      final restored = SavedTeamProfile.fromJson(team.toJson());
      expect(restored.removedKitNames, contains('Alternatif'));
      expect(
        restored.jerseyKits.any((kit) => kit.name == 'Alternatif'),
        isFalse,
      );
    });
  });

  group('realistic shot calculator', () {
    const weak = PlayerShootingStats(
      shooting: 0.55,
      finishing: 0.50,
      shotPower: 0.65,
      longShots: 0.40,
      curve: 0.35,
      composure: 0.35,
      balance: 0.45,
      preferredFoot: PreferredFoot.right,
      weakFoot: 2,
    );
    const worldClass = PlayerShootingStats(
      shooting: 0.94,
      finishing: 0.94,
      shotPower: 0.94,
      longShots: 0.91,
      curve: 0.91,
      composure: 0.94,
      balance: 0.93,
      preferredFoot: PreferredFoot.right,
      weakFoot: 5,
    );

    ShotContext context(
      PlayerShootingStats stats, {
      double distance = 18,
      ShotType type = ShotType.normal,
      double pressure = 4,
    }) {
      return ShotContext(
        stats: stats,
        playerPosition: Vec2(300, 350),
        intendedTarget: Vec2(1150, 320),
        facingAngleDegrees: 10,
        distanceMeters: distance,
        nearestDefenderMeters: pressure,
        movementRatio: 0.45,
        sprinting: false,
        turning: false,
        incomingBallSpeed: 0,
        ballHeight: 0,
        bodyLean: 0,
        supportFootQuality: 0.9,
        usingPreferredFoot: true,
        firstTime: false,
        fatigue: 0.1,
        powerInput: 0.68,
        shotType: type,
        goalWidthPixels: GameConstants.goalPixelHeight,
        freeKick: false,
      );
    }

    test('level presets match the supplied shooting plan', () {
      final weakPreset = PlayerShootingStats.forLevel(PlayerLevel.weak);
      final worldPreset = PlayerShootingStats.forLevel(PlayerLevel.worldClass);
      expect(weakPreset.shooting, 0.55);
      expect(weakPreset.shotPower, 0.65);
      expect(worldPreset.finishing, 0.94);
      expect(worldPreset.longShots, 0.91);
      expect(worldPreset.balance, 0.93);
    });

    test('world-class players produce a tighter Gaussian spread', () {
      final weakCalculator = ShotCalculator(math.Random(11));
      final worldCalculator = ShotCalculator(math.Random(11));
      var weakError = 0.0;
      var worldError = 0.0;
      for (var index = 0; index < 1000; index++) {
        weakError += weakCalculator.calculate(context(weak)).lateralError.abs();
        worldError += worldCalculator
            .calculate(context(worldClass))
            .lateralError
            .abs();
      }
      expect(worldError / 1000, lessThan(weakError / 1000));
    });

    test('curve is executed by ball physics instead of changing accuracy', () {
      final shooter = PlayerGame(
        profile: PlayerProfile.generated(name: 'Curve', isGoalkeeper: false),
        teamId: TeamId.blue,
        role: PlayerRole.striker,
        number: 9,
        position: Vec2(200, 350),
      );
      final ball = BallGame(pos: Vec2(210, 350));
      ball.release(
        direction: Vec2(1, 0),
        power: 1,
        toucher: shooter,
        kickType: KickType.shoot,
        curve: 2,
        spin: 2,
        shotType: ShotType.finesse,
      );
      const BallPhysics().update(ball, 1 / 60);
      expect(ball.vel.y, greaterThan(0));
      expect(ball.curve, lessThan(2));
    });

    test('distance and shot type affect accuracy, height and power', () {
      final calculator = ShotCalculator(math.Random(19));
      final close = calculator.calculate(context(worldClass, distance: 10));
      final far = calculator.calculate(context(worldClass, distance: 32));
      final ground = calculator.calculate(
        context(worldClass, type: ShotType.ground),
      );
      final power = calculator.calculate(
        context(worldClass, type: ShotType.power),
      );
      expect(close.accuracy, greaterThan(far.accuracy));
      expect(ground.targetHeight, lessThan(power.targetHeight));
      expect(power.power, greaterThan(ground.power));
    });
  });

  group('goalkeeper prediction model', () {
    GoalkeeperContext context({double ballY = 350, double curve = 0}) {
      return GoalkeeperContext(
        goalkeeperPosition: Vec2(68, 350),
        goalkeeperHeight: 1.88,
        goalCenter: Vec2(68, 350),
        goalTop: 285,
        goalBottom: 415,
        goalLineX: 68,
        ballPosition: Vec2(300, ballY),
        ballVelocity: Vec2(-6, 0),
        ballHeight: 0.6,
        ballVerticalVelocity: 1.2,
        ballCurve: curve,
        shotType: ShotType.normal,
        shooterPosition: Vec2(310, 350),
        nearestDefenderDistance: 3,
        numberOfAttackers: 1,
        isBallOwned: false,
        isCross: false,
        isOneVsOne: false,
        isThroughBall: false,
        isCorner: false,
        isFreeKick: false,
        visibilityFactor: 1,
        fatigue: 0,
      );
    }

    test('goalkeeper level presets match the supplied plan', () {
      final weak = GoalkeeperStats.forLevel(PlayerLevel.weak);
      final world = GoalkeeperStats.forLevel(PlayerLevel.worldClass);
      expect(weak.reaction, 0.45);
      expect(weak.catching, 0.40);
      expect(world.positioning, 0.96);
      expect(world.diving, 0.96);
      expect(world.highBalls, 0.94);
    });

    test('world-class prediction has tighter human error and confidence', () {
      final weakStats = GoalkeeperStats.forLevel(PlayerLevel.weak);
      final worldStats = GoalkeeperStats.forLevel(PlayerLevel.worldClass);
      final weakPredictor = GoalkeeperPredictor(math.Random(31));
      final worldPredictor = GoalkeeperPredictor(math.Random(31));
      var weakError = 0.0;
      var worldError = 0.0;
      var weakConfidence = 0.0;
      var worldConfidence = 0.0;
      for (var index = 0; index < 1000; index++) {
        final weak = weakPredictor.predict(weakStats, context());
        final world = worldPredictor.predict(worldStats, context());
        weakError += (weak.predictedImpact.y - 350).abs();
        worldError += (world.predictedImpact.y - 350).abs();
        weakConfidence += weak.confidence;
        worldConfidence += world.confidence;
      }
      expect(worldError, lessThan(weakError));
      expect(worldConfidence, greaterThan(weakConfidence));
    });
  });

  group('goalkeeper recovery', () {
    test('keeper moves only during the dive and stays locked after landing', () {
      final profile = PlayerProfile.generated(
        name: 'Recovery Keeper',
        isGoalkeeper: true,
      )..speedRating = 80;
      final keeper = PlayerGame(
        profile: profile,
        teamId: TeamId.blue,
        role: PlayerRole.goalkeeper,
        number: 1,
        position: Vec2.zero(),
      );
      final standingSpeed = keeper.speed;

      keeper
        ..keeperState = 'atlayis'
        ..keeperGroundTimer = 1.4
        ..jumpAnimationTimer = 0.62;
      final diveSpeed = keeper.speed;
      expect(diveSpeed, greaterThan(0));
      expect(diveSpeed, lessThan(standingSpeed));

      keeper
        ..keeperState = 'yerde'
        ..jumpAnimationTimer = 0.05;
      expect(keeper.speed, 0);

      keeper.keeperGroundTimer = 0;
      expect(keeper.speed, standingSpeed);
    });

    test('keeper cannot distribute while down or recollect his own release', () {
      final setup = _testMatchSetup();
      final engine = MatchEngine(setup);
      final keeper = engine.blueTeam.goalkeeper;
      engine.ball.attachTo(keeper);

      keeper.keeperGroundTimer = 1.2;
      expect(
        engine.distributeFromGoalkeeper(keeper, high: false),
        isFalse,
      );
      expect(engine.ball.owner, keeper);

      keeper.keeperGroundTimer = 0;
      expect(
        engine.distributeFromGoalkeeper(keeper, high: false),
        isTrue,
      );
      expect(engine.ball.owner, isNull);
      expect(engine.ball.lastTouch, keeper);
      expect(keeper.keeperRehandleCooldown, greaterThanOrEqualTo(1.35));
    });
  });

  group('discipline and substitutions', () {
    test('red cards always carry a suspension for the next match', () {
      expect(GameConstants.redCardSuspensionMatches, greaterThanOrEqualTo(1));
      final player = PlayerProfile.generated(
        name: 'Kirmizi',
        isGoalkeeper: false,
      )..suspendedMatchesRemaining = GameConstants.redCardSuspensionMatches;
      expect(player.isBanned, isTrue);
    });

    test('position swaps are free and injury bonus raises the limit', () {
      final setup = _testMatchSetup();
      final engine = MatchEngine(setup);
      final team = engine.blueTeam;
      final firstProfile = team.players[1].profile;
      final secondProfile = team.players[2].profile;

      expect(team.swapPlayerPositions(1, 2), isTrue);
      expect(team.players[1].profile, secondProfile);
      expect(team.players[2].profile, firstProfile);
      expect(team.substitutionsUsed, 0);
      expect(team.substitutionLimit, 5);

      team
        ..substitutionsUsed = 5
        ..bonusSubstitutions = 1;
      expect(team.substitutionLimit, 6);
      final fieldBenchIndex = team.bench.indexWhere(
        (player) => !player.profile.isGoalkeeper,
      );
      expect(fieldBenchIndex, greaterThanOrEqualTo(0));
      expect(team.substitute(1, fieldBenchIndex), isTrue);
      expect(team.substitutionsUsed, 6);
    });
  });

  group('saved formations', () {
    test('assigns unique compatible slots and restores a named preset', () {
      final players = [
        PlayerProfile.generated(name: 'Keeper', isGoalkeeper: true),
        for (var index = 0; index < 10; index++)
          PlayerProfile.generated(name: 'Player $index', isGoalkeeper: false),
      ];
      final team = SavedTeamProfile.create(
        ownerAccountId: 'owner',
        name: 'Test Team',
        playerIds: players.map((player) => player.id),
        formation: FormationType.wing433,
      );
      team.ensureLineupDefaults(players);

      expect(team.slotByPlayerId.length, 11);
      expect(team.slotByPlayerId.values.toSet().length, 11);
      final plan = formationPlan(team.formation);
      for (final entry in team.slotByPlayerId.entries) {
        final player = players.firstWhere((item) => item.id == entry.key);
        expect(
          plan.spots[entry.value].role.isGoalkeeper,
          player.isGoalkeeper,
        );
      }

      final preset = team.saveCurrentFormation('Best Eleven');
      team
        ..formation = FormationType.classic442
        ..slotByPlayerId.clear();
      team.applyFormationPreset(preset);
      team.ensureLineupDefaults(players);
      expect(team.formation, FormationType.wing433);
      expect(team.activeFormationPresetId, preset.id);
      expect(team.slotByPlayerId.length, 11);

      final restored = SavedTeamProfile.fromJson(
        team.toJson(),
        fallbackOwnerAccountId: 'owner',
      );
      expect(restored.savedFormations.single.name, 'Best Eleven');
      expect(restored.slotByPlayerId, team.slotByPlayerId);
    });
  });

  group('match archive', () {
    test('preserves real goals and complete player performance', () {
      final summary = FinishedMatchSummary(
        matchId: 'match-1',
        blueStorageTeamId: 'blue-team',
        redStorageTeamId: 'red-team',
        blueName: 'Blue',
        redName: 'Red',
        blueScore: 1,
        redScore: 0,
        blueRatingDelta: 1.2,
        redRatingDelta: -1.2,
        bluePossessionPercent: 55,
        redPossessionPercent: 45,
        bluePasses: 400,
        redPasses: 350,
        blueSuccessfulPasses: 330,
        redSuccessfulPasses: 270,
        blueShots: 9,
        redShots: 6,
        timestamp: 123456,
        goals: const [
          FinishedGoalSummary(
            teamId: TeamId.blue,
            scorerName: 'Real Scorer',
            minute: 37,
            isPenalty: false,
          ),
        ],
        playerStats: const [
          FinishedPlayerSummary(
            playerId: 'player-1',
            teamId: TeamId.blue,
            name: 'Real Scorer',
            number: 9,
            role: 'SF',
            minutes: 90,
            goals: 1,
            assists: 0,
            passes: 31,
            successfulPasses: 25,
            dribbles: 4,
            successfulDribbles: 3,
            tackles: 1,
            shots: 4,
            shotsOnTarget: 2,
            missedChances: 1,
            clearances: 0,
            saves: 0,
            foulsCommitted: 1,
            foulsReceived: 2,
            yellowCards: 0,
            redCards: 0,
            rating: 8.2,
            staminaPercent: 72,
            injured: false,
          ),
        ],
      );

      final restored = FinishedMatchSummary.fromJson(summary.toJson());
      expect(restored.goals.single.scorerName, 'Real Scorer');
      expect(restored.goals.single.minute, 37);
      expect(restored.playerStats.single.shotsOnTarget, 2);
      expect(restored.playerStats.single.rating, 8.2);

      final data = SavedGameData.defaults();
      data.archiveMatch(summary);
      final restoredData = SavedGameData.fromJson(data.toJson());
      expect(restoredData.matchArchive.single.matchId, 'match-1');
    });
  });

  group('shot speed realism', () {
    test('shots are clearly faster than passes', () {
      final engine = MatchEngine(_testMatchSetup());
      final shooter = engine.blueTeam.players[1];
      shooter.profile.shotPowerRating = 70;
      shooter.profile.passingRating = 70;
      engine.ball
        ..owner = shooter
        ..pos = shooter.pos.copy();
      engine.releaseFromPlayer(
        shooter,
        Vec2(1, 0),
        1.0,
        type: KickType.shoot,
      );
      final shotSpeed = engine.ball.vel.length;

      final passer = engine.blueTeam.players[2];
      engine.ball
        ..owner = passer
        ..pos = passer.pos.copy();
      engine.releaseFromPlayer(
        passer,
        Vec2(1, 0),
        1.0,
        type: KickType.pass,
      );
      final passSpeed = engine.ball.vel.length;
      expect(shotSpeed, greaterThan(passSpeed));
    });

    test('shot speed scales with shot power rating', () {
      final weak = MatchEngine(_testMatchSetup());
      final weakShooter = weak.blueTeam.players[1];
      weakShooter.profile.shotPowerRating = 30;
      weak.ball
        ..owner = weakShooter
        ..pos = weakShooter.pos.copy();
      weak.releaseFromPlayer(
        weakShooter,
        Vec2(1, 0),
        1.0,
        type: KickType.shoot,
      );
      final weakSpeed = weak.ball.vel.length;

      final strong = MatchEngine(_testMatchSetup());
      final strongShooter = strong.blueTeam.players[1];
      strongShooter.profile.shotPowerRating = 95;
      strong.ball
        ..owner = strongShooter
        ..pos = strongShooter.pos.copy();
      strong.releaseFromPlayer(
        strongShooter,
        Vec2(1, 0),
        1.0,
        type: KickType.shoot,
      );
      final strongSpeed = strong.ball.vel.length;
      expect(strongSpeed, greaterThan(weakSpeed * 1.08));
    });

    test('high pass keeps a forward cruise speed while airborne', () {
      final engine = MatchEngine(_testMatchSetup());
      final passer = engine.blueTeam.players[1];
      engine.ball
        ..owner = passer
        ..pos = passer.pos.copy();
      engine.releaseFromPlayer(
        passer,
        Vec2(1, 0),
        1.0,
        type: KickType.highPass,
        loft: 5.0,
      );
      expect(engine.ball.highPassCruiseSpeed, greaterThan(0));
      expect(engine.ball.lastPassWasHigh, isTrue);
    });
  });

  group('clean pass tracking', () {
    test('opponent touch clears the clean-pass marker', () {
      final engine = MatchEngine(_testMatchSetup());
      final passer = engine.blueTeam.players[1];
      final receiver = engine.blueTeam.players[2];
      final opponent = engine.redTeam.players.firstWhere(
        (player) => !player.isGoalkeeper,
      );
      engine.ball
        ..owner = passer
        ..pos = passer.pos.copy();
      engine.releaseFromPlayer(
        passer,
        receiver.pos - passer.pos,
        0.8,
        type: KickType.pass,
        target: receiver,
      );
      expect(engine.ball.potentialAssister, passer);
      engine.ball.attachTo(opponent);
      expect(engine.ball.potentialAssister, isNull);
    });
  });

  group('market value', () {
    test('fresh players start at 1 billion and stay until they play', () {
      final player = PlayerProfile.generated(name: 'New', isGoalkeeper: false);
      expect(player.marketValue, 1000000000);
      player.recalculateMarketValue(strong: false);
      expect(player.marketValue, 1000000000);
      player.recalculateMarketValue(strong: true);
      expect(player.marketValue, 1000000000);
    });

    test('good performances raise the value, strong moves it more', () {
      final player = PlayerProfile.generated(name: 'Star', isGoalkeeper: false);
      player
        ..matchesPlayed = 10
        ..minutesPlayed = 900
        ..goals = 12
        ..assists = 4
        ..points = 82
        ..addMatchRecord(
          PlayerMatchRecord(
            matchId: 'm1',
            teamName: 'T',
            opponentName: 'O',
            scoreText: '2-0',
            minutes: 90,
            goals: 2,
            assists: 1,
            passes: 30,
            successfulPasses: 25,
            dribbles: 4,
            successfulDribbles: 3,
            tackles: 1,
            shots: 5,
            shotsOnTarget: 3,
            missedChances: 1,
            clearances: 0,
            saves: 0,
            foulsCommitted: 1,
            foulsReceived: 2,
            yellowCards: 0,
            redCards: 0,
            rating: 8.5,
            injured: false,
          ),
        );
      player.recalculateMarketValue(strong: false);
      final lightValue = player.marketValue;
      expect(lightValue, greaterThan(1000000000));
      player.recalculateMarketValue(strong: true);
      expect(player.marketValue, greaterThan(lightValue));
      expect(player.marketValueText, isNotEmpty);
      expect(player.marketValueFull, isNotEmpty);
    });

    test('market value survives JSON round trip', () {
      final player = PlayerProfile.generated(name: 'P', isGoalkeeper: true)
        ..marketValue = 7500000000;
      final restored = PlayerProfile.fromJson(player.toJson());
      expect(restored.marketValue, 7500000000);
    });
  });

  group('controlled player switching', () {
    test('ball owner is always controlled when the team has the ball', () {
      final engine = MatchEngine(_testMatchSetup());
      final owner = engine.blueTeam.players[3];
      engine.ball.attachTo(owner);
      expect(engine.controlledPlayer(TeamId.blue), owner);
    });

    test('manual switch cycles to the next chaser when defending', () {
      final engine = MatchEngine(_testMatchSetup());
      // Give the ball to the opponent so blue defends.
      final redCarrier = engine.redTeam.players[2];
      engine.ball.attachTo(redCarrier);
      final first = engine.controlledPlayer(TeamId.blue);
      final second = engine.switchControlledPlayer(TeamId.blue);
      expect(second.id, isNot(first.id));
      final third = engine.switchControlledPlayer(TeamId.blue);
      expect(third.id, isNot(second.id));
      engine.toggleAutoSwitch(TeamId.blue);
      final manual = engine.controlledPlayer(TeamId.blue);
      expect(manual.id, third.id);
    });

    test('toggle auto switch flips the flag per team', () {
      final engine = MatchEngine(_testMatchSetup());
      expect(engine.isAutoSwitchEnabled(TeamId.blue), isTrue);
      expect(engine.isAutoSwitchEnabled(TeamId.red), isTrue);
      engine.toggleAutoSwitch(TeamId.blue);
      expect(engine.isAutoSwitchEnabled(TeamId.blue), isFalse);
      expect(engine.isAutoSwitchEnabled(TeamId.red), isTrue);
      engine.toggleAutoSwitch(TeamId.blue);
      expect(engine.isAutoSwitchEnabled(TeamId.blue), isTrue);
      engine.toggleAutoSwitch(TeamId.red);
      expect(engine.isAutoSwitchEnabled(TeamId.red), isFalse);
    });
  });

  group('substitution undo', () {
    test('undo restores the outgoing player and refunds the slot', () {
      final team = MatchEngine(_testMatchSetup()).blueTeam;
      expect(team.substitutionLog, isEmpty);
      final outgoing = team.players[1];
      final benchIndex = team.bench.indexWhere(
        (player) => !player.profile.isGoalkeeper,
      );
      expect(benchIndex, greaterThanOrEqualTo(0));
      expect(team.substitute(1, benchIndex, minute: 30), isTrue);
      expect(team.substitutionsUsed, 1);
      expect(team.substitutionLog.length, 1);
      expect(team.substitutedOut.length, 1);
      expect(team.players[1].profile, isNot(outgoing.profile));

      expect(team.undoLastSubstitution(), isTrue);
      expect(team.substitutionsUsed, 0);
      expect(team.substitutionLog, isEmpty);
      expect(team.players[1].profile, outgoing.profile);
      expect(team.bench.length, greaterThanOrEqualTo(1));
    });
  });

  group('transfer requests', () {
    test('pending request marks a player as reserved', () {
      final data = SavedGameData.defaults();
      final player = data.players.first;
      final team = data.teams.first;
      data.transferRequests.add(
        TransferRequest.create(
          playerId: player.id,
          targetTeamId: team.id,
          requesterAccountId: data.activeAccountId,
        ),
      );
      final request = data.transferRequestFor(player.id);
      expect(request, isNotNull);
      expect(request!.isPending, isTrue);
      expect(data.pendingTransfers.length, 1);
    });

    test('transfer requests survive JSON round trip', () {
      final data = SavedGameData.defaults();
      data.transferRequests.add(
        TransferRequest.create(
          playerId: 'p1',
          targetTeamId: 't1',
          requesterAccountId: 'a1',
        ),
      );
      final restored = SavedGameData.fromJson(data.toJson());
      expect(restored.transferRequests.length, 1);
      expect(restored.transferRequests.single.playerId, 'p1');
      expect(restored.transferRequests.single.status, 'pending');
    });
  });

  group('daily injury recovery', () {
    test('one real day removes three to five injury days', () {
      final player = PlayerProfile.generated(name: 'Hasta', isGoalkeeper: false);
      final now = DateTime.now();
      player
        ..injuredDaysRemaining = 20
        ..injuryUpdatedAt = now
            .subtract(const Duration(days: 3))
            .millisecondsSinceEpoch;
      expect(player.recoverInjuryDays(now), isTrue);
      expect(player.injuredDaysRemaining, 20 - 3 * player.injuryDaysPerRealDay);
      // Same day again: no double recovery.
      expect(player.recoverInjuryDays(now), isFalse);
    });

    test('the injury day speed stays inside the 3-5 band', () {
      final player = PlayerProfile.generated(name: 'Hasta', isGoalkeeper: false);
      expect(player.injuryDaysPerRealDay, inInclusiveRange(3, 5));
      player.dayaniklilikGucu = 100;
      expect(player.injuryDaysPerRealDay, 5);
      player.dayaniklilikGucu = 1;
      expect(player.injuryDaysPerRealDay, 3);
    });

    test('an injury registers its date, duration and end date', () {
      final player = PlayerProfile.generated(name: 'Hasta', isGoalkeeper: false);
      final start = DateTime(2026, 3, 1, 12);
      player.registerInjury(days: 30, at: start);
      expect(player.injuredDaysRemaining, 30);
      expect(player.injuryDurationDays, 30);
      expect(player.injuryStartedAt, start.millisecondsSinceEpoch);
      expect(player.injuryDateText, '01.03.2026');
      expect(player.injuryEndsAt, greaterThan(start.millisecondsSinceEpoch));
      expect(player.injuryEndText, isNot('-'));
      expect(player.injuryProgress, 0);
    });

    test('a healed injury clears its end date', () {
      final player = PlayerProfile.generated(name: 'Hasta', isGoalkeeper: false);
      final now = DateTime(2026, 3, 1);
      player.registerInjury(days: 4, at: now);
      expect(player.recoverInjuryDays(now.add(const Duration(days: 2))), isTrue);
      expect(player.injuredDaysRemaining, 0);
      expect(player.injuryEndsAt, 0);
      expect(player.injuryEndText, '-');
    });

    test('injury fields survive JSON round trip', () {
      final player = PlayerProfile.generated(name: 'Hasta', isGoalkeeper: false)
        ..registerInjury(days: 12, at: DateTime(2026, 1, 2));
      final restored = PlayerProfile.fromJson(player.toJson());
      expect(restored.injuredDaysRemaining, 12);
      expect(restored.injuryDurationDays, 12);
      expect(restored.injuryStartedAt, player.injuryStartedAt);
      expect(restored.injuryEndsAt, player.injuryEndsAt);
      expect(restored.injuryDateText, player.injuryDateText);
    });
  });

  group('ban fields for penalties page', () {
    test('banMatches/isBanned stay in sync with suspension', () {
      final player = PlayerProfile.generated(
        name: 'Banned',
        isGoalkeeper: false,
      );
      expect(player.isBanned, isFalse);
      player.banMatches = 4;
      expect(player.banMatches, 4);
      expect(player.suspendedMatchesRemaining, 4);
      expect(player.isBanned, isTrue);
      player.banMatches = 0;
      expect(player.isBanned, isFalse);
    });
  });
  group('offside line and defending discipline', () {
    test('the defensive line retreats with the ball while defending', () {
      const engine = TacticalEngine();
      final setup = _testMatchSetup();
      final match = MatchEngine(setup);
      final blue = match.blueTeam;
      // Ball deep in the blue half, red attacking: the blue block must sit
      // goal-side of the ball, never in front of the carrier.
      match.ball.pos = Vec2(GameConstants.leftBound + 120, 350);
      final context = engine.evaluate(
        engine: match,
        team: blue,
        playState: TeamPlayState.organizedDefense,
        shapeKind: TeamShapeKind.defensive,
      );
      final ballFraction =
          (match.ball.pos.x - GameConstants.leftBound) / GameConstants.pitchWidth;
      final lineFraction =
          (context.defensiveLineX - GameConstants.leftBound) /
              GameConstants.pitchWidth;
      expect(lineFraction, lessThanOrEqualTo(ballFraction));
    });

    test('the double defence key digs the block deeper than the press key',
        () {
      const engine = TacticalEngine();
      final match = MatchEngine(_testMatchSetup());
      final setup = _testMatchSetup();
      final blue = match.blueTeam;
      match.ball.pos = Vec2(GameConstants.virtualWidth / 2 + 60, 350);
      match.setTacticalOverride(TeamId.blue, TeamMode.defense);
      final deep = engine.evaluate(
        engine: match,
        team: blue,
        playState: TeamPlayState.organizedDefense,
        shapeKind: TeamShapeKind.defensive,
      );
      match.setTacticalOverride(TeamId.blue, TeamMode.press);
      final high = engine.evaluate(
        engine: match,
        team: blue,
        playState: TeamPlayState.organizedDefense,
        shapeKind: TeamShapeKind.defensive,
      );
      expect(deep.lineHeight, lessThan(high.lineHeight));
      expect(setup.mode, MatchMode.knockout);
    });

    test('the letter keys drive the tactical intensity', () {
      final match = MatchEngine(_testMatchSetup());
      expect(match.tacticalIntensityFor(TeamId.blue), 1.0);
      match.setTacticalOverride(TeamId.blue, TeamMode.press);
      expect(match.tacticalIntensityFor(TeamId.blue), greaterThan(1.0));
      expect(match.secondPresserAllowedFor(TeamId.blue), isTrue);
      match.setTacticalOverride(TeamId.blue, TeamMode.defense);
      expect(match.tacticalIntensityFor(TeamId.blue), lessThan(1.0));
      expect(match.secondPresserAllowedFor(TeamId.blue), isFalse);
    });
  });

  group('goal kick discipline', () {
    test('opponents are pushed out of the box during a goal kick', () {
      final match = MatchEngine(_testMatchSetup());
      final opponent = match.redTeam.players.firstWhere(
        (player) => !player.isGoalkeeper,
      );
      // Put a red player right in front of the blue goal, then announce a
      // blue goal kick: he must be moved out of the penalty area.
      opponent.pos = Vec2(GameConstants.leftBound + 70, 350);
      match.ball.pos = Vec2(GameConstants.leftBound + 58, 350);
      match.ball.vel = Vec2.zero();
      match.restartKind = RestartKind.goalKick;
      match.restartTeamId = TeamId.blue;
      expect(match.isGoalKickLockedAgainst(TeamId.red), isTrue);
      match.tick(0.016);
      expect(match.isInPenaltyBox(opponent.pos, TeamId.blue), isFalse);
    });
  });

  group('possession duels', () {
    test('duel strength follows balance, stamina, physique and intelligence',
        () {
      final weak = PlayerProfile.generated(
        name: 'Zayif',
        isGoalkeeper: false,
      )
        ..balanceRating = 30
        ..zekaGucu = 20;
      final strong = PlayerProfile.generated(
        name: 'Guclu',
        isGoalkeeper: false,
      )
        ..balanceRating = 92
        ..zekaGucu = 95;
      final weakGame = PlayerGame(
        profile: weak,
        teamId: TeamId.blue,
        role: PlayerRole.attackingMidfielder,
        number: 8,
        position: Vec2(300, 300),
      );
      final strongGame = PlayerGame(
        profile: strong,
        teamId: TeamId.red,
        role: PlayerRole.attackingMidfielder,
        number: 6,
        position: Vec2(320, 300),
      );
      expect(strongGame.duelStrength, greaterThan(weakGame.duelStrength));
      expect(strongGame.zekaFactor, closeTo(0.95, 0.001));
    });

    test('losing the ball starts a short control cooldown', () {
      final match = MatchEngine(_testMatchSetup());
      final player = match.blueTeam.players.firstWhere(
        (candidate) => !candidate.isGoalkeeper,
      )..ballControlCooldown = 0.4;
      match.tick(0.05);
      // The engine ticks the cooldown down instead of leaving it frozen, so
      // the man who just lost the ball cannot steal it straight back.
      expect(player.ballControlCooldown, lessThan(0.4));
    });
  });

  group('jump and landing', () {
    test('jumping costs a short landing recovery before sprinting again', () {
      final profile = PlayerProfile.generated(
        name: 'Zipla',
        isGoalkeeper: false,
      );
      final player = PlayerGame(
        profile: profile,
        teamId: TeamId.blue,
        role: PlayerRole.rightWing,
        number: 7,
        position: Vec2(400, 350),
      );
      final freshSpeed = player.speed;
      player.landingRecoveryTimer = 0.5;
      expect(player.landingFactor, lessThan(0.6));
      expect(player.speed, lessThan(freshSpeed));
      player.landingRecoveryTimer = 0;
      expect(player.landingFactor, 1.0);
    });
  });

  group('keeper control lock', () {
    test('a keeper who catches the ball is locked until the keys are released',
        () {
      final match = MatchEngine(_testMatchSetup());
      match.tick(0.016);
      expect(match.keeperControlLockedFor(TeamId.blue), isFalse);
      final keeper = match.blueTeam.goalkeeper;
      match.ball.attachTo(keeper);
      match.tick(0.016);
      // The keeper just won the ball: the player must lift his fingers.
      expect(match.keeperControlLockedFor(TeamId.blue), isTrue);
      match.releaseKeeperControlLock(TeamId.blue);
      expect(match.keeperControlLockedFor(TeamId.blue), isFalse);
    });
  });

  group('realistic penalties', () {
    test('a well struck, well placed penalty beats a poor one', () {
      final random = math.Random(7);
      final logic = PenaltyLogic(random);
      final match = MatchEngine(_testMatchSetup());
      final shooter = match.blueTeam.players.firstWhere(
        (player) => !player.isGoalkeeper,
      )
        ..profile.finishingRating = 95
        ..profile.composureRating = 95
        ..profile.shootingRating = 95;
      var goals = 0;
      for (var i = 0; i < 400; i++) {
        final result = logic.takeSelectedKick(
          shootingTeam: match.blueTeam,
          defendingTeam: match.redTeam,
          kickIndex: 0,
          minute: 90,
          shotDirection: PenaltyLane.leftLow,
          keeperDirection: PenaltyLane.rightLow,
          power: 1.18,
          selectedShooter: shooter,
        );
        if (result.scored) {
          goals += 1;
        }
        // The picture must always match the verdict.
        if (result.outcome == PenaltyOutcome.goal) {
          final keeperSameSide =
              result.keeperLane == PenaltyLane.leftLow ||
              result.keeperLane == PenaltyLane.leftHigh;
          expect(keeperSameSide, isFalse);
        }
        if (result.outcome == PenaltyOutcome.saved) {
          expect(result.scored, isFalse);
          final shotLeft = result.shotLane == PenaltyLane.leftLow ||
              result.shotLane == PenaltyLane.leftHigh ||
              result.shotLane == PenaltyLane.center;
          final keeperLeft = result.keeperLane == PenaltyLane.leftLow ||
              result.keeperLane == PenaltyLane.leftHigh ||
              result.keeperLane == PenaltyLane.center;
          expect(shotLeft, keeperLeft);
        }
        if (result.outcome == PenaltyOutcome.overBar) {
          expect(result.heightMeters, greaterThan(2.44));
        }
      }
      // Not every penalty may be a goal, and the good taker must still
      // convert the majority of them.
      expect(goals, greaterThan(200));
      expect(goals, lessThan(400));
    });

    test('power, accuracy and finishing all move the conversion rate', () {
      final logic = PenaltyLogic(math.Random(11));
      final match = MatchEngine(_testMatchSetup());
      final shooter = match.blueTeam.players.firstWhere(
        (player) => !player.isGoalkeeper,
      )
        ..profile.finishingRating = 20
        ..profile.composureRating = 20
        ..profile.shootingRating = 20;
      var weakGoals = 0;
      for (var i = 0; i < 300; i++) {
        final result = logic.takeSelectedKick(
          shootingTeam: match.blueTeam,
          defendingTeam: match.redTeam,
          kickIndex: 0,
          minute: 90,
          shotDirection: PenaltyLane.center,
          keeperDirection: PenaltyLane.center,
          power: 0.62,
          selectedShooter: shooter,
        );
        if (result.scored) {
          weakGoals += 1;
        }
      }
      shooter.profile
        ..finishingRating = 96
        ..composureRating = 96
        ..shootingRating = 96;
      var strongGoals = 0;
      for (var i = 0; i < 300; i++) {
        final result = logic.takeSelectedKick(
          shootingTeam: match.blueTeam,
          defendingTeam: match.redTeam,
          kickIndex: 0,
          minute: 90,
          shotDirection: PenaltyLane.leftLow,
          keeperDirection: PenaltyLane.leftLow,
          power: 1.2,
          selectedShooter: shooter,
        );
        if (result.scored) {
          strongGoals += 1;
        }
      }
      expect(strongGoals, greaterThan(weakGoals));
    });
  });

  group('passing into space', () {
    test('a pass with nobody in the aimed direction flies that way', () {
      final match = MatchEngine(_testMatchSetup());
      final player = match.blueTeam.players.firstWhere(
        (candidate) => !candidate.isGoalkeeper,
      );
      // Every team-mate drops behind the carrier: the cone in front of him
      // is empty, so there is simply no one to pass to.
      for (final mate in match.blueTeam.players) {
        if (mate == player) {
          continue;
        }
        mate.pos = Vec2(GameConstants.leftBound + 40, 200 + mate.number * 6);
      }
      player.pos = Vec2(GameConstants.virtualWidth / 2, 350);
      player.lastDirection = Vec2(0, -1);
      match.ball
        ..attachTo(player)
        ..pos = player.pos.copy();

      match.manualKick(TeamId.blue, KickType.pass, 0.8);

      expect(match.ball.owner, isNull);
      expect(match.ball.vel.length, greaterThan(0));
      final flight = match.ball.vel.normalized();
      // The ball travels where the player aimed instead of turning back to
      // the nearest shirt behind him (Gereksinim).
      expect(flight.y, lessThan(-0.9));
      expect(flight.x.abs(), lessThan(0.35));
    });

    test('a team-mate standing in the aimed direction gets the pass', () {
      final match = MatchEngine(_testMatchSetup());
      final player = match.blueTeam.players.firstWhere(
        (candidate) => !candidate.isGoalkeeper,
      );
      final mate = match.blueTeam.players.firstWhere(
        (candidate) => candidate != player && !candidate.isGoalkeeper,
      );
      for (final other in match.blueTeam.players) {
        if (other == player || other == mate) {
          continue;
        }
        other.pos = Vec2(GameConstants.leftBound + 40, 200 + other.number * 6);
      }
      player.pos = Vec2(GameConstants.virtualWidth / 2, 420);
      mate.pos = Vec2(player.pos.x, player.pos.y - 210);
      player.lastDirection = Vec2(0, -1);
      match.ball
        ..attachTo(player)
        ..pos = player.pos.copy();

      match.manualKick(TeamId.blue, KickType.pass, 0.7);

      expect(match.ball.intendedReceiver?.id, mate.id);
      expect(match.ball.vel.normalized().y, lessThan(-0.8));
    });
  });

  group('fatigue during a stoppage', () {
    test('a stopped match refills at most 2% of the tank per minute', () {
      final match = MatchEngine(_testMatchSetup());
      match.tick(0.05);
      final player = match.blueTeam.players.firstWhere(
        (candidate) => !candidate.isGoalkeeper,
      );
      player.stamina = 0.5;
      // A substitution / VAR review stop: one real minute of wall clock.
      match.substitutionPaused = true;
      for (var second = 0; second < 60; second++) {
        match.tick(1);
      }
      match.substitutionPaused = false;
      final gained = player.stamina - 0.5;
      // Energy comes back, but only a trickle: the old build handed the
      // players a full tank every time the referee looked at the screen
      // (Gereksinim: dakikada en fazla %2).
      expect(gained, greaterThan(0));
      expect(gained, lessThanOrEqualTo(0.02));
    });
  });

  group('var reviews', () {
    test('leaving a review resumes the match right away', () {
      final match = MatchEngine(_testMatchSetup());
      match.tick(0.05);
      // A review (or any referee banner) freezes the game...
      match.cycleFormation(TeamId.blue);
      expect(match.isFrozen, isTrue);

      // ...and leaving it puts the players straight back on the pitch
      // instead of forcing a restart of the whole match
      // (Gereksinim: VAR cikisinda mac devam etsin).
      match.skipCurrentReview();
      expect(match.isFrozen, isFalse);
      match.tick(0.05);
      expect(match.isFrozen, isFalse);
    });
  });
}
