// lib/main.dart - Complete, corrected and mobile-ready
import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(GameWidget(game: NeonPongGame(), overlayBuilderMap: {
    'MainMenu': (ctx, game) => MainMenu(game: game as NeonPongGame),
    'PauseMenu': (ctx, game) => PauseMenu(game: game as NeonPongGame),
  }, initialActiveOverlays: ['MainMenu']));
}

enum Difficulty { easy, normal, hard, insane }

class NeonPongGame extends FlameGame with HasTappables, HasDraggables, TapDetector {
  late Paddle player, computer;
  late Ball ball;
  late TextComponent scoreText, highScoreText;
  late AudioPlayer musicPlayer;
  late AudioPlayer sfxPlayer;
  bool soundEnabled = true;
  Difficulty difficulty = Difficulty.normal;
  int highScore = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    final paddleWidth = size.x * 0.02;
    final paddleHeight = size.y * 0.18;

    player = Paddle(Vector2(paddleWidth + 10, (size.y - paddleHeight) / 2), Vector2(paddleWidth, paddleHeight));
    computer = Paddle(Vector2(size.x - paddleWidth - 10 - paddleWidth, (size.y - paddleHeight) / 2), Vector2(paddleWidth, paddleHeight));

    add(player);
    add(computer);

    ball = Ball(Vector2(size.x / 2 - 10, size.y / 2 - 10), Vector2.all(20));
    add(ball);

    scoreText = TextComponent(
      text: 'Score: 0',
      position: Vector2(size.x / 2, 12),
      anchor: Anchor.topCenter,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.redAccent, fontSize: 20, fontFamily: 'Roboto'),
      ),
    );
    add(scoreText);

    highScore = await _loadHighScore();
    highScoreText = TextComponent(
      text: 'High: $highScore',
      position: Vector2(size.x - 12, 12),
      anchor: Anchor.topRight,
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.redAccent, fontSize: 16),
      ),
    );
    add(highScoreText);

    // audio
    musicPlayer = AudioPlayer();
    sfxPlayer = AudioPlayer();

    try {
      await musicPlayer.setSource(AssetSource('8-bit-loop-music-290770.mp3'));
      musicPlayer.setReleaseMode(ReleaseMode.loop);
      if (soundEnabled) await musicPlayer.resume();
    } catch (e) {
      // ignore audio init failure on some CI envs
    }

    ball.reset(size);
  }

  double get aiSpeed {
    switch (difficulty) {
      case Difficulty.easy:
        return 180; // px/s
      case Difficulty.normal:
        return 260;
      case Difficulty.hard:
        return 380;
      case Difficulty.insane:
        return 560;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    // check scoring
    if (ball.outLeft(size.x) || ball.outRight(size.x)) {
      if (ball.outRight(size.x)) {
        player.score++;
        scoreText.text = 'Score: ${player.score}';
        if (player.score > highScore) {
          highScore = player.score;
          highScoreText.text = 'High: $highScore';
          _saveHighScore(highScore);
        }
      }
      ball.reset(size);
      // brief pause then serve
      Future.delayed(Duration(milliseconds: 300), () => ball.serve());
    }

    // AI: simple proportional tracking
    final targetY = ball.center.y - computer.height / 2;
    final diff = targetY - computer.position.y;
    final move = aiSpeed * dt;
    if (diff.abs() > move) {
      computer.position.y += diff.sign * move;
    } else {
      computer.position.y = targetY;
    }

    player.clampToScreen(size.y);
    computer.clampToScreen(size.y);
  }

  @override
  void onTapDown(TapDownInfo info) {
    if (ball.isStopped) {
      player.score = 0;
      scoreText.text = 'Score: 0';
      ball.reset(size);
      ball.serve();
    }
    super.onTapDown(info);
  }

  @override
  void onDragUpdate(int pointerId, DragUpdateInfo info) {
    if (info.eventPosition.global.x < size.x * 0.5) {
      player.center = Vector2(player.center.x, info.eventPosition.global.y);
    }
    super.onDragUpdate(pointerId, info);
  }

  void playHit() {
    if (!soundEnabled) return;
    sfxPlayer.play(AssetSource('hit.wav'));
  }

  void playOver() {
    if (!soundEnabled) return;
    sfxPlayer.play(AssetSource('over.wav'));
  }

  Future<int> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('high_score') ?? 0;
  }

  Future<void> _saveHighScore(int v) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('high_score', v);
  }

  void toggleSound() {
    soundEnabled = !soundEnabled;
    if (soundEnabled) musicPlayer.resume();
    else musicPlayer.pause();
  }

  void setDifficulty(Difficulty d) {
    difficulty = d;
  }
}

