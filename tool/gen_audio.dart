// Generates every sound effect in the game as an original 16-bit PCM WAV.
//
// Nothing is sampled or licensed -- each cue is synthesised here from
// oscillators, noise and envelopes, so the audio is unambiguously original.
//
//   dart run tool/gen_audio.dart
//
// Output: assets/audio/<id>.wav

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 22050;

void main() {
  final dir = Directory('assets/audio');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  final bank = <String, List<double>>{
    'ui_tap': _uiTap(),
    'swipe_start': _swipeStart(),
    'blade_move': _bladeMove(),
    'cut_crystal': _cutCrystal(),
    'cut_jelly': _cutJelly(),
    'cut_fruit': _cutFruit(),
    'cut_plastic': _cutPlastic(),
    'cut_metal': _cutMetal(),
    'cut_ice': _cutIce(),
    'separation': _separation(),
    'land_correct': _landCorrect(),
    'land_wrong': _landWrong(),
    'percent_tick': _percentTick(),
    'combo': _combo(),
    'perfect_cut': _perfectCut(),
    'failure': _failure(),
    'level_complete': _levelComplete(),
    'reward': _reward(),
    'blade_unlock': _bladeUnlock(),
    'core_arm': _coreArm(),
    'core_blast': _coreBlast(),
  };

  var total = 0;
  bank.forEach((name, samples) {
    final bytes = _wav(samples);
    File('assets/audio/$name.wav').writeAsBytesSync(bytes);
    total += bytes.length;
    stdout.writeln(
      '  $name.wav  ${samples.length} samples  '
      '${(bytes.length / 1024).toStringAsFixed(1)} KB',
    );
  });
  stdout.writeln(
    '\n${bank.length} sounds, ${(total / 1024).toStringAsFixed(1)} KB total',
  );
}

// ---------------------------------------------------------------------------
// Synthesis helpers
// ---------------------------------------------------------------------------

final math.Random _rng = math.Random(20260805);

int _n(double seconds) => (seconds * sampleRate).round();

/// Exponential decay envelope with a short attack.
double _env(int i, int len, {double attack = 0.004, double curve = 3.0}) {
  final t = i / sampleRate;
  final total = len / sampleRate;
  if (t < attack) return t / attack;
  final u = ((t - attack) / (total - attack)).clamp(0.0, 1.0);
  return math.pow(1.0 - u, curve).toDouble();
}

double _sine(double phase) => math.sin(phase * 2 * math.pi);

double _saw(double phase) => 2.0 * (phase % 1.0) - 1.0;

double _square(double phase) => (phase % 1.0) < 0.5 ? 1.0 : -1.0;

double _noise() => _rng.nextDouble() * 2 - 1;

/// One-pole low-pass; `cut` in 0..1 (1 = open).
List<double> _lowpass(List<double> x, double cut) {
  final out = List<double>.filled(x.length, 0);
  var prev = 0.0;
  final a = cut.clamp(0.001, 1.0);
  for (var i = 0; i < x.length; i++) {
    prev += a * (x[i] - prev);
    out[i] = prev;
  }
  return out;
}

/// One-pole high-pass, used to thin out low rumble.
List<double> _highpass(List<double> x, double cut) {
  final lp = _lowpass(x, cut);
  return List<double>.generate(x.length, (i) => x[i] - lp[i]);
}

/// Tone with an optional pitch glide from [f0] to [f1].
List<double> _tone(
  double seconds,
  double f0, {
  double? f1,
  double Function(double) wave = _sine,
  double gain = 0.6,
  double attack = 0.004,
  double curve = 3.0,
}) {
  final len = _n(seconds);
  final out = List<double>.filled(len, 0);
  var phase = 0.0;
  for (var i = 0; i < len; i++) {
    final t = i / len;
    final f = f1 == null ? f0 : f0 + (f1 - f0) * t;
    phase += f / sampleRate;
    out[i] = wave(phase) * _env(i, len, attack: attack, curve: curve) * gain;
  }
  return out;
}

List<double> _noiseBurst(
  double seconds, {
  double gain = 0.5,
  double cutStart = 0.9,
  double cutEnd = 0.06,
  double curve = 3.0,
}) {
  final len = _n(seconds);
  final out = List<double>.filled(len, 0);
  var prev = 0.0;
  for (var i = 0; i < len; i++) {
    final t = i / len;
    final cut = cutStart + (cutEnd - cutStart) * t;
    prev += cut.clamp(0.002, 1.0) * (_noise() - prev);
    out[i] = prev * _env(i, len, curve: curve) * gain;
  }
  return out;
}

List<double> _mix(List<List<double>> layers) {
  final len = layers.fold<int>(0, (a, l) => math.max(a, l.length));
  final out = List<double>.filled(len, 0);
  for (final l in layers) {
    for (var i = 0; i < l.length; i++) {
      out[i] += l[i];
    }
  }
  return out;
}

/// Delays a layer so cues can be built as short sequences.
List<double> _at(double seconds, List<double> x) {
  final pad = _n(seconds);
  return List<double>.filled(pad, 0, growable: true)..addAll(x);
}

