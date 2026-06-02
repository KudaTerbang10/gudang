import 'package:audioplayers/audioplayers.dart';

class AppAudio {
  static final AppAudio _instance = AppAudio._();
  factory AppAudio() => _instance;
  AppAudio._();

  final AudioPlayer _player = AudioPlayer();

  Future<void> playSuccess() => _play('sounds/success.mp3');
  Future<void> playError() => _play('sounds/error.mp3');
  Future<void> playScan() => _play('sounds/scan.mp3');

  Future<void> _play(String source) async {
    await _player.play(AssetSource(source));
  }
}
