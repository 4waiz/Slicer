import 'dart:ui' show Color;

/// A purely cosmetic blade. Geometry is shared -- only the tint, trail colour
/// and cut-flash change, so skins can never affect physics or scoring.
class BladeSkin {
  const BladeSkin({
    required this.id,
    required this.name,
    required this.tint,
    required this.trail,
    required this.flash,
    required this.price,
    this.tintAmount = 0.6,
    this.glow = 0.35,
    this.unlockStars = 0,
  });

  final String id;
  final String name;

  /// Null keeps the model's own silver material.
  final Color? tint;
  final Color trail;
  final Color flash;
  final int price;
  final double tintAmount;
  final double glow;

  /// Alternative unlock: reach this many total stars.
  final int unlockStars;

  bool get isDefault => id == 'silver';
}

const List<BladeSkin> bladeSkins = [
  BladeSkin(
    id: 'silver',
    name: 'DEFAULT SILVER',
    tint: null,
    trail: Color(0xFFF2FBFF),
    flash: Color(0xFFF2FBFF),
    price: 0,
  ),
  BladeSkin(
    id: 'cyan',
    name: 'CYAN ENERGY',
    tint: Color(0xFF35D6F0),
    trail: Color(0xFF6FE8FF),
    flash: Color(0xFF35D6F0),
    price: 250,
    glow: 0.7,
  ),
  BladeSkin(
    id: 'orange',
    name: 'ORANGE PLASMA',
    tint: Color(0xFFF07A2A),
    trail: Color(0xFFFFA85C),
    flash: Color(0xFFF07A2A),
    price: 350,
    glow: 0.7,
  ),
  BladeSkin(
    id: 'purple',
    name: 'PURPLE CRYSTAL',
    tint: Color(0xFFA05FD0),
    trail: Color(0xFFC98BEF),
    flash: Color(0xFFA05FD0),
    price: 450,
    glow: 0.6,
  ),
  BladeSkin(
    id: 'gold',
    name: 'GOLD',
    tint: Color(0xFFF5C93A),
    trail: Color(0xFFFFE38A),
    flash: Color(0xFFFFD84D),
    price: 600,
    glow: 0.55,
  ),
  BladeSkin(
    id: 'ice',
    name: 'ICE',
    tint: Color(0xFFB8E8F5),
    trail: Color(0xFFDFF6FF),
    flash: Color(0xFFDFF6FF),
    price: 700,
    glow: 0.5,
  ),
  BladeSkin(
    id: 'lava',
    name: 'LAVA',
    tint: Color(0xFFF0524A),
    trail: Color(0xFFFF8A5C),
    flash: Color(0xFFFF6B3A),
    price: 850,
    glow: 0.8,
  ),
  BladeSkin(
    id: 'galaxy',
    name: 'GALAXY',
    tint: Color(0xFF7A3FA8),
    trail: Color(0xFFD94FA0),
    flash: Color(0xFFC98BEF),
    price: 1000,
    glow: 0.75,
  ),
  BladeSkin(
    id: 'kanban',
    name: 'BLACK KANBAN',
    tint: Color(0xFF16323E),
    trail: Color(0xFFF07A2A),
    flash: Color(0xFFF5C93A),
    price: 1400,
    tintAmount: 0.8,
    glow: 0.4,
  ),
  BladeSkin(
    id: 'rainbow',
    name: 'RAINBOW',
    tint: Color(0xFF3CE08A),
    trail: Color(0xFF35D6F0),
    flash: Color(0xFFF5C93A),
    price: 0,
    unlockStars: 120,
    glow: 0.9,
  ),
];

BladeSkin bladeById(String id) =>
    bladeSkins.firstWhere((b) => b.id == id, orElse: () => bladeSkins.first);