/// Normalises and applies a short fade-out so nothing clicks at the tail.
List<double> _master(List<double> x, {double peak = 0.82}) {
  var maxAbs = 0.0;
  for (final v in x) {
    maxAbs = math.max(maxAbs, v.abs());
  }
  if (maxAbs < 1e-9) return x;
  final g = peak / maxAbs;
  final fade = math.min(_n(0.012), x.length);
  final out = List<double>.filled(x.length, 0);
  for (var i = 0; i < x.length; i++) {
    var v = x[i] * g;
    final fromEnd = x.length - i;
    if (fromEnd < fade) v *= fromEnd / fade;
    out[i] = v.clamp(-1.0, 1.0);
  }
  return out;
}

Uint8List _wav(List<double> samples) {
  final dataLen = samples.length * 2;
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) =>
      b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) =>
      b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

  str('RIFF');
  u32(36 + dataLen);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  str('data');
  u32(dataLen);

  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    pcm[i] = (samples[i] * 32767).round().clamp(-32768, 32767);
  }
  b.add(pcm.buffer.asUint8List());
  return b.toBytes();
}

// ---------------------------------------------------------------------------
// The bank
// ---------------------------------------------------------------------------

List<double> _uiTap() => _master(
  _mix([
    _tone(0.05, 1400, f1: 900, gain: 0.35, curve: 5),
    _noiseBurst(0.035, gain: 0.22, cutStart: 0.7, cutEnd: 0.2, curve: 6),
  ]),
);

/// Rising airy sweep as the finger starts to draw.
List<double> _swipeStart() => _master(
  _mix([
    _noiseBurst(0.20, gain: 0.5, cutStart: 0.05, cutEnd: 0.55, curve: 1.4),
    _tone(0.20, 320, f1: 880, gain: 0.16, wave: _sine, curve: 1.6),
  ]),
);

/// The blade travelling: a fast filtered whoosh.
List<double> _bladeMove() => _master(
  _mix([
    _highpass(
      _noiseBurst(0.26, gain: 0.6, cutStart: 0.5, cutEnd: 0.12, curve: 1.8),
      0.05,
    ),
    _tone(0.22, 1200, f1: 380, gain: 0.14, curve: 2.4),
  ]),
);

/// Bright glassy ping with a shard tail.
List<double> _cutCrystal() => _master(
  _mix([
    _tone(0.34, 2100, f1: 1750, gain: 0.42, curve: 4),
    _tone(0.28, 3150, f1: 2700, gain: 0.22, curve: 5),
    _tone(0.20, 4600, gain: 0.12, curve: 6),
    _noiseBurst(0.16, gain: 0.28, cutStart: 0.95, cutEnd: 0.3, curve: 4),
  ]),
);

/// Soft low squelch with a wobble.
List<double> _cutJelly() {
  final len = _n(0.30);
  final body = List<double>.filled(len, 0);
  var phase = 0.0;
  for (var i = 0; i < len; i++) {
    final t = i / len;
    // Vibrato is what makes it read as "wobbly" rather than just low.
    final f = 210 - 90 * t + math.sin(t * 42) * 26;
    phase += f / sampleRate;
    body[i] = _sine(phase) * _env(i, len, attack: 0.01, curve: 2.2) * 0.6;
  }
  return _master(
    _mix([
      body,
      _lowpass(_noiseBurst(0.14, gain: 0.2, cutStart: 0.3, cutEnd: 0.05), 0.2),
    ]),
  );
}

/// Wet burst plus a soft body.
List<double> _cutFruit() => _master(
  _mix([
    _noiseBurst(0.22, gain: 0.55, cutStart: 0.6, cutEnd: 0.06, curve: 2.6),
    _tone(0.20, 460, f1: 210, gain: 0.3, curve: 2.6),
    _tone(0.12, 900, f1: 600, gain: 0.14, curve: 4),
  ]),
);

/// Dry click-thock.
List<double> _cutPlastic() => _master(
  _mix([
    _tone(0.13, 780, f1: 420, gain: 0.5, wave: _square, curve: 5),
    _noiseBurst(0.07, gain: 0.3, cutStart: 0.8, cutEnd: 0.2, curve: 6),
  ]),
);

/// Inharmonic partials give the metallic clang its character.
List<double> _cutMetal() => _master(
  _mix([
    _tone(0.44, 620, gain: 0.34, curve: 3.4),
    _tone(0.40, 933, gain: 0.24, curve: 3.6),
    _tone(0.36, 1487, gain: 0.18, curve: 4.0),
    _tone(0.30, 2310, gain: 0.12, curve: 4.6),
    _noiseBurst(0.10, gain: 0.3, cutStart: 0.9, cutEnd: 0.4, curve: 5),
  ]),
);

/// Crackle plus a thin high ping.
List<double> _cutIce() => _master(
  _mix([
    _highpass(
      _noiseBurst(0.20, gain: 0.5, cutStart: 0.95, cutEnd: 0.5, curve: 3.4),
      0.25,
    ),
    _tone(0.26, 3300, f1: 2900, gain: 0.24, curve: 5),
    _at(0.05, _tone(0.14, 4200, gain: 0.14, curve: 6)),
  ]),
);

