import 'package:flutter_test/flutter_test.dart';
import 'package:sports_player/services/candidate_scoring.dart';
import 'package:sports_player/services/player_strategies/player_strategy.dart';

void main() {
  group('PlayerStrategy default behavior matches the old shared formula', () {
    const realManifest =
        'https://s32.grzcdn.com/hls/yqdzva4ayxypzfhh35oaylifvh7mqhuofrxemawqrnf6ggbxu64r2cxssyda/index-v1-a1.m3u8';

    for (final strategy in [
      PlayerStrategyRegistry.generic,
      PlayerStrategyRegistry.videoJs,
      PlayerStrategyRegistry.jwplayer,
    ]) {
      test('${strategy.id}: score = base + 85 (framework) + 85 (registered hls)', () {
        final expected = CandidateScoring.scoreDetectedSource(realManifest) + 85 + 85;
        expect(
          strategy.scoreCandidate(realManifest, isFrameworkSource: true, registeredAsHls: true),
          expected,
        );
      });

      test('${strategy.id}: score with no bonuses = base only', () {
        expect(
          strategy.scoreCandidate(realManifest, isFrameworkSource: false, registeredAsHls: false),
          CandidateScoring.scoreDetectedSource(realManifest),
        );
      });

      test('${strategy.id}: isNonMediaAsset defers to the shared base (covers #39/#40 fixes)', () {
        expect(strategy.isNonMediaAsset('$realManifest'.replaceAll('index-v1-a1.m3u8', 'encryption.key')), isTrue);
        expect(strategy.isNonMediaAsset('$realManifest'.replaceAll('index-v1-a1.m3u8', 'seg-1-v1-a1.ts')), isTrue);
        expect(strategy.isNonMediaAsset(realManifest), isFalse);
      });
    }
  });

  test('PlayerStrategyRegistry.select prefers JWPlayer-like mode, then video.js, then generic', () {
    expect(
      PlayerStrategyRegistry.select(isVideoJsMode: false, isJwPlayerLikeMode: true),
      same(PlayerStrategyRegistry.jwplayer),
    );
    expect(
      PlayerStrategyRegistry.select(isVideoJsMode: true, isJwPlayerLikeMode: false),
      same(PlayerStrategyRegistry.videoJs),
    );
    expect(
      PlayerStrategyRegistry.select(isVideoJsMode: false, isJwPlayerLikeMode: false),
      same(PlayerStrategyRegistry.generic),
    );
    // Both flags set (shouldn't happen in practice, but JWPlayer-like wins
    // deterministically rather than depending on evaluation order).
    expect(
      PlayerStrategyRegistry.select(isVideoJsMode: true, isJwPlayerLikeMode: true),
      same(PlayerStrategyRegistry.jwplayer),
    );
  });

  test('a strategy override is isolated to that strategy alone (the whole point of this file)', () {
    // A synthetic subclass proving structural isolation: overriding one
    // strategy's bonus must not change another strategy's behavior at all.
    final custom = _NoFrameworkBonusStrategy();
    const url = 'https://x.com/live/master.m3u8';
    final base = CandidateScoring.scoreDetectedSource(url);

    expect(custom.scoreCandidate(url, isFrameworkSource: true, registeredAsHls: false), base);
    expect(
      PlayerStrategyRegistry.jwplayer.scoreCandidate(url, isFrameworkSource: true, registeredAsHls: false),
      base + 85,
    );
    expect(
      PlayerStrategyRegistry.videoJs.scoreCandidate(url, isFrameworkSource: true, registeredAsHls: false),
      base + 85,
    );
  });
}

class _NoFrameworkBonusStrategy extends PlayerStrategy {
  @override
  String get id => 'no_framework_bonus_test_double';
  @override
  int frameworkEvidenceBonus() => 0;
}
