import 'package:flutter/widgets.dart';

import '../../app/app.dart';
import '../../core/audio/audio_service.dart';
import '../../core/haptics/haptics.dart';
import '../../core/persistence/save_data.dart';
import '../../game/levels/campaign.dart';
import '../../game/levels/level_def.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/stage_backdrop.dart';
import '../gameplay/gameplay_screen.dart';

/// Horizontally scrolling progression map: one column band per world, with
/// level nodes staggered along a path.
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Open at the player's current position rather than the very start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final id = SaveData.instance.highestUnlocked.clamp(1, levelCount);
      final target = ((id - 1) / 10).floor() * 720.0;
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _play(LevelDef level) {
    Haptics.instance.uiTap();
    AudioService.instance.play(Sfx.uiTap);
    pushScreen(
      context,
      GameplayScreen(
        level: level,
        onExit: () => Navigator.of(context).maybePop(),
        onNext: (_) {
          Navigator.of(context).maybePop();
          final next = levelById(level.id + 1);
          if (next != null && SaveData.instance.isUnlocked(next.id)) {
            _play(next);
          } else {
            setState(() {});
          }
        },
      ),
    ).then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final save = SaveData.instance;
    return AnimatedBuilder(
      animation: save,
      builder: (context, _) => MenuScaffold(
        title: 'LEVEL SELECT',
        subtitle: '${save.totalStars} / ${levelCount * 3} STARS COLLECTED',
        accent: K.purple,
        child: ListView.builder(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          itemCount: 6,
          itemBuilder: (context, i) =>
              _WorldBand(world: i + 1, save: save, onPlay: _play),
        ),
      ),
    );
  }
}

class _WorldBand extends StatelessWidget {
  const _WorldBand({
    required this.world,
    required this.save,
    required this.onPlay,
  });

  final int world;
  final SaveData save;
  final void Function(LevelDef) onPlay;

  static const List<Color> _accents = [
    K.cyan,
    K.purple,
    K.orange,
    K.yellow,
    K.steel,
    K.green,
  ];

  @override
  Widget build(BuildContext context) {
    final levels = levelsInWorld(world);
    final accent = _accents[(world - 1) % _accents.length];
    final unlocked = levels.any((l) => save.isUnlocked(l.id));
    final worldStars = levels.fold<int>(0, (a, l) => a + save.starsFor(l.id));

    return Container(
      width: 720,
      margin: const EdgeInsets.only(right: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AngularPanel(
            cut: 10,
            color: accent.withValues(alpha: unlocked ? 0.14 : 0.05),
            border: accent.withValues(alpha: unlocked ? 0.7 : 0.25),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'WORLD $world',
                  style: K.label(11, color: accent, track: 2.6),
                ),
                const SizedBox(width: 12),
                Container(width: 1, height: 13, color: K.stroke),
                const SizedBox(width: 12),
                Text(
                  LevelDef.worldNameFor(world),
                  style: K.label(11, color: K.white, track: 2.2),
                ),
                const SizedBox(width: 14),
                const StarRow(stars: 1, max: 1, size: 12),
                const SizedBox(width: 6),
                Text(
                  '$worldStars/${levels.length * 3}',
                  style: K.number(11, color: K.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: CustomPaint(
              painter: _PathPainter(accent.withValues(alpha: 0.22)),
              child: Stack(
                children: [
                  // World hero art, rendered from that world's own structures.
                  Positioned.fill(
                    child: Opacity(
                      // Atmosphere, not competition: the level nodes have to
                      // stay the most readable thing on the band.
                      opacity: unlocked ? 0.17 : 0.07,
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => const LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                        ).createShader(rect),
                        child: Image.asset(
                          'assets/images/world$world.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.centerRight,
                          errorBuilder: (_, _, _) => const SizedBox(),
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < levels.length; i++)
                    Align(
                      alignment: Alignment(
                        -0.92 + (i / (levels.length - 1)) * 1.84,
                        // Stagger nodes along a gentle wave.
                        (i.isEven ? -0.34 : 0.30) + (i % 4 == 0 ? -0.14 : 0.0),
                      ),
                      child: _LevelNode(
                        level: levels[i],
                        stars: save.starsFor(levels[i].id),
                        unlocked: save.isUnlocked(levels[i].id),
                        accent: accent,
                        isBoss: levels[i].id % 10 == 0,
                        onTap: () => onPlay(levels[i]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PathPainter extends CustomPainter {
  _PathPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Path();
    final steps = 10;
    for (var i = 0; i < steps; i++) {
      final t = i / (steps - 1);
      final x = size.width * (0.04 + t * 0.92);
      final y =
          size.height *
          (0.5 + ((i.isEven ? -0.17 : 0.15) + (i % 4 == 0 ? -0.07 : 0.0)));
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.color != color;
}

class _LevelNode extends StatelessWidget {
  const _LevelNode({
    required this.level,
    required this.stars,
    required this.unlocked,
    required this.accent,
    required this.isBoss,
    required this.onTap,
  });

  final LevelDef level;
  final int stars;
  final bool unlocked;
  final Color accent;
  final bool isBoss;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = isBoss ? 72.0 : 58.0;
    return GestureDetector(
      onTap: unlocked ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: AngularPanel(
              cut: isBoss ? 16 : 12,
              color: unlocked
                  ? accent.withValues(alpha: isBoss ? 0.26 : 0.16)
                  : K.panel.withValues(alpha: 0.7),
              border: unlocked ? accent : K.stroke,
              glow: unlocked ? accent.withValues(alpha: 0.4) : null,
              padding: EdgeInsets.zero,
              child: Center(
                child: unlocked
                    ? Text(
                        '${level.id}',
                        style: K.number(isBoss ? 24 : 20, color: K.white),
                      )
                    : const _LockGlyph(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (unlocked)
            StarRow(stars: stars, size: 12)
          else
            const SizedBox(height: 12),
          const SizedBox(height: 3),
          SizedBox(
            width: 92,
            child: Text(
              unlocked ? level.name : 'LOCKED',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: K.label(
                8,
                color: unlocked ? K.textDim : K.stroke,
                track: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LockGlyph extends StatelessWidget {
  const _LockGlyph();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 15,
    height: 17,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 10,
          height: 7,
          decoration: BoxDecoration(
            border: Border.all(color: K.stroke, width: 1.8),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          ),
        ),
        Container(width: 15, height: 9, color: K.stroke),
      ],
    ),
  );
}
