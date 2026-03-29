import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:worka/config/app_env.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = AppEnv.current;
  final options = DefaultFirebaseOptions.currentPlatform(env);
  assert(() {
    // Fail fast if dev config not set up.
    if (env.isDev && options.projectId.startsWith('TODO')) {
      throw StateError(
        'Dev Firebase config is not set. Provide non-prod options or run with APP_ENV=prod explicitly.',
      );
    }
    return true;
  }());
  await Firebase.initializeApp(
    options: options,
  );
  runApp(const WorkaApp());
}

class WorkaApp extends StatelessWidget {
  const WorkaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StartScreen(),
    );
  }
}

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  bool isWorker = true;

  // Colors
  static const Color orange = Color(0xFFFF7A00);
  static const Color dividerGrey = Color(0xFFEDEDED);

  // ✅ нижняя светло-серая зона (оверлей)
  static const Color bottomOverlayGrey = Color(0xFFF6F6F6);

  // Reference base for scaling (uniform)
  static const double refW = 390;
  static const double refH = 844;

  // Reference-like widths/sizes
  static const double baseContentW = 318;
  static const double baseLogoH = 44;
  static const double baseIllusH = 252;

  static const double baseTitle = 34;
  static const double baseSubtitle = 20;

  static const double baseControlH = 56;
  static const double baseRadius = 28;

  static const double baseControlFont = 18;
  static const double baseButtonFont = 26;

  // Vertical rhythm
  static const double topPadRef = 24;
  static const double afterLogoRef = 18;
  static const double afterIllusRef = 18;
  static const double afterTitleRef = 10;
  static const double afterSubtitleRef = 18;
  static const double afterSliderRef = 16;

  // “пробел” в твоих правках = 12
  static const double oneSpace = 12;

  // Keys to measure RU|EN position inside Stack
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _langKey = GlobalKey();

  double? _overlayTop; // computed y where overlay starts

  void _recalcOverlayTop(double s) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stackCtx = _stackKey.currentContext;
      final langCtx = _langKey.currentContext;
      if (stackCtx == null || langCtx == null) return;

      final stackBox = stackCtx.findRenderObject() as RenderBox?;
      final langBox = langCtx.findRenderObject() as RenderBox?;
      if (stackBox == null || langBox == null) return;

      final stackGlobal = stackBox.localToGlobal(Offset.zero);
      final langGlobal = langBox.localToGlobal(Offset.zero);

      final langTopInStack = langGlobal.dy - stackGlobal.dy;
      final langBottomInStack = langTopInStack + langBox.size.height;

      // ✅ overlay starts BELOW RU|EN by 3 “spaces”
      final top = langBottomInStack + (oneSpace * 3) * s;

      // update only if changed (avoid rebuild loops)
      if (_overlayTop == null || (_overlayTop! - top).abs() > 0.5) {
        setState(() => _overlayTop = top);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final h = c.maxHeight;

            final s = math.min(w / refW, h / refH).clamp(0.86, 1.12);
            final contentW = math.min(w - 48, baseContentW * s);

            final logoH = baseLogoH * s;
            final illusH = baseIllusH * s;

            final titleFS = baseTitle * s;
            final subtitleFS = baseSubtitle * s;

            final controlH = baseControlH * s;
            final radius = baseRadius * s;

            final controlFS = baseControlFont * s;
            final buttonFS = baseButtonFont * s;

            double sp(double v) => v * s;

            final needsScroll = h < 660 * s;

            // recalc overlay start based on actual RU|EN position
            _recalcOverlayTop(s);

            final content = Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    SizedBox(height: sp(topPadRef)),

                    // LOGO
                    SizedBox(
                      height: logoH,
                      child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                    ),
                    SizedBox(height: sp(afterLogoRef)),

                    // Illustration
                    SizedBox(
                      height: illusH,
                      child: Image.asset('assets/illustration.png', fit: BoxFit.contain),
                    ),
                    SizedBox(height: sp(afterIllusRef)),

                    // Title
                    Text(
                      'Работа рядом\nи по всему миру',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: titleFS,
                        fontWeight: FontWeight.w700,
                        height: 1.06,
                        color: Colors.black,
                      ),
                    ),
                    SizedBox(height: sp(afterTitleRef)),

                    // Subtitle
                    Text(
                      'Вакансии и специалисты\nдля удалёнки и локально',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: subtitleFS,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                        color: Colors.black54,
                      ),
                    ),
                    SizedBox(height: sp(afterSubtitleRef)),

                    // Slider
                    SizedBox(
                      width: contentW,
                      height: controlH,
                      child: _SegmentedPremium(
                        width: contentW,
                        height: controlH,
                        radius: radius,
                        orange: orange,
                        isLeftSelected: isWorker,
                        leftLabel: 'Работник',
                        rightLabel: 'Работодатель',
                        onLeftTap: () => setState(() => isWorker = true),
                        onRightTap: () => setState(() => isWorker = false),
                        fontSize: controlFS,
                      ),
                    ),
                    SizedBox(height: sp(afterSliderRef)),

                    // Button
                    SizedBox(
                      width: contentW,
                      height: controlH,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(radius),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFF8A1A), Color(0xFFFF7A00)],
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 10,
                              offset: Offset(3, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(radius),
                            ),
                          ),
                          child: Text(
                            'Продолжить',
                            style: TextStyle(
                              fontSize: buttonFS,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // пробел под кнопкой
                    SizedBox(height: sp(24)), // 2 пробела по 12


                    // Divider
                    SizedBox(
                      width: contentW,
                      child: Container(height: 1, color: dividerGrey),
                    ),
                    SizedBox(height: sp(24)), // 2 пробела по 12


                    // Auth row
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Войти',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 18 * s,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: '  •  ',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 18 * s,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text: 'Создать аккаунт',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 18 * s,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),

                    SizedBox(height: sp(oneSpace * 2)),

                    // Languages (key for measuring)
                    Text(
                      'RU  |  EN',
                      key: _langKey,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 13 * s,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    SizedBox(height: sp(oneSpace * 2)),
                  ],
                ),
              ),
            );

            return Stack(
              key: _stackKey,
              children: [
                // Base content (layout unchanged)
                if (needsScroll)
                  SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: h),
                      child: content,
                    ),
                  )
                else
                  content,

                // ✅ Overlay starts BELOW RU|EN by 3 spaces and goes to bottom
                if (_overlayTop != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _overlayTop!,
                    bottom: 0,
                    child: const ColoredBox(color: bottomOverlayGrey),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SegmentedPremium extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final Color orange;

  final bool isLeftSelected;
  final String leftLabel;
  final String rightLabel;
  final VoidCallback onLeftTap;
  final VoidCallback onRightTap;
  final double fontSize;

  const _SegmentedPremium({
    required this.width,
    required this.height,
    required this.radius,
    required this.orange,
    required this.isLeftSelected,
    required this.leftLabel,
    required this.rightLabel,
    required this.onLeftTap,
    required this.onRightTap,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final half = width / 2.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE6E6E6), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(3, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: isLeftSelected ? 0.0 : half,
              top: 0.0,
              width: half,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: orange,
                  borderRadius: BorderRadius.circular(radius),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onLeftTap,
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Text(
                        leftLabel,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: isLeftSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: onRightTap,
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Text(
                        rightLabel,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: !isLeftSelected ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