/// Low thump as the halves part.
List<double> _separation() => _master(
  _mix([
    _tone(0.24, 150, f1: 70, gain: 0.7, curve: 2.6),
    _noiseBurst(0.10, gain: 0.18, cutStart: 0.25, cutEnd: 0.04, curve: 4),
  ]),
);

/// Rising perfect-fifth chime.
List<double> _landCorrect() => _master(
  _mix([
    _tone(0.20, 784, gain: 0.34, curve: 4),
    _at(0.06, _tone(0.24, 1175, gain: 0.30, curve: 4)),
  ]),
);

/// Dull descending buzz.
List<double> _landWrong() => _master(
  _mix([
    _tone(0.24, 220, f1: 130, gain: 0.5, wave: _saw, curve: 3),
    _tone(0.18, 165, f1: 98, gain: 0.3, wave: _square, curve: 3),
  ]),
);

List<double> _percentTick() =>
    _master(_tone(0.045, 1800, f1: 2100, gain: 0.4, curve: 6));

/// Each combo step lands a little higher.
List<double> _combo() => _master(
  _mix([
    _tone(0.10, 880, gain: 0.3, curve: 4),
    _at(0.05, _tone(0.12, 1320, gain: 0.3, curve: 4)),
    _at(0.10, _tone(0.16, 1760, gain: 0.3, curve: 4)),
  ]),
);

/// Bright four-note flourish with a white shimmer.
List<double> _perfectCut() => _master(
  _mix([
    _tone(0.16, 1047, gain: 0.26, curve: 4),
    _at(0.07, _tone(0.16, 1319, gain: 0.26, curve: 4)),
    _at(0.14, _tone(0.18, 1568, gain: 0.26, curve: 4)),
    _at(0.21, _tone(0.42, 2093, gain: 0.32, curve: 3)),
    _at(0.21, _tone(0.42, 3136, gain: 0.14, curve: 3)),
    _highpass(
      _noiseBurst(0.5, gain: 0.16, cutStart: 0.9, cutEnd: 0.6, curve: 2),
      0.3,
    ),
  ]),
);

/// Descending minor fall.
List<double> _failure() => _master(
  _mix([
    _tone(0.20, 392, gain: 0.34, wave: _saw, curve: 3),
    _at(0.10, _tone(0.22, 311, gain: 0.34, wave: _saw, curve: 3)),
    _at(0.20, _tone(0.36, 233, gain: 0.38, wave: _saw, curve: 2.4)),
  ]),
);

/// Ascending major triad.
List<double> _levelComplete() => _master(
  _mix([
    _tone(0.16, 523, gain: 0.3, curve: 3.6),
    _at(0.09, _tone(0.16, 659, gain: 0.3, curve: 3.6)),
    _at(0.18, _tone(0.34, 784, gain: 0.34, curve: 3.0)),
    _at(0.18, _tone(0.34, 1047, gain: 0.18, curve: 3.0)),
  ]),
);

/// Coin sparkle.
List<double> _reward() => _master(
  _mix([
    _tone(0.09, 1568, gain: 0.3, curve: 5),
    _at(0.05, _tone(0.20, 2093, gain: 0.32, curve: 4)),
    _at(
      0.05,
      _highpass(
        _noiseBurst(0.18, gain: 0.12, cutStart: 0.95, cutEnd: 0.7),
        0.4,
      ),
    ),
  ]),
);

/// Shimmering unlock.
List<double> _bladeUnlock() => _master(
  _mix([
    _tone(0.5, 1318, f1: 1760, gain: 0.24, curve: 2.2),
    _at(0.08, _tone(0.44, 1976, f1: 2637, gain: 0.20, curve: 2.2)),
    _highpass(
      _noiseBurst(0.55, gain: 0.18, cutStart: 0.6, cutEnd: 0.9, curve: 1.6),
      0.35,
    ),
  ]),
);

/// Rising two-tone warning: a core has been freed and is counting down.
List<double> _coreArm() => _master(
  _mix([
    _tone(0.14, 620, f1: 880, gain: 0.28, curve: 3.4),
    _at(0.16, _tone(0.16, 780, f1: 1100, gain: 0.30, curve: 3.0)),
    _at(0.16, _tone(0.16, 1170, gain: 0.12, curve: 3.0)),
  ]),
);

/// The blast: a soft body thump under a bright pop. Deliberately playful --
/// this is a shove that repositions pieces, not an explosion.
List<double> _coreBlast() => _master(
  _mix([
    _tone(0.34, 190, f1: 58, gain: 0.72, curve: 2.2),
    _tone(0.20, 420, f1: 150, gain: 0.34, curve: 2.8),
    _tone(0.16, 1250, f1: 700, gain: 0.22, curve: 4.0),
    _lowpass(
      _noiseBurst(0.30, gain: 0.5, cutStart: 0.7, cutEnd: 0.05, curve: 2.4),
      0.65,
    ),
    _at(
      0.02,
      _highpass(
        _noiseBurst(0.12, gain: 0.24, cutStart: 0.95, cutEnd: 0.5),
        0.3,
      ),
    ),
  ]),
);
