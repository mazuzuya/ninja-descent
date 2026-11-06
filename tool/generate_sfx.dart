// Bakes the WebAudio sound effects of game js/game/audio.js into WAV assets.
// Same oscillators, exponential ramps and high-passed noise as the JS synth.
//
// Run from the project root:  dart run tool/generate_sfx.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 44100;
// WebAudio plays these straight to the destination; mobile speakers need a
// little more headroom-free level, so everything is scaled uniformly.
const double master = 3.0;
final _random = math.Random(7);

Float64List _buffer(double seconds) => Float64List((seconds * sampleRate).ceil());

// tone(frequency, duration, type, volume, slide) from audio.js.
void tone(Float64List out, double start, double frequency,
    {double duration = 0.08, String type = "triangle", double volume = 0.08, double slide = 1}) {
  final endFrequency = math.max(30.0, frequency * slide);
  final length = (duration * sampleRate).round();
  final offset = (start * sampleRate).round();
  var phase = 0.0;
  for (int i = 0; i < length && offset + i < out.length; i += 1) {
    final t = i / length;
    final f = frequency * math.pow(endFrequency / frequency, t);
    final gain = volume * math.pow(0.001 / volume, t);
    phase = (phase + f / sampleRate) % 1.0;
    final double sample;
    switch (type) {
      case "sine":
        sample = math.sin(phase * 2 * math.pi);
      case "square":
        sample = phase < 0.5 ? 1 : -1;
      case "sawtooth":
        sample = 2 * phase - 1;
      default:
        sample = 1 - 4 * (phase - 0.5).abs();
    }
    out[offset + i] += sample * gain;
  }
}

// noise(duration, volume, highpass) from audio.js: decaying white noise
// through a WebAudio-style biquad high-pass (Q = 1).
void noise(Float64List out, double start, {double duration = 0.12, double volume = 0.05, double highpass = 700}) {
  final length = (duration * sampleRate).ceil();
  final offset = (start * sampleRate).round();
  final w0 = 2 * math.pi * highpass / sampleRate;
  final alpha = math.sin(w0) / 2;
  final cosW0 = math.cos(w0);
  final a0 = 1 + alpha;
  final b0 = (1 + cosW0) / 2 / a0, b1 = -(1 + cosW0) / a0, b2 = (1 + cosW0) / 2 / a0;
  final a1 = -2 * cosW0 / a0, a2 = (1 - alpha) / a0;
  var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;
  for (int i = 0; i < length && offset + i < out.length; i += 1) {
    final x = (_random.nextDouble() * 2 - 1) * (1 - i / length);
    final y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1;
    x1 = x;
    y2 = y1;
    y1 = y;
    out[offset + i] += y * volume;
  }
}

void writeWav(String path, Float64List samples, {int rate = sampleRate, double gain = master}) {
  final data = ByteData(44 + samples.length * 2);
  void ascii(int at, String s) {
    for (int i = 0; i < s.length; i += 1) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, "RIFF");
  data.setUint32(4, 36 + samples.length * 2, Endian.little);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, "data");
  data.setUint32(40, samples.length * 2, Endian.little);
  for (int i = 0; i < samples.length; i += 1) {
    final v = (samples[i] * gain).clamp(-1.0, 1.0);
    data.setInt16(44 + i * 2, (v * 32767).round(), Endian.little);
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data.buffer.asUint8List());
}