class Paddle extends PositionComponent {
  int score = 0;
  Paddle(Vector2 position, Vector2 size) : super(position: position, size: size, anchor: Anchor.topLeft);

  Vector2 get center => Vector2(position.x + width / 2, position.y + height / 2);
  set center(Vector2 v) => position = Vector2(position.x - width / 2, v.y - height / 2);

  void clampToScreen(double height) {
    if (position.y < 0) position.y = 0;
    if (position.y + this.height > height) position.y = height - this.height;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(position.x, position.y, width, height);
    final fillPaint = Paint()..color = const Color(0xFF220000);
    canvas.drawRect(rect, fillPaint);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFFFF3B3B).withOpacity(.9);
    canvas.drawRect(rect.inflate(2), glow);
  }
}

class Ball extends PositionComponent with HasGameRef<NeonPongGame> {
  Vector2 velocity = Vector2.zero();
  bool isStopped = true;

  Ball(Vector2 position, Vector2 size) : super(position: position, size: size, anchor: Anchor.topLeft);

  Vector2 get center => Vector2(position.x + width / 2, position.y + height / 2);

  void serve() {
    final rand = Random();
    final baseSpeed = 700.0; // px/s - tuneable
    final dx = rand.nextBool() ? baseSpeed : -baseSpeed;
    final dy = (rand.nextDouble() * 400) - 200;
    velocity = Vector2(dx, dy);
    isStopped = false;
  }

  void reset(Vector2 screenSize) {
    position = Vector2(screenSize.x / 2 - width / 2, screenSize.y / 2 - height / 2);
    velocity = Vector2.zero();
    isStopped = true;
  }

  bool outLeft(double w) => position.x + width < 0;
  bool outRight(double w) => position.x > w;

  @override
  void update(double dt) {
    super.update(dt);
    if (isStopped) return;

    position += velocity * dt;

    if (position.y <= 0) {
      position.y = 0;
      velocity.y = -velocity.y;
    } else if (position.y + height >= gameRef.size.y) {
      position.y = gameRef.size.y - height;
      velocity.y = -velocity.y;
    }

    final paddleRect = Rect.fromLTWH(gameRef.player.position.x, gameRef.player.position.y, gameRef.player.width, gameRef.player.height);
    final compRect = Rect.fromLTWH(gameRef.computer.position.x, gameRef.computer.position.y, gameRef.computer.width, gameRef.computer.height);
    final ballRect = Rect.fromLTWH(position.x, position.y, width, height);

    if (ballRect.overlaps(paddleRect) && velocity.x < 0) {
      velocity.x = -velocity.x * 1.05;
      velocity.y += (Random().nextDouble() * 300 - 150);
      gameRef.playHit();
    } else if (ballRect.overlaps(compRect) && velocity.x > 0) {
      velocity.x = -velocity.x * 1.05;
      velocity.y += (Random().nextDouble() * 300 - 150);
      gameRef.playHit();
    }

    final maxSpeed = 1500.0;
    if (velocity.length > maxSpeed) velocity = velocity.normalized() * maxSpeed;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromLTWH(position.x, position.y, width, height);
    final fill = Paint()..color = const Color(0xFF220000);
    canvas.drawOval(rect, fill);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFFFF3B3B).withOpacity(.95);
    canvas.drawOval(rect.inflate(4), glow);
  }
}

// Simple Flutter overlays for menus
class MainMenu extends StatelessWidget {
  final NeonPongGame game;
  const MainMenu({required this.game, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Neon Pong Revival', style: TextStyle(color: Colors.redAccent, fontSize: 28)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () {
              game.overlays.remove('MainMenu');
              game.ball.reset(game.size);
              game.ball.serve();
            }, child: const Text('Tap to Play')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: () {
              game.toggleSound();
            }, child: Text(game.soundEnabled ? 'Sound: On' : 'Sound: Off')),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: () {
              game.overlays.add('PauseMenu');
            }, child: const Text('Settings')),
          ],
        ),
      ),
    );
  }
}

class PauseMenu extends StatelessWidget {
  final NeonPongGame game;
  const PauseMenu({required this.game, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Settings', style: TextStyle(color: Colors.redAccent, fontSize: 22)),
            const SizedBox(height: 8),
            DropdownButton<Difficulty>(
              value: game.difficulty,
              dropdownColor: Colors.black,
              items: Difficulty.values.map((d) => DropdownMenuItem(value: d, child: Text(d.toString().split('.').last))).toList(),
              onChanged: (v) {
                if (v != null) game.setDifficulty(v);
              },
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: () { game.overlays.remove('PauseMenu'); }, child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
