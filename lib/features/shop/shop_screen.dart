import 'package:flutter/widgets.dart';

import '../../core/audio/audio_service.dart';
import '../../core/haptics/haptics.dart';
import '../../core/persistence/save_data.dart';
import '../../game/cosmetics/blades.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/model_preview.dart';
import '../../shared/widgets/stage_backdrop.dart';

/// Blade shop with a live 3D preview. Skins share one mesh and only change
/// tint, trail and flash colour -- they can never affect gameplay.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late String _selected = SaveData.instance.equippedBlade;

  @override
  Widget build(BuildContext context) {
    final save = SaveData.instance;
    return AnimatedBuilder(
      animation: save,
      builder: (context, _) {
        final skin = bladeById(_selected);
        final owned =
            save.ownedBlades.contains(skin.id) ||
            (skin.unlockStars > 0 && save.totalStars >= skin.unlockStars);
        final equipped = save.equippedBlade == skin.id;

        return MenuScaffold(
          title: 'BLADE SHOP',
          subtitle: 'COSMETIC ONLY - NO GAMEPLAY EFFECT',
          accent: K.cyan,
          trailing: AngularPanel(
            cut: 8,
            color: K.panel.withValues(alpha: 0.85),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ZoneGlyph(shape: 'diamond', color: K.yellow, size: 12),
                const SizedBox(width: 7),
                Text('${save.coins}', style: K.number(13, color: K.yellow)),
              ],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    Expanded(
                      child: ModelPreview(
                        model: 'default_blade.glb',
                        spin: 0.7,
                        tiltX: 0.3,
                        fill: 0.78,
                        tint: skin.tint,
                        glowBoost: skin.glow,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(skin.name, style: K.display(17, track: 4)),
                    const SizedBox(height: 12),
                    if (equipped)
                      Text(
                        'EQUIPPED',
                        style: K.label(11, color: K.green, track: 3),
                      )
                    else if (owned)
                      KButton(
                        label: 'Equip',
                        onTap: () {
                          Haptics.instance.uiTap();
                          AudioService.instance.play(Sfx.uiTap);
                          save.equipBlade(skin.id);
                        },
                      )
                    else if (skin.unlockStars > 0)
                      Text(
                        'UNLOCK AT ${skin.unlockStars} STARS',
                        style: K.label(10, color: K.textDim, track: 2),
                      )
                    else
                      KButton(
                        label: 'Buy  ${skin.price}',
                        color: save.coins >= skin.price ? K.yellow : K.steel,
                        enabled: save.coins >= skin.price,
                        onTap: () {
                          if (!save.spendCoins(skin.price)) return;
                          save.unlockBlade(skin.id);
                          save.equipBlade(skin.id);
                          Haptics.instance.perfect();
                          AudioService.instance.play(Sfx.bladeUnlock);
                        },
                      ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 5,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisExtent: 74,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: bladeSkins.length,
                  itemBuilder: (context, i) {
                    final s = bladeSkins[i];
                    final has =
                        save.ownedBlades.contains(s.id) ||
                        (s.unlockStars > 0 && save.totalStars >= s.unlockStars);
                    return _SkinTile(
                      skin: s,
                      owned: has,
                      selected: s.id == _selected,
                      equipped: save.equippedBlade == s.id,
                      onTap: () {
                        Haptics.instance.uiTap();
                        setState(() => _selected = s.id);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkinTile extends StatelessWidget {
  const _SkinTile({
    required this.skin,
    required this.owned,
    required this.selected,
    required this.equipped,
    required this.onTap,
  });

  final BladeSkin skin;
  final bool owned;
  final bool selected;
  final bool equipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = skin.tint ?? K.white;
    return GestureDetector(
      onTap: onTap,
      child: AngularPanel(
        cut: 9,
        color: c.withValues(alpha: selected ? 0.24 : 0.09),
        border: selected ? c : K.stroke,
        glow: selected ? c.withValues(alpha: 0.4) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(width: 22, height: 3, color: c),
                const Spacer(),
                if (equipped)
                  Text('ON', style: K.label(8, color: K.green, track: 1))
                else if (!owned)
                  const _SmallLock(),
              ],
            ),
            Text(
              skin.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: K.label(8.5, color: K.white, track: 1),
            ),
            Text(
              owned
                  ? 'OWNED'
                  : (skin.unlockStars > 0
                        ? '${skin.unlockStars}★'
                        : '${skin.price}'),
              style: K.number(10, color: owned ? K.textDim : K.yellow),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallLock extends StatelessWidget {
  const _SmallLock();

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 8,
    decoration: BoxDecoration(border: Border.all(color: K.stroke, width: 1.5)),
  );
}