void main() {
  const dir = "assets/sfx";
  final sounds = <String, Float64List Function()>{
    "jump": () {
      final b = _buffer(0.11);
      noise(b, 0, duration: 0.11, volume: 0.045, highpass: 900);
      tone(b, 0, 260, duration: 0.1, type: "sine", volume: 0.04, slide: 1.7);
      return b;
    },
    "shoot": () {
      final b = _buffer(0.07);
      tone(b, 0, 720, duration: 0.07, type: "triangle", volume: 0.07, slide: 1.35);
      noise(b, 0, duration: 0.07, volume: 0.035, highpass: 1500);
      return b;
    },
    "shoot_charged": () {
      final b = _buffer(0.18);
      tone(b, 0, 260, duration: 0.18, type: "triangle", volume: 0.07, slide: 2.2);
      noise(b, 0, duration: 0.07, volume: 0.035, highpass: 1500);
      return b;
    },
    "slash": () {
      final b = _buffer(0.16);
      noise(b, 0, duration: 0.16, volume: 0.08, highpass: 1200);
      tone(b, 0, 190, duration: 0.13, type: "sawtooth", volume: 0.035, slide: 2.8);
      return b;
    },
    "hit": () {
      final b = _buffer(0.14);
      tone(b, 0, 95, duration: 0.14, type: "square", volume: 0.07, slide: 0.55);
      noise(b, 0, duration: 0.09, volume: 0.06, highpass: 180);
      return b;
    },
    "dash": () {
      final b = _buffer(0.2);
      noise(b, 0, duration: 0.18, volume: 0.07, highpass: 450);
      tone(b, 0, 120, duration: 0.2, type: "sine", volume: 0.06, slide: 0.45);
      return b;
    },
    "victory": () {
      final b = _buffer(0.52);
      const notes = [440.0, 660.0, 880.0];
      for (int i = 0; i < 3; i += 1) {
        tone(b, i * 0.12, notes[i], duration: 0.28, type: "triangle", volume: 0.07, slide: 1.08);
      }
      return b;
    },
  };
  // coin(combo): pitch 660 * min(1.5, 1 + combo * 0.035) — the cap is reached at combo 15.
  for (int combo = 0; combo <= 15; combo += 1) {
    sounds["coin_$combo"] = () {
      final b = _buffer(0.08);
      tone(b, 0, 660 * math.min(1.5, 1 + combo * 0.035), duration: 0.08, type: "sine", volume: 0.065, slide: 1.35);
      return b;
    };
  }
  // Sounds beyond the JS set: weight on landings, boss cues, menu feedback.
  sounds.addAll({
    "land": () {
      final b = _buffer(0.1);
      tone(b, 0, 150, duration: 0.09, type: "sine", volume: 0.05, slide: 0.5);
      noise(b, 0, duration: 0.05, volume: 0.02, highpass: 300);
      return b;
    },
    "pound": () {
      final b = _buffer(0.3);
      tone(b, 0, 110, duration: 0.28, type: "sine", volume: 0.13, slide: 0.35);
      noise(b, 0, duration: 0.16, volume: 0.09, highpass: 150);
      return b;
    },
    "boss_hit": () {
      final b = _buffer(0.16);
      tone(b, 0, 210, duration: 0.14, type: "sawtooth", volume: 0.05, slide: 0.5);
      tone(b, 0, 1370, duration: 0.09, type: "sine", volume: 0.03, slide: 0.8);
      noise(b, 0, duration: 0.08, volume: 0.06, highpass: 900);
      return b;
    },
    "ui_tap": () {
      final b = _buffer(0.05);
      tone(b, 0, 880, duration: 0.04, type: "triangle", volume: 0.05, slide: 0.6);
      return b;
    },
    "ui_buy": () {
      final b = _buffer(0.5);
      for (final (i, f) in const [587.3, 698.5, 880.0, 1174.7].indexed) {
        tone(b, i * 0.07, f, duration: 0.24, type: "triangle", volume: 0.06, slide: 1.0);
      }
      return b;
    },
    "heal": () {
      final b = _buffer(0.42);
      for (final (i, f) in const [523.3, 659.3, 784.0].indexed) {
        tone(b, i * 0.07, f, duration: 0.26, type: "sine", volume: 0.06, slide: 1.02);
      }
      return b;
    },
    "boss_appear": () {
      final b = _buffer(1.8);
      for (final (f, v) in const [(98.0, 0.1), (146.8, 0.06), (233.1, 0.04), (311.0, 0.025)]) {
        tone(b, 0, f, duration: 1.75, type: "sine", volume: v, slide: 0.97);
      }
      tone(b, 0, 80, duration: 0.5, type: "sine", volume: 0.14, slide: 0.5);
      noise(b, 0, duration: 0.2, volume: 0.07, highpass: 200);
      return b;
    },
    "area_clear": () {
      final b = _buffer(1.0);
      for (final (i, f) in const [293.7, 392.0, 440.0, 587.3, 784.0].indexed) {
        tone(b, i * 0.11, f, duration: 0.5, type: "triangle", volume: 0.065, slide: 1.0);
      }
      tone(b, 0, 80, duration: 0.3, type: "sine", volume: 0.12, slide: 0.5);
      return b;
    },
    "gameover": () {
      final b = _buffer(1.3);
      for (final (i, f) in const [392.0, 311.1, 233.1, 146.8].indexed) {
        tone(b, i * 0.24, f, duration: 0.55, type: "triangle", volume: 0.07, slide: 0.96);
      }
      tone(b, 0.72, 70, duration: 0.55, type: "sine", volume: 0.13, slide: 0.6);
      return b;
    },
  });
  for (final entry in sounds.entries) {
    writeWav("$dir/${entry.key}.wav", entry.value());
  }
  writeWav("$dir/music_descent.wav", _descentLoop(), rate: musicRate, gain: 1);
  writeWav("$dir/music_boss.wav", _bossLoop(), rate: musicRate, gain: 1);
  stdout.writeln("Wrote ${sounds.length + 2} files to $dir/");
}

