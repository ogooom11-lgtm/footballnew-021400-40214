import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/config/game_constants.dart';
import '../game/enums/team_id.dart';
import '../game/logic/match_engine.dart';
import '../game/models/player_game.dart';
import 'field_painter.dart';
import 'player_painter.dart';

class GamePainter extends CustomPainter {
  GamePainter(
    this.engine, {
    this.replayZoom = 1.0,
    this.showGoalkeeperDebug = false,
    this.showHeader = false,
    this.pulsePhase = 0,
    this.chargePlayer,
    this.chargeFraction = 0,
  });

  final MatchEngine engine;
  final double replayZoom;
  final bool showGoalkeeperDebug;

  /// The on-canvas score header only shows when the widget scoreboard is
  /// not on screen (replays and the finished-match view); during live
  /// play the scoreboard widget owns that space.
  final bool showHeader;

  /// Wall-clock seconds — drives the pulsing controlled-player ring.
  final double pulsePhase;

  /// While a kick/penalty button is held down: the player charging and
  /// how full the power gauge is (0..1).
  final PlayerGame? chargePlayer;
  final double chargeFraction;
  final PlayerPainter _playerPainter = const PlayerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / GameConstants.virtualWidth,
      size.height / GameConstants.virtualHeight,
    );
    final dx = (size.width - GameConstants.virtualWidth * scale) / 2;
    final dy = (size.height - GameConstants.virtualHeight * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final replay = engine.currentReplayFrame;
    canvas.save();
    if (replay != null && replayZoom > 1.0) {
      canvas.translate(
        GameConstants.virtualWidth / 2,
        GameConstants.virtualHeight / 2,
      );
      canvas.scale(replayZoom);
      canvas.translate(-replay.ballX, -replay.ballY);
    }

    // Goal celebration: while the flash timer runs, the net that was hit
    // bulges outward (0..1 eased over the celebration duration).
    final flash = engine.goalFlashTimer > 0
        ? (engine.goalFlashTimer / 1.7).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final bulgeEase = flash * (2 - flash); // ease-out
    final fieldPainter = FieldPainter(
      leftBulge: engine.goalFlashSide == TeamSide.left ? bulgeEase : 0,
      rightBulge: engine.goalFlashSide == TeamSide.right ? bulgeEase : 0,
    );
    fieldPainter.paint(canvas);
    _drawOffside(canvas);
    for (final player in engine.blueTeam.players) {
      if (player.isSentOff) continue;
      final frame = replay?.players.where((item) => item.id == player.id);
      _playerPainter.paint(
        canvas,
        player,
        engine.blueTeam.color,
        position: frame == null || frame.isEmpty
            ? null
            : Offset(frame.first.x, frame.first.y),
        showControlledName: replay == null,
        jerseyKit: engine.blueTeam.jerseyKit,
        goalkeeperKit: engine.blueTeam.goalkeeperKit,
        pulsePhase: pulsePhase,
      );
    }
    for (final player in engine.redTeam.players) {
      if (player.isSentOff) continue;
      final frame = replay?.players.where((item) => item.id == player.id);
      _playerPainter.paint(
        canvas,
        player,
        engine.redTeam.color,
        position: frame == null || frame.isEmpty
            ? null
            : Offset(frame.first.x, frame.first.y),
        showControlledName: replay == null,
        jerseyKit: engine.redTeam.jerseyKit,
        goalkeeperKit: engine.redTeam.goalkeeperKit,
        pulsePhase: pulsePhase,
      );
    }
    _drawBall(canvas);
    _drawChargeMeter(canvas);
    if (showGoalkeeperDebug && replay == null) {
      _drawGoalkeeperDebug(canvas, engine.blueTeam.goalkeeper);
      _drawGoalkeeperDebug(canvas, engine.redTeam.goalkeeper);
    }
    canvas.restore();

    if (showHeader) {
      _drawHeader(canvas);
    }
    if (replay != null) {
      _drawReplayStamp(canvas, replay.minute);
    }
    _drawGoalFlash(canvas);

    canvas.restore();
  }

  /// Power gauge while a kick button is held: an arc fills around the
  /// charging player from green (soft) to red (full power).
  void _drawChargeMeter(Canvas canvas) {
    final player = chargePlayer;
    if (player == null || chargeFraction <= 0.01) {
      return;
    }
    final fraction = chargeFraction.clamp(0.0, 1.0).toDouble();
    final center = player.pos.toOffset();
    final radius = player.radius + 13;
    // Green -> amber -> red as the shot loads up.
    final color = fraction < 0.5
        ? Color.lerp(
            const Color(0xff22c55e),
            const Color(0xfffacc15),
            fraction * 2,
          )!
        : Color.lerp(
            const Color(0xfffacc15),
            const Color(0xffef4444),
            (fraction - 0.5) * 2,
          )!;
    final track = Paint()
      ..color = Colors.black.withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, track);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction, false, fill);
  }

  /// Goal celebration overlay: a short golden flash over the pitch and a
  /// big GOL splash that pops in and settles.
  void _drawGoalFlash(Canvas canvas) {
    if (engine.goalFlashTimer <= 0) {
      return;
    }
    final flash = (engine.goalFlashTimer / 1.7).clamp(0.0, 1.0).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        0,
        GameConstants.virtualWidth,
        GameConstants.virtualHeight,
      ),
      Paint()
        ..color = Color.lerp(
          const Color(0xffd4af37),
          Colors.white,
          flash,
        )!.withValues(alpha: 0.10 + flash * 0.20),
    );
    // Text pops in quickly (first 30% of the celebration) then holds.
    final appear = ((1 - flash) / 0.30).clamp(0.0, 1.0).toDouble();
    if (appear <= 0) {
      return;
    }
    final scale = 0.6 + appear * 0.4;
    canvas.save();
    canvas.translate(
      GameConstants.virtualWidth / 2,
      GameConstants.virtualHeight * 0.30,
    );
    canvas.scale(scale);
    final goals = engine.reviewGoals;
    final latestScorer = goals.isEmpty ? null : goals.last.scorerName;
    _text(
      canvas,
      'GOL!',
      Offset.zero,
      64,
      Colors.white.withValues(alpha: appear),
      FontWeight.w900,
    );
    if (latestScorer != null) {
      _text(
        canvas,
        latestScorer,
        const Offset(0, 46),
        16,
        Colors.white.withValues(alpha: appear * 0.85),
        FontWeight.w700,
      );
    }
    canvas.restore();
  }

  void _drawGoalkeeperDebug(Canvas canvas, PlayerGame keeper) {
    final debug = keeper.goalkeeperDebug;
    final impact = debug.predictedImpact;
    canvas.drawCircle(
      keeper.pos.toOffset(),
      debug.reachRadius,
      Paint()
        ..color = const Color(0xff40c4ff).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (impact == null) return;
    canvas.drawLine(
      engine.ball.pos.toOffset(),
      impact.toOffset(),
      Paint()
        ..color = const Color(0xffffab40).withValues(alpha: 0.80)
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      keeper.pos.toOffset(),
      impact.toOffset(),
      Paint()
        ..color = const Color(0xff40c4ff).withValues(alpha: 0.90)
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      impact.toOffset(),
      7,
      Paint()
        ..color = const Color(0xffffab40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawHeader(Canvas canvas) {
    _text(
      canvas,
      '${engine.blueTeam.name}  ${engine.blueTeam.score} - ${engine.redTeam.score}  ${engine.redTeam.name}',
      const Offset(GameConstants.virtualWidth / 2, 18),
      22,
      Colors.white,
      FontWeight.w800,
    );
    _text(
      canvas,
      '${engine.periodTitle}  ${engine.clockText}',
      const Offset(GameConstants.virtualWidth / 2, 43),
      15,
      Colors.white70,
      FontWeight.w700,
    );
  }

  void _drawBall(Canvas canvas) {
    final ball = engine.ball;
    final replay = engine.currentReplayFrame;
    final ballX = replay?.ballX ?? ball.pos.x;
    final ballY = replay?.ballY ?? ball.pos.y;
    final height = replay?.ballHeight ?? ball.heightMeters;
    // Fast loose balls leave a short fading trail (live play only).
    if (replay == null && ball.trail.length > 1) {
      for (var i = 0; i < ball.trail.length; i++) {
        final age = (i + 1) / ball.trail.length;
        canvas.drawCircle(
          ball.trail[i].toOffset(),
          GameConstants.ballRadius * (0.25 + age * 0.45),
          Paint()
            ..color = const Color(0xffffdc2e).withValues(alpha: age * 0.30),
        );
      }
    }
    final shadowRadius = GameConstants.ballRadius + height * 2.2;
    canvas.drawCircle(
      Offset(ballX, ballY) + Offset(0, 2 + height * 2),
      shadowRadius,
      Paint()..color = Colors.black.withValues(alpha: 0.20),
    );
    canvas.drawCircle(
      Offset(ballX, ballY),
      GameConstants.ballRadius,
      Paint()..color = const Color(0xffffdc2e),
    );
    // Rolling seams: two arcs rotate with the distance the ball covers.
    if (height < 0.5) {
      canvas.save();
      canvas.translate(ballX, ballY);
      canvas.rotate(ball.rollAngle);
      final seam = Paint()
        ..color = Colors.black.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: GameConstants.ballRadius - 1.6),
        0.3,
        1.4,
        false,
        seam,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: GameConstants.ballRadius - 1.6),
        math.pi + 0.3,
        1.4,
        false,
        seam,
      );
      canvas.restore();
    }
    canvas.drawCircle(
      Offset(ballX, ballY),
      GameConstants.ballRadius,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (height > 0.06) {
      _text(
        canvas,
        height.toStringAsFixed(2),
        Offset(ballX, ballY - 24),
        13,
        Colors.white,
        FontWeight.w800,
      );
    }
  }

  void _drawReplayStamp(Canvas canvas, double minute) {
    _text(
      canvas,
      'VAR ${minute.toStringAsFixed(1)}',
      const Offset(GameConstants.virtualWidth - 90, 42),
      18,
      const Color(0xffffd34d),
      FontWeight.w900,
    );
  }

  void _drawOffside(Canvas canvas) {
    final event = engine.currentOffside;
    if (event == null) {
      return;
    }
    // FIFA-style semi-automated offside display
    // Red offside line
    final redLine = Paint()
      ..color = const Color(0xffff3b30)
      ..strokeWidth = 3;
    // Blue defender line  
    final blueLine = Paint()
      ..color = const Color(0xff2196f3)
      ..strokeWidth = 3;

    // Draw red offside line (solid)
    canvas.drawLine(
      Offset(event.lineX, GameConstants.topBound),
      Offset(event.lineX, GameConstants.bottomBound),
      redLine,
    );

    // Draw blue defender line next to offside line
    final defenderX = event.lineX + (engine.teamById(event.attackingTeam).attackDirection * -4);
    canvas.drawLine(
      Offset(defenderX, GameConstants.topBound),
      Offset(defenderX, GameConstants.bottomBound),
      blueLine,
    );

    // Highlight offending player
    canvas.drawCircle(
      event.offenderPos.toOffset(),
      22,
      Paint()
        ..color = const Color(0xffff3b30).withValues(alpha: 0.22)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      event.offenderPos.toOffset(),
      22,
      Paint()
        ..color = const Color(0xffff3b30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Show distance text
    final attackingTeam = engine.teamById(event.attackingTeam);
    final offender = attackingTeam.players.firstWhere(
      (p) => p.profile.name == event.offenderName,
      orElse: () => attackingTeam.players.first,
    );
    // Show the infringement in REAL metres, not engine pixels.
    final offsideDist = (offender.pos.x - event.lineX).abs() *
        105 /
        GameConstants.pitchWidth;
    _text(
      canvas,
      'Ofsayt: ${offsideDist.toStringAsFixed(2)} m',
      Offset(event.lineX + 8, GameConstants.topBound + 18),
      14,
      const Color(0xffff3b30),
      FontWeight.w900,
    );
  }

  void _text(
    Canvas canvas,
    String value,
    Offset center,
    double size,
    Color color,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: GameConstants.virtualWidth - 160);
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
