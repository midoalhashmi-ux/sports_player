// ============================================================================
// توليد/التحقق من توكن موقّع (HMAC-SHA256) لحماية بث HLS + بروكسي يمنع
// وصول رابط المصدر الحقيقي (privateStreams/{channelId}.url) للمستخدم
// إطلاقاً. لا يحتاج أي تخزين إضافي (لا KV) — التحقق حسابي بحت.
// ============================================================================

export const HLS_TOKEN_TTL_SECONDS = 240; // صلاحية كل توكن: 4 دقائق

async function hmacHex(secret, message) {
  const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
  );
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function signHlsToken(env, channelId, exp) {
  return hmacHex(env.HLS_TOKEN_SECRET, `${channelId}:${exp}`);
}

// مقارنة بوقت ثابت لتفادي timing attacks
export async function verifyHlsToken(env, channelId, exp, sig) {
  if (!sig || !exp) return false;
  if (Date.now() / 1000 > Number(exp)) return false;
  const expected = await hmacHex(env.HLS_TOKEN_SECRET, `${channelId}:${exp}`);
  if (expected.length !== sig.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ sig.charCodeAt(i);
  return diff === 0;
}

export function buildHlsPlaybackUrl(workerOrigin, channelId, exp, sig) {
  return `${workerOrigin}/hls/${channelId}/playlist.m3u8?exp=${exp}&sig=${sig}`;
}

// يعيد كتابة كل سطر رابط داخل m3u8 ليمر عبر نفس الـ Worker بنفس التوكن،
// بدل الإشارة لرابط المصدر الحقيقي مباشرة.
export function rewriteHlsPlaylist(text, channelId, exp, sig, workerOrigin) {
  return text
      .split('\n')
      .map((line) => {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith('#')) return line;
        const fileName = trimmed.split('/').pop().split('?')[0];
        return `${workerOrigin}/hls/${channelId}/${fileName}?exp=${exp}&sig=${sig}`;
      })
      .join('\n');
}
