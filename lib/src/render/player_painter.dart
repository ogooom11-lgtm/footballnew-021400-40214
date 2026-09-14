import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/math/vec2.dart';
import '../game/models/jersey_kit.dart';
import '../game/models/player_game.dart';

class PlayerPainter {
  const PlayerPainter();

  void paint(
    Canvas canvas,
    PlayerGame player,
    Color color, {
    Offset? position,
    bool showControlledName = true,
    JerseyKit? jerseyKit,
    JerseyKit? goalkeeperKit,
    double pulsePhase = 0,
  }) {
    final isKeeper = player.isGoalkeeper;
    final playerColor = isKeeper && goalkeeperKit != null
        ? goalkeeperKit.shirtColor
        : jerseyKit?.shirtColor ?? color;
    final shortsColor = jerseyKit?.shortsColor ?? color;
    final socksColor = isKeeper && goalkeeperKit != null
        ? goalkeeperKit.socksColor
        : jerseyKit?.socksColor ?? Colors.white;
    final numberClr = isKeeper && goalkeeperKit != null
        ? goalkeeperKit.numberColor
        : jerseyKit?.numberColor ?? Colors.white;
    final body = Paint()..color = playerColor;
    final border = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rawCenter = position ?? player.pos.toOffset();
    final jumpDuration = player.isGoalkeeper ? 0.62 : 0.48;
    final jumpPhase = player.jumpAnimationTimer <= 0
        ? 0.0
        : math.sin(
            (1 -
                    (player.jumpAnimationTimer / jumpDuration).clamp(0.0, 1.0)) *
                math.pi,
          );
    // Ground shadow: shrinks and fades while the player is airborne.
    final shadowScale = (1 - jumpPhase * 0.45).clamp(0.4, 1.0);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.28 * shadowScale)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);
    canvas.drawOval(
      Rect.fromCenter(
        center: rawCenter.translate(0, player.radius * 0.78),
        width: player.radius * 2.05 * shadowScale,
        height: player.radius * 0.68 * shadowScale,
      ),
      shadow,
    );
    // Run bob: a tiny vertical bounce driven by the distance covered,
    // so sprinting players visibly pump instead of gliding.
    final runBob = math.sin(player.runPhase * 2.2) *
        1.15 *
        player.movementIntensity.clamp(0.0, 1.0);
    final center = rawCenter.translate(
      0,
      -jumpPhase * (player.isGoalkeeper ? 13 : 9) - runBob,
    );
    if (player.isGoalkeeper) {
      _paintKeeperBody(
        canvas,
        player,
        center,
        body,
        border,
        shortsColor,
        socksColor,
        jumpPhase,
      );
    } else {
      canvas.drawCircle(center, player.radius, body);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center.translate(0, player.radius * 0.45),
            width: player.radius * 1.35,
            height: player.radius * 0.55,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = shortsColor,
      );
      // Socks: a thin band under the shorts in the kit's sock colour.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center.translate(0, player.radius * 0.86),
            width: player.radius * 1.05,
            height: player.radius * 0.30,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = socksColor,
      );
      canvas.drawCircle(center, player.radius, border);
    }
    if (player.isGoalkeeper) {
      _keeperCue(canvas, player, center);
    }
    _fatigueCue(canvas, player, center);
    if (player.yellowCardsThisMatch > 0) {
      final cardRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          center.dx - player.radius - 7,
          center.dy - player.radius - 13,
          7,
          10,
        ),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(cardRect, Paint()..color = const Color(0xffffd34d));
    }
    if (player.jumpBoostMeters > 0) {
      canvas.drawCircle(
        center,
        player.radius + 5,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (player.controlled && showControlledName) {
      // Breathing selection ring: gently expands and brightens on a loop.
      final pulse = (math.sin(pulsePhase * 5.2) + 1) / 2;
      canvas.drawCircle(
        center,
        player.radius + 7 + pulse * 1.6,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.72 + pulse * 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + pulse * 0.8,
      );
    }
    _text(
      canvas,
      player.number.toString(),
      center,
      11,
      numberClr,
      FontWeight.w800,
    );
    if (player.controlled) {
      _text(
        canvas,
        player.profile.name,
        Offset(center.dx, center.dy - 26),
        10,
        Colors.white,
        FontWeight.w700,
      );
    }
  }

  void _fatigueCue(Canvas canvas, PlayerGame player, Offset center) {
    if (player.stamina > 0.42) {
      return;
    }
    final severity = ((0.42 - player.stamina) / 0.42).clamp(0.0, 1.0);
    final color = severity > 0.55
        ? const Color(0xffff4d4d)
        : const Color(0xffffc857);
    final iconCenter = center.translate(player.radius + 7, -player.radius - 8);
    final battery = RRect.fromRectAndRadius(
      Rect.fromCenter(center: iconCenter, width: 13, height: 8),
      const Radius.circular(2),
    );
    final cap = Rect.fromCenter(
      center: iconCenter.translate(7.3, 0),
      width: 2.4,
      height: 4.6,
    );
    canvas.drawRRect(
      battery,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.72)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      battery,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawRect(cap, Paint()..color = color);
    final fillWidth = 9.0 * player.stamina.clamp(0.08, 0.42) / 0.42;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(iconCenter.dx - 5, iconCenter.dy - 2.5, fillWidth, 5),
        const Radius.circular(1.2),
      ),
      Paint()..color = color.withValues(alpha: 0.82),
    );
  }

  /// Dedicated goalkeeper body per state — the keeper never looks like a
  /// plain outfield circle again: mid-dive he is stretched and tilted in
  /// the dive direction, on the ground he lies flat, while getting up he
  /// pushes himself upright, with the ball he hugs it, after a save the
  /// arms go up, and in the ready stance he crouches with the gloves wide
  /// (مطلب: تفاعلات مخصصة للحارس في كل حالة).
  void _paintKeeperBody(
    Canvas canvas,
    PlayerGame player,
    Offset center,
    Paint body,
    Paint border,
    Color shortsColor,
    Color socksColor,
    double jumpPhase,
  ) {
    final r = player.radius;
    final glovePaint = Paint()..color = const Color(0xfff3f6ff);
    final gloveBorder = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;

    // -------- 1) Mid-dive: stretched body tilted along the dive ---------
    final diving = player.keeperGroundTimer > 0 &&
        player.jumpAnimationTimer > 0.10 &&
        player.keeperState == 'atlayis';
    if (diving) {
      final dir = player.lastDirection.lengthSquared > 0.003
          ? player.lastDirection.normalized()
          : Vec2(1, 0);
      final angle = math.atan2(dir.y, dir.x);
      canvas.save();
      canvas.translate(center.dx, center.dy - jumpPhase * 4);
      canvas.rotate(angle);
      final stretch = Rect.fromCenter(
        center: Offset.zero,
        width: r * 3.05,
        height: r * 1.32,
      );
      canvas.drawOval(stretch, body);
      canvas.drawOval(stretch, border);
      // Shorts near the trailing hip.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(-r * 0.85, 0),
            width: r * 0.85,
            height: r * 1.1,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = shortsColor,
      );
      // Both gloves reach toward the ball side of the dive.
      canvas.drawCircle(Offset(r * 1.72, -r * 0.28), r * 0.38, glovePaint);
      canvas.drawCircle(Offset(r * 1.72, r * 0.28), r * 0.38, glovePaint);
      canvas.drawCircle(Offset(r * 1.72, -r * 0.28), r * 0.38, gloveBorder);
      canvas.drawCircle(Offset(r * 1.72, r * 0.28), r * 0.38, gloveBorder);
      canvas.restore();
      // Motion streaks trailing the dive.
      final streak = Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      final back = Offset(-dir.x, -dir.y);
      final side = Offset(-dir.y, dir.x);
      for (var i = 0; i < 3; i++) {
        final start = center +
            back * (r * 1.7 + i * 5.5) +
            side * ((i - 1) * 4.2);
        canvas.drawLine(start, start + back * 7, streak);
      }
      return;
    }

    // -------- 2) On the ground / getting up ------------------------------
    if (player.keeperGroundTimer > 0) {
      final rising = player.keeperGroundTimer <= 0.24;
      if (rising) {
        // Getting up: the flat body tilts upright as the timer runs out,
        // one arm still pushing off the ground.
        final progress =
            (1 - player.keeperGroundTimer / 0.24).clamp(0.0, 1.0).toDouble();
        final rect = Rect.fromCenter(
          center: center.translate(0, -r * 0.4 * progress),
          width: r * (2.9 - 1.45 * progress),
          height: r * (1.15 + 1.15 * progress),
        );
        canvas.drawOval(rect, body);
        canvas.drawOval(rect, border);
        final pushArm = Paint()
          ..color = body.color
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(center.dx - r * 1.15, center.dy - r * 0.1),
          Offset(center.dx - r * 0.65, center.dy + r * 0.95 * (1 - progress * 0.5)),
          pushArm,
        );
        canvas.drawCircle(
          Offset(center.dx - r * 0.65, center.dy + r * 0.95 * (1 - progress * 0.5)),
          r * 0.24,
          glovePaint,
        );
        return;
      }
      // Lying flat after the dive.
      final rect = Rect.fromCenter(
        center: center,
        width: r * 2.9,
        height: r * 1.15,
      );
      canvas.drawOval(rect, body);
      canvas.drawOval(rect, border);
      return;
    }

    // -------- 3) Airborne (jump launch / flight) -------------------------
    if (jumpPhase > 0.02) {
      final rect = Rect.fromCenter(
        center: center.translate(0, -r * 0.55),
        width: r * (2.1 - jumpPhase * 0.5),
        height: r * (2.05 + jumpPhase * 1.1),
      );
      canvas.drawOval(rect, body);
      canvas.drawOval(rect, border);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center.translate(0, r * 0.55),
            width: r * 1.1,
            height: r * 0.45,
          ),
          const Radius.circular(2),
        ),
        Paint()..color = shortsColor,
      );
      // Gloves reach up for the ball while the jump is in the air.
      final gloveY = -r * (1.75 + jumpPhase * 0.9);
      canvas.drawCircle(center.translate(-r * 0.72, gloveY), r * 0.34, glovePaint);
      canvas.drawCircle(center.translate(r * 0.72, gloveY), r * 0.34, glovePaint);
      canvas.drawCircle(center.translate(-r * 0.72, gloveY), r * 0.34, gloveBorder);
      canvas.drawCircle(center.translate(r * 0.72, gloveY), r * 0.34, gloveBorder);
      return;
    }

    // -------- 4) Standing states -----------------------------------------
    switch (player.keeperState) {
      case 'top elde':
        // Holding the ball: it is hugged against the chest with both arms.
        canvas.drawCircle(center, r, body);
        canvas.drawCircle(center, r, border);
        final heldBall = center.translate(0, -r * 0.45);
        canvas.drawCircle(heldBall, r * 0.52, Paint()..color = Colors.white);
        canvas.drawCircle(
          heldBall,
          r * 0.52,
          Paint()
            ..color = Colors.black
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        canvas.drawCircle(
          heldBall.translate(-r * 0.55, r * 0.1),
          r * 0.26,
          glovePaint,
        );
        canvas.drawCircle(
          heldBall.translate(r * 0.55, r * 0.1),
          r * 0.26,
          glovePaint,
        );
        return;
      case 'kurtaris':
        // Just saved: standing tall with both arms raised.
        canvas.drawCircle(center, r, body);
        canvas.drawCircle(center, r, border);
        final arm = Paint()
          ..color = body.color
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          center.translate(-r * 0.75, -r * 0.2),
          center.translate(-r * 1.25, -r * 1.5),
          arm,
        );
        canvas.drawLine(
          center.translate(r * 0.75, -r * 0.2),
          center.translate(r * 1.25, -r * 1.5),
          arm,
        );
        canvas.drawCircle(center.translate(-r * 1.25, -r * 1.5), r * 0.26, glovePaint);
        canvas.drawCircle(center.translate(r * 1.25, -r * 1.5), r * 0.26, glovePaint);
        return;
      case 'hazir':
        // Ready stance: a slight crouch with the gloves spread wide.
        final crouch = Rect.fromCenter(
          center: center.translate(0, r * 0.12),
          width: r * 2.15,
          height: r * 1.82,
        );
        canvas.drawOval(crouch, body);
        canvas.drawOval(crouch, border);
        canvas.drawCircle(center.translate(-r * 1.28, r * 0.1), r * 0.30, glovePaint);
        canvas.drawCircle(center.translate(r * 1.28, r * 0.1), r * 0.30, glovePaint);
        canvas.drawCircle(center.translate(-r * 1.28, r * 0.1), r * 0.30, gloveBorder);
        canvas.drawCircle(center.translate(r * 1.28, r * 0.1), r * 0.30, gloveBorder);
        return;
      default:
        canvas.drawCircle(center, r, body);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center.translate(0, r * 0.45),
              width: r * 1.35,
              height: r * 0.55,
            ),
            const Radius.circular(2),
          ),
          Paint()..color = shortsColor,
        );
        canvas.drawCircle(center, r, border);
        return;
    }
  }

  void _keeperCue(Canvas canvas, PlayerGame player, Offset center) {
    if (player.keeperGroundTimer > 0) {
      if (player.keeperGroundTimer <= 0.24) {
        // Getting up: a small upward arrow above the keeper.
        _text(
          canvas,
          '^',
          center.translate(0, -player.radius - 14),
          11,
          const Color(0xffbde8ff),
          FontWeight.w900,
        );
        return;
      }
      // On the ground: no text above the keeper — just two short lines on
      // both sides of the body to show he is lying down.
      final sidePaint = Paint()
        ..color = const Color(0xff8bd3ff)
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round;
      final bodyW = player.radius * 1.45;
      final lineY = center.dy - 2;
      canvas.drawLine(
        Offset(center.dx - bodyW - 7, lineY),
        Offset(center.dx - bodyW - 16, lineY),
        sidePaint,
      );
      canvas.drawLine(
        Offset(center.dx + bodyW + 7, lineY),
        Offset(center.dx + bodyW + 16, lineY),
        sidePaint,
      );
      return;
    }
    if (player.keeperState == 'top elde') {
      _text(
        canvas,
        'TOP ELDE',
        center.translate(0, -player.radius - 16),
        8,
        const Color(0xffbde8ff),
        FontWeight.w900,
      );
    } else if (player.keeperState == 'kurtaris') {
      _text(
        canvas,
        'KURTARIS!',
        center.translate(0, -player.radius - 16),
        8,
        const Color(0xff8bff9e),
        FontWeight.w900,
      );
    }
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
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }
}