// ---- music: two seamless loops in the Japanese "in" scale (D Eb G A Bb) ----
const int musicRate = 22050;

// Mixes wrap around the loop end, so note tails continue into the loop start.
void _pluck(Float64List out, double at, double f, double dur, double vol) {
  // Karplus-Strong string, the koto voice.
  final period = (musicRate / f).round();
  final delay = Float64List(period);
  for (int i = 0; i < period; i += 1) {
    delay[i] = _random.nextDouble() * 2 - 1;
  }
  final start = (at * musicRate).round();
  final len = (dur * musicRate).round();
  var last = 0.0;
  for (int i = 0; i < len; i += 1) {
    final k = i % period;
    final v = delay[k];
    delay[k] = (v + last) * 0.4985;
    last = v;
    out[(start + i) % out.length] += v * vol;
  }
}

void _taiko(Float64List out, double at, double vol) {
  final start = (at * musicRate).round();
  final len = (0.5 * musicRate).round();
  var phase = 0.0;
  for (int i = 0; i < len; i += 1) {
    final t = i / musicRate;
    phase += (55 + 55 * math.exp(-t * 28)) / musicRate;
    final skin = t < 0.02 ? (_random.nextDouble() * 2 - 1) * 0.3 * (1 - t / 0.02) : 0.0;
    out[(start + i) % out.length] += (math.sin(phase * 2 * math.pi) * math.exp(-t * 7) + skin) * vol;
  }
}

void _flute(Float64List out, double at, double f, double dur, double vol) {
  // Shakuhachi-like: vibrato that deepens through the note, plus breath.
  final start = (at * musicRate).round();
  final len = (dur * musicRate).round();
  var phase = 0.0;
  var noiseLow = 0.0;
  for (int i = 0; i < len; i += 1) {
    final t = i / musicRate;
    final p = i / len;
    final env = math.min(1.0, t / 0.18) * math.min(1.0, (1 - p) / 0.3);
    phase += f * (1 + 0.006 * p * math.sin(t * 2 * math.pi * 5)) / musicRate;
    noiseLow += ((_random.nextDouble() * 2 - 1) - noiseLow) * 0.2;
    final v = math.sin(phase * 2 * math.pi) + 0.25 * math.sin(phase * 4 * math.pi) + noiseLow * 0.12;
    out[(start + i) % out.length] += v * env * vol;
  }
}

