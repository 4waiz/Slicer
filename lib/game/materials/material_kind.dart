import 'dart:ui' show Color;

/// How a slicable section behaves once it has been cut free.
///
/// Every value here feeds the physics solver, the cut effects and the audio
/// bank, so the seven kinds genuinely play differently rather than just
/// looking different.
enum MaterialKind {
  crystal,
  jelly,
  fruit,
  plasticToy,
  metal,
  ice,
  explosiveCore;

  static MaterialKind parse(String? s) => switch (s) {
    'crystal' => MaterialKind.crystal,
    'jelly' => MaterialKind.jelly,
    'fruit' => MaterialKind.fruit,
    'plastic' || 'plasticToy' || 'toy' => MaterialKind.plasticToy,
    'metal' => MaterialKind.metal,
    'ice' => MaterialKind.ice,
    'explosive' || 'explosiveCore' => MaterialKind.explosiveCore,
    _ => MaterialKind.crystal,
  };

  String get id => switch (this) {
    MaterialKind.crystal => 'crystal',
    MaterialKind.jelly => 'jelly',
    MaterialKind.fruit => 'fruit',
    MaterialKind.plasticToy => 'plastic',
    MaterialKind.metal => 'metal',
    MaterialKind.ice => 'ice',
    MaterialKind.explosiveCore => 'explosive',
  };

  String get label => switch (this) {
    MaterialKind.crystal => 'CRYSTAL',
    MaterialKind.jelly => 'JELLY',
    MaterialKind.fruit => 'FRUIT',
    MaterialKind.plasticToy => 'PLASTIC',
    MaterialKind.metal => 'METAL',
    MaterialKind.ice => 'ICE',
    MaterialKind.explosiveCore => 'CORE',
  };

  MaterialProfile get profile => _profiles[this]!;
}

/// Physical + presentational constants for a [MaterialKind].
class MaterialProfile {
  const MaterialProfile({
    required this.restitution,
    required this.friction,
    required this.density,
    required this.linearDamping,
    required this.angularDamping,
    required this.wobble,
    required this.shardCount,
    required this.shardSize,
    required this.sparkColor,
    required this.cutSound,
    required this.separationImpulse,
    this.fuseSeconds = 0.0,
    this.blastRadius = 0.0,
    this.blastImpulse = 0.0,
  });

  /// Bounciness on landing, 0..1.
  final double restitution;

  /// Surface friction -- ice slides, fruit grips.
  final double friction;

  /// Mass per unit volume; metal pieces genuinely fall harder.
  final double density;

  final double linearDamping;
  final double angularDamping;

  /// Amplitude of the post-cut jiggle applied by the renderer, 0 = rigid.
  final double wobble;

  final int shardCount;
  final double shardSize;
  final Color sparkColor;
  final String cutSound;

  /// How hard the two halves push apart at the moment of the cut.
  final double separationImpulse;

  /// Explosive cores only: how long after being freed by a cut the core arms
  /// and then goes off. Zero means the material is inert.
  final double fuseSeconds;

  /// Radius of the shove, in world units.
  final double blastRadius;

  /// Impulse delivered at the centre of the blast, falling off to zero at
  /// the rim. Applied through inverse mass, so heavy metal resists it.
  final double blastImpulse;

  bool get isExplosive => fuseSeconds > 0 && blastRadius > 0;
}

const Map<MaterialKind, MaterialProfile> _profiles = {
  MaterialKind.crystal: MaterialProfile(
    restitution: 0.16,
    friction: 0.62,
    density: 1.5,
    linearDamping: 0.02,
    angularDamping: 0.06,
    wobble: 0.0,
    shardCount: 12,
    shardSize: 0.10,
    sparkColor: Color(0xFF9BEBFF),
    cutSound: 'cut_crystal',
    separationImpulse: 2.3,
  ),
  MaterialKind.jelly: MaterialProfile(
    restitution: 0.52,
    friction: 0.48,
    density: 0.75,
    linearDamping: 0.06,
    angularDamping: 0.16,
    wobble: 1.0,
    shardCount: 6,
    shardSize: 0.13,
    sparkColor: Color(0xFFFF9BE0),
    cutSound: 'cut_jelly',
    separationImpulse: 1.9,
  ),
  MaterialKind.fruit: MaterialProfile(
    restitution: 0.22,
    friction: 0.74,
    density: 0.95,
    linearDamping: 0.05,
    angularDamping: 0.12,
    wobble: 0.35,
    shardCount: 16,
    shardSize: 0.09,
    sparkColor: Color(0xFFFFC46B),
    cutSound: 'cut_fruit',
    separationImpulse: 2.1,
  ),
  MaterialKind.plasticToy: MaterialProfile(
    restitution: 0.34,
    friction: 0.55,
    density: 1.0,
    linearDamping: 0.03,
    angularDamping: 0.08,
    wobble: 0.0,
    shardCount: 8,
    shardSize: 0.11,
    sparkColor: Color(0xFFFFE28A),
    cutSound: 'cut_plastic',
    separationImpulse: 2.2,
  ),
  MaterialKind.metal: MaterialProfile(
    restitution: 0.12,
    friction: 0.5,
    density: 2.6,
    linearDamping: 0.01,
    angularDamping: 0.04,
    wobble: 0.0,
    shardCount: 18,
    shardSize: 0.08,
    sparkColor: Color(0xFFFFD48A),
    cutSound: 'cut_metal',
    separationImpulse: 1.9,
  ),
  MaterialKind.ice: MaterialProfile(
    restitution: 0.2,
    friction: 0.07,
    density: 1.1,
    linearDamping: 0.01,
    angularDamping: 0.03,
    wobble: 0.0,
    shardCount: 14,
    shardSize: 0.09,
    sparkColor: Color(0xFFDFF6FF),
    cutSound: 'cut_ice',
    separationImpulse: 2.4,
  ),
  MaterialKind.explosiveCore: MaterialProfile(
    restitution: 0.3,
    friction: 0.45,
    density: 1.2,
    linearDamping: 0.02,
    angularDamping: 0.05,
    wobble: 0.0,
    shardCount: 20,
    shardSize: 0.12,
    sparkColor: Color(0xFFFF7A4A),
    cutSound: 'cut_metal',
    separationImpulse: 2.1,
    // Long enough to read the warning ring and see where pieces are heading,
    // short enough that the player is still watching the cut they just made.
    fuseSeconds: 1.15,
    blastRadius: 3.4,
    blastImpulse: 3.6,
  ),
};
