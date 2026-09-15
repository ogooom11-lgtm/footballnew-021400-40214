import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Holds the last game error so any screen can show it with a copy button
/// (مطلب: إذا حدث خطأ أثناء اللعب يظهر مع إمكانية النسخ).
final ValueNotifier<ErrorReport?> gameError = ValueNotifier(null);

class ErrorReport {
  ErrorReport({required this.message, required this.details, required this.when});

  final String message;
  final String details;
  final DateTime when;

  String get copyText => 'Bomban Futbol HATA\nZaman: $when\n$details';
}

/// Records an error exactly once per session burst; the overlay shows it.
void reportGameError(Object error, [StackTrace? stack]) {
  if (gameError.value != null) {
    return;
  }
  final message = error.toString();
  final frames = stack == null
      ? ''
      : stack.toString().split('\n').take(14).join('\n');
  gameError.value = ErrorReport(
    message: message,
    details: message + (frames.isEmpty ? '' : '\n\n$frames'),
    when: DateTime.now(),
  );
}

/// Installs the global error hooks: framework errors, async zone errors and
/// build errors all funnel into [gameError].
void installErrorHandlers() {
  FlutterError.onError = (details) {
    reportGameError(details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportGameError(error, stack);
    return true;
  };
  ErrorWidget.builder = (details) => _FallbackErrorWidget(details);
}

class _FallbackErrorWidget extends StatelessWidget {
  const _FallbackErrorWidget(this.details);

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    reportGameError(details.exception, details.stack);
    return const ColoredBox(color: Color(0xff050a08));
  }
}

/// Full-screen overlay that appears whenever [gameError] is set: shows the
/// error text and offers a copy button (مطلب: عرض الخطأ مع النسخ).
class GameErrorOverlay extends StatelessWidget {
  const GameErrorOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ErrorReport?>(
      valueListenable: gameError,
      builder: (context, report, _) {
        return Stack(
          children: [
            Positioned.fill(child: child),
            if (report != null)
              Positioned.fill(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.78),
                  child: Center(
                    child: Container(
                      width: 560,
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xff180a0a),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.65),
                          width: 1.6,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 30,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'HATA OLUSDU',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.redAccent,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              Text(
                                '${report.when.hour.toString().padLeft(2, '0')}:'
                                '${report.when.minute.toString().padLeft(2, '0')}:'
                                '${report.when.second.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 260),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                report.details,
                                style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 11.5,
                                  color: Color(0xffffc2c2),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: report.copyText),
                                  );
                                  ScaffoldMessenger.maybeOf(context)
                                      ?.showSnackBar(
                                    const SnackBar(
                                      content: Text('Hata metni kopyalandi'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.copy_all, size: 17),
                                label: const Text('Kopyala'),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () => gameError.value = null,
                                icon: const Icon(Icons.close, size: 17),
                                label: const Text('Kapat'),
                              ),
                              const Spacer(),
                              const Text(
                                'Oyun durduruldu',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Runs [run] inside a guarded zone so async errors also reach the overlay.
void runGuardedApp(void Function() run) {
  runZonedGuarded(run, (error, stack) => reportGameError(error, stack));
}
