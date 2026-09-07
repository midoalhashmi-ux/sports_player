// ============================================================================
// أدوات مساعدة: توليد Access Token من حساب خدمة Google، وقراءة/كتابة
// Firestore عبر REST API — بدون أي مكتبة Firebase Admin (غير متاحة في بيئة
// Cloudflare Workers)، فقط Web Crypto القياسي المتوفر في كل Worker.
// ============================================================================

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/datastore';

let cachedToken = null; // { accessToken, expiresAt } — يُعاد استخدامه بين الطلبات داخل نفس الـ isolate

function base64UrlEncode(bytes) {
  let binary = '';
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  for (let i = 0; i < view.length; i++) binary += String.fromCharCode(view[i]);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function textToBase64Url(text) {
  return base64UrlEncode(new TextEncoder().encode(text));
}

function pemToArrayBuffer(pem) {
  const clean = pem
      .replace(/-----BEGIN PRIVATE KEY-----/, '')
      .replace(/-----END PRIVATE KEY-----/, '')
      .replace(/\s+/g, '');
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function signJwt(env) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: env.GCP_SERVICE_ACCOUNT_EMAIL,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };

  const unsigned = `${textToBase64Url(JSON.stringify(header))}.${textToBase64Url(JSON.stringify(claims))}`;

  const privateKeyPem = env.GCP_SERVICE_ACCOUNT_PRIVATE_KEY.replace(/\\n/g, '\n');
  const key = await crypto.subtle.importKey(
      'pkcs8',
      pemToArrayBuffer(privateKeyPem),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
  );

  const signature = await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      key,
      new TextEncoder().encode(unsigned),
  );

  return `${unsigned}.${base64UrlEncode(signature)}`;
}

// يعيد Access Token صالح، ويعيد استخدام النسخة المخزنة مؤقتاً لو باقي عليها
// أكثر من دقيقتين قبل الانتهاء — لتقليل عدد الطلبات لخادم Google.
export async function getAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - now > 120) {
    return cachedToken.accessToken;
  }

  const jwt = await signJwt(env);
  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    throw new Error(`تعذر الحصول على رمز دخول Google (${response.status}): ${await response.text()}`);
  }

  const body = await response.json();
  cachedToken = { accessToken: body.access_token, expiresAt: now + body.expires_in };
  return cachedToken.accessToken;
}

function firestoreBaseUrl(env) {
  return `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;
}

// يحوّل قيمة JS عادية إلى الشكل المُنمَّط (typed) الذي يتطلبه Firestore REST.
function toFirestoreValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(toFirestoreValue) } };
  }
  if (typeof value === 'object') {
    return { mapValue: { fields: toFirestoreFields(value) } };
  }
  return { stringValue: String(value) };
}

function toFirestoreFields(obj) {
  const fields = {};
  for (const key of Object.keys(obj)) fields[key] = toFirestoreValue(obj[key]);
  return fields;
}

// يحوّل استجابة Firestore REST (fields مُنمَّطة) إلى كائن JS عادي.
function fromFirestoreValue(value) {
  if (!value) return null;
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('nullValue' in value) return null;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(fromFirestoreValue);
  if ('mapValue' in value) return fromFirestoreFields(value.mapValue.fields || {});
  return null;
}

export function fromFirestoreFields(fields) {
  const obj = {};
  for (const key of Object.keys(fields || {})) obj[key] = fromFirestoreValue(fields[key]);
  return obj;
}

// GET مستند واحد. يعيد null لو غير موجود (404).
export async function getDoc(env, path) {
  const token = await getAccessToken(env);
  const response = await fetch(`${firestoreBaseUrl(env)}/${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (response.status === 404) return null;
  if (!response.ok) {
    throw new Error(`فشلت قراءة ${path} (${response.status}): ${await response.text()}`);
  }
  const body = await response.json();
  return fromFirestoreFields(body.fields || {});
}

// يستبدل مستنداً بالكامل بالحقول المُعطاة (نفس سلوك .set() بدون merge).
export async function setDoc(env, path, data) {
  const token = await getAccessToken(env);
  const response = await fetch(`${firestoreBaseUrl(env)}/${path}`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ fields: toFirestoreFields(data) }),
  });
  if (!response.ok) {
    throw new Error(`فشلت كتابة ${path} (${response.status}): ${await response.text()}`);
  }
  return response.json();
}
