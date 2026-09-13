import 'package:flutter_test/flutter_test.dart';
import 'package:sports_player/services/candidate_scoring.dart';

void main() {
  group('containsMediaMarker', () {
    test('detects an HLS manifest tag', () {
      expect(CandidateScoring.containsMediaMarker('#EXTM3U\n#EXT-X-VERSION:3'), isTrue);
    });
    test('detects an .m3u8 mention', () {
      expect(CandidateScoring.containsMediaMarker('window.src = "a.m3u8"'), isTrue);
    });
    test('detects a <video> tag', () {
      expect(CandidateScoring.containsMediaMarker('<video src="a.mp4">'), isTrue);
    });
    test('plain text has no marker', () {
      expect(CandidateScoring.containsMediaMarker('hello world'), isFalse);
    });
  });

  group('isDirectPlayable', () {
    test('.m3u8 is playable', () {
      expect(CandidateScoring.isDirectPlayable('https://x.com/a.m3u8'), isTrue);
    });
    test('.mp4 with query string is playable', () {
      expect(CandidateScoring.isDirectPlayable('https://x.com/a.mp4?token=1'), isTrue);
    });
    test('an image is not playable', () {
      expect(CandidateScoring.isDirectPlayable('https://x.com/a.jpg'), isFalse);
    });
  });

  group('normalizeCandidate', () {
    test('strips the URL fragment', () {
      expect(CandidateScoring.normalizeCandidate('https://x.com/a.m3u8#t=10'),
          'https://x.com/a.m3u8');
    });
    test('trims surrounding whitespace', () {
      expect(CandidateScoring.normalizeCandidate('  https://x.com/a.m3u8  '),
          'https://x.com/a.m3u8');
    });
    test('strips a stray trailing slash right after .m3u8', () {
      expect(CandidateScoring.normalizeCandidate('https://s43.grzcdn.com/hls/x/master.m3u8/'),
          'https://s43.grzcdn.com/hls/x/master.m3u8');
    });
    test('does not touch a trailing slash on a non-manifest path', () {
      expect(CandidateScoring.normalizeCandidate('https://x.com/hls/'),
          'https://x.com/hls/');
    });
  });

  group('looksLikeHls', () {
    test('.m3u8 URL', () {
      expect(CandidateScoring.looksLikeHls('https://x.com/a.m3u8'), isTrue);
    });
    test('.m3u URL (optional trailing 8)', () {
      expect(CandidateScoring.looksLikeHls('https://x.com/a.m3u'), isTrue);
    });
    test('an /hls/ path segment', () {
      expect(CandidateScoring.looksLikeHls('https://x.com/hls/seg1.ts'), isTrue);
    });
    test('a plain .mp4 URL is not HLS', () {
      expect(CandidateScoring.looksLikeHls('https://x.com/a.mp4'), isFalse);
    });
  });

  group('looksLikeProgressiveVideo', () {
    test('.mp4 with query string', () {
      expect(CandidateScoring.looksLikeProgressiveVideo('https://x.com/a.mp4?x=1'), isTrue);
    });
    test('.m3u8 is not progressive', () {
      expect(CandidateScoring.looksLikeProgressiveVideo('https://x.com/a.m3u8'), isFalse);
    });
  });

  group('scoreDetectedSource', () {
    test('an HLS live master manifest scores highest', () {
      expect(CandidateScoring.scoreDetectedSource('https://x.com/live/master.m3u8'), 150);
    });
    test('an ad segment scores negative', () {
      expect(CandidateScoring.scoreDetectedSource('https://x.com/ads/seg-1.ts'), -200);
    });
    test('a channel playlist manifest', () {
      expect(
          CandidateScoring.scoreDetectedSource('https://cdn.example.com/channel/playlist.m3u8'),
          130);
    });
  });

  group('isNonMediaAsset', () {
    test('an image asset', () {
      expect(CandidateScoring.isNonMediaAsset('https://x.com/logo.png'), isTrue);
    });
    test('a bare domain with root path only', () {
      expect(CandidateScoring.isNonMediaAsset('https://x.com/'), isTrue);
    });
    test('a bare domain with no path at all', () {
      expect(CandidateScoring.isNonMediaAsset('https://x.com'), isTrue);
    });
    test('a double-slash-only path (real false positive seen in a diagnostic log)', () {
      expect(CandidateScoring.isNonMediaAsset('https://miravid.club//'), isTrue);
    });
    test('a real manifest path is not a non-media asset', () {
      expect(CandidateScoring.isNonMediaAsset('https://x.com/stream/master.m3u8'), isFalse);
    });
    test('an HLS AES-128 encryption key under /hls/ (real false positive seen in a diagnostic log)', () {
      expect(
        CandidateScoring.isNonMediaAsset(
            'https://s32.grzcdn.com/hls/yqdzva4ayxypzfhh/encryption.key'),
        isTrue,
      );
    });
  });
}