void _drone(Float64List out, double f, double vol) {
  // Whole cycles only, so the drone is continuous across the loop point.
  final cycles = (f * out.length / musicRate).round();
  for (int i = 0; i < out.length; i += 1) {
    final x = i / out.length;
    out[i] += vol * (math.sin(2 * math.pi * cycles * x) + 0.5 * math.sin(2 * math.pi * cycles * 2 * x)) * (0.8 + 0.2 * math.sin(2 * math.pi * 2 * x));
  }
}

Float64List _normalize(Float64List out, double peak) {
  var maximum = 0.0;
  for (final v in out) {
    maximum = math.max(maximum, v.abs());
  }
  for (int i = 0; i < out.length; i += 1) {
    out[i] *= peak / maximum;
  }
  return out;
}

const _d3 = 146.83, _eb3 = 155.56, _g3 = 196.0, _a3 = 220.0, _bb3 = 233.08;
const _d4 = 293.66, _eb4 = 311.13, _g4 = 392.0, _a4 = 440.0, _bb4 = 466.16, _d5 = 587.33;

Float64List _descentLoop() {
  const beat = 60 / 72;
  const bars = 8;
  final out = Float64List((bars * 4 * beat * musicRate).round());
  _drone(out, 73.42, 0.05);
  const melody = [
    [_d4, _a3, _bb3, _a3], [_g3, _a3, _d4, _eb4], [_d4, _a4, _g4, _eb4], [_d4, _bb3, _a3, _g3],
    [_d4, _g4, _a4, _bb4], [_a4, _g4, _eb4, _d4], [_d5, _bb4, _a4, _g4], [_eb4, _d4, _a3, _d3],
  ];
  for (int bar = 0; bar < bars; bar += 1) {
    final t = bar * 4 * beat;
    for (int n = 0; n < 4; n += 1) {
      _pluck(out, t + n * beat, melody[bar][n], 1.6, 0.13);
      if (bar.isOdd && n == 2) _pluck(out, t + (n + 0.5) * beat, melody[bar][n] * 2, 0.9, 0.06);
    }
    _taiko(out, t, 0.32);
    _taiko(out, t + 2.5 * beat, 0.16);
    _taiko(out, t + 3 * beat, 0.22);
  }
  _flute(out, 8 * beat, _a4, 3.2 * beat, 0.07);
  _flute(out, 12 * beat, _g4, 3.2 * beat, 0.07);
  _flute(out, 24 * beat, _d5, 2.8 * beat, 0.06);
  _flute(out, 28 * beat, _a4, 3.2 * beat, 0.07);
  return _normalize(out, 0.75);
}

Float64List _bossLoop() {
  const beat = 60 / 112;
  const bars = 8;
  final out = Float64List((bars * 4 * beat * musicRate).round());
  _drone(out, 73.42, 0.07);
  const riff = [_d3, _d3, _eb3, _d3, _a3, _g3, _eb3, _d3];
  for (int bar = 0; bar < bars; bar += 1) {
    final t = bar * 4 * beat;
    for (int n = 0; n < 8; n += 1) {
      final f = riff[n] * (bar >= 4 && n >= 4 ? 2 : 1);
      _pluck(out, t + n * beat / 2, f, 0.7, n % 4 == 0 ? 0.17 : 0.11);
    }
    for (final hit in const [0.0, 1.5, 2.0, 3.0, 3.5]) {
      _taiko(out, t + hit * beat, hit == 0 ? 0.4 : 0.26);
    }
    if (bar % 2 == 1) _flute(out, t + 2 * beat, bar >= 4 ? _d5 : _bb4, 1.8 * beat, 0.05);
  }
  return _normalize(out, 0.8);
}
