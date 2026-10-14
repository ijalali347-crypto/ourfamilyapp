const ALLOWED_ORIGIN = 'https://ijalali347-crypto.github.io';

const encoder = new TextEncoder();
const FIREBASE_KEYS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
function b64url(bytes) { const b = typeof bytes === 'string' ? encoder.encode(bytes) : new Uint8Array(bytes); let s = ''; for (const x of b) s += String.fromCharCode(x); return btoa(s).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/g, ''); }
function fromB64url(s) { const t = s.replace(/-/g, '+').replace(/_/g, '/'); const raw = atob(t + '='.repeat((4 - t.length % 4) % 4)); return Uint8Array.from(raw, x => x.charCodeAt(0)); }
function pemBytes(pem) { return Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, '').replace(/\\s/g, '')), x => x.charCodeAt(0)); }
async function signJwt(claims, privatePem) {
  const key = await crypto.subtle.importKey('pkcs8', pemBytes(privatePem), {name:'RSASSA-PKCS1-v1_5', hash:'SHA-256'}, false, ['sign']);
  const unsigned = b64url(JSON.stringify({alg:'RS256',typ:'JWT'})) + '.' + b64url(JSON.stringify(claims));
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, encoder.encode(unsigned));
  return unsigned + '.' + b64url(signature);
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json',
      'access-control-allow-origin': ALLOWED_ORIGIN,
      'vary': 'Origin'
    }
  });
}

function corsResponse() {
  return new Response(null, {
    status: 204,
    headers: {
      'access-control-allow-origin': ALLOWED_ORIGIN,
      'access-control-allow-methods': 'POST, OPTIONS',
      'access-control-allow-headers': 'authorization, content-type',
      'access-control-max-age': '86400'
    }
  });
}

async function verifyFirebaseUser(request, env) {
  const token = request.headers.get('authorization')?.replace(/^Bearer\\s+/i, '');
  if (!token) throw new Error('MISSING_TOKEN');
  if (!env.FIREBASE_PROJECT_ID) throw new Error('PROJECT_ID_MISSING');
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('INVALID_TOKEN_FORMAT');
  let header, payload;
  try {
    header = JSON.parse(new TextDecoder().decode(fromB64url(parts[0])));
    payload = JSON.parse(new TextDecoder().decode(fromB64url(parts[1])));
  } catch (_) { throw new Error('INVALID_TOKEN_FORMAT'); }
  const now = Math.floor(Date.now()/1000);
  if (header.alg !== 'RS256' || !header.kid) throw new Error('INVALID_TOKEN_HEADER');
  if (payload.aud !== env.FIREBASE_PROJECT_ID || payload.iss !== 'https://securetoken.google.com/' + env.FIREBASE_PROJECT_ID) throw new Error('PROJECT_MISMATCH');
  if (typeof payload.sub !== 'string' || !payload.sub || payload.sub.length > 128 || typeof payload.exp !== 'number' || payload.exp <= now || typeof payload.iat !== 'number' || payload.iat > now || typeof payload.auth_time !== 'number' || payload.auth_time > now) throw new Error('INVALID_TOKEN_CLAIMS');
  const response = await fetch(FIREBASE_KEYS_URL);
  if (!response.ok) throw new Error('PUBLIC_KEYS_UNAVAILABLE');
  const jwks = await response.json();
  const jwk = (jwks.keys || []).find(k => k.kid === header.kid && k.kty === 'RSA');
  if (!jwk) throw new Error('SIGNING_KEY_NOT_FOUND');
  const key = await crypto.subtle.importKey('jwk', jwk, {name:'RSASSA-PKCS1-v1_5', hash:'SHA-256'}, false, ['verify']);
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, fromB64url(parts[2]), encoder.encode(parts[0]+'.'+parts[1]));
  if (!valid) throw new Error('INVALID_SIGNATURE');
  return payload;
}

async function googleAccessToken(credentials) {
  const now = Math.floor(Date.now() / 1000);

  const assertion = await signJwt({
    scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging',
    iss: credentials.client_email,
    sub: credentials.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600
  }, credentials.private_key);

  const response = await fetch(
    'https://oauth2.googleapis.com/token',
    {
      method: 'POST',
      headers: {
        'content-type':
          'application/x-www-form-urlencoded'
      },
      body: new URLSearchParams({
        grant_type:
          'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion
      })
    }
  );

  if (!response.ok) {
    throw new Error(
      'Google token exchange failed'
    );
  }

  const result = await response.json();

  return result.access_token;
}

async function generateTurnCredentials(
  request,
  env
) {
  try {
    await verifyFirebaseUser(request, env);
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'UNKNOWN';
    console.warn('CHAT_PLUS_AUTH_FAILURE', reason);
    return json({error: 'Firebase authentication failed', reason}, 401);
  }

  if (
    !env.CLOUDFLARE_TURN_TOKEN_ID ||
    !env.CLOUDFLARE_TURN_API_TOKEN
  ) {
    return json(
      {error: 'TURN is not configured'},
      503
    );
  }

  try {
    const response = await fetch(
      'https://rtc.live.cloudflare.com/v1/turn/keys/' +
        encodeURIComponent(
          env.CLOUDFLARE_TURN_TOKEN_ID
        ) +
        '/credentials/generate-ice-servers',
      {
        method: 'POST',
        headers: {
          'Authorization':
            'Bearer ' +
            env.CLOUDFLARE_TURN_API_TOKEN,
          'Content-Type':
            'application/json'
        },
        body: JSON.stringify({
          ttl: 14400
        })
      }
    );

    if (!response.ok) {
      return json(
        {error: 'TURN provider unavailable'},
        502
      );
    }

    const result = await response.json();

    if (!Array.isArray(result.iceServers)) {
      return json(
        {error: 'Invalid TURN response'},
        502
      );
    }

    return json({
      iceServers: result.iceServers
    });
  } catch (_) {
    return json(
      {error: 'Unable to generate TURN credentials'},
      502
    );
  }
}

async function notifyCall(request, env) {
  let payload;

  try {
    payload = await verifyFirebaseUser(
      request,
      env
    );
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'UNKNOWN';
    console.warn('CHAT_PLUS_AUTH_FAILURE', reason);
    return json({error: 'Firebase authentication failed', reason}, 401);
  }

  try {
    const body = await request.json();

    const conversationId =
      body.conversationId;

    const callId =
      body.callId;

    if (
      typeof conversationId !== 'string' ||
      typeof callId !== 'string' ||
      !/^[A-Za-z0-9._-]{1,180}$/.test(
        conversationId
      ) ||
      !/^[A-Za-z0-9_-]{1,180}$/.test(
        callId
      )
    ) {
      return json(
        {error: 'Invalid call'},
        400
      );
    }

    const credentials = JSON.parse(
      env.FIREBASE_SERVICE_ACCOUNT_JSON
    );

    if (
      credentials.project_id !==
      env.FIREBASE_PROJECT_ID
    ) {
      throw new Error(
        'Project mismatch'
      );
    }

    const accessToken =
      await googleAccessToken(
        credentials
      );

    const base =
      'https://firestore.googleapis.com/v1/projects/' +
      env.FIREBASE_PROJECT_ID +
      '/databases/(default)/documents';

    const authHeaders = {
      authorization:
        'Bearer ' + accessToken
    };

    const callUrl =
      base +
      '/conversations/' +
      encodeURIComponent(
        conversationId
      ) +
      '/calls/' +
      encodeURIComponent(callId);

    const callResponse =
      await fetch(callUrl, {
        headers: authHeaders
      });

    if (!callResponse.ok) {
      return json(
        {error: 'Call not found'},
        404
      );
    }

    const call =
      await callResponse.json();

    const fields =
      call.fields || {};

    if (
      fields.callerId?.stringValue !==
        payload.sub ||
      fields.status?.stringValue !==
        'ringing'
    ) {
      return json(
        {
          error:
            'Not authorized or no longer ringing'
        },
        403
      );
    }

    if (fields.pushNotifiedAt) {
      return json({
        ok: true,
        alreadySent: true
      });
    }

    const recipientId =
      fields.recipientId?.stringValue;

    if (
      !recipientId ||
      recipientId === payload.sub
    ) {
      return json(
        {error: 'Invalid recipient'},
        400
      );
    }

    const createdAt = Date.parse(
      fields.createdAt?.timestampValue ||
        ''
    );

    if (
      !Number.isFinite(createdAt) ||
      Math.abs(
        Date.now() - createdAt
      ) > 120000
    ) {
      return json(
        {error: 'Call expired'},
        400
      );
    }

    const claimUrl =
      callUrl +
      '?updateMask.fieldPaths=pushNotifiedAt' +
      '&currentDocument.updateTime=' +
      encodeURIComponent(
        call.updateTime
      );

    const claim = await fetch(
      claimUrl,
      {
        method: 'PATCH',
        headers: {
          ...authHeaders,
          'content-type':
            'application/json'
        },
        body: JSON.stringify({
          fields: {
            pushNotifiedAt: {
              timestampValue:
                new Date().toISOString()
            }
          }
        })
      }
    );

    if (!claim.ok) {
      return json({
        ok: true,
        alreadySent: true
      });
    }

    const devicesResponse =
      await fetch(
        base +
          '/pushTokens/' +
          encodeURIComponent(
            recipientId
          ) +
          '/devices?pageSize=100',
        {
          headers: authHeaders
        }
      );

    if (!devicesResponse.ok) {
      throw new Error(
        'Could not read recipient devices'
      );
    }

    const devicesData =
      await devicesResponse.json();

    const devices =
      devicesData.documents || [];

    const tokens = devices
      .map(
        device =>
          device.fields
            ?.registration
            ?.stringValue
      )
      .filter(Boolean);

    const profileResponse =
      await fetch(
        base +
          '/users/' +
          encodeURIComponent(
            payload.sub
          ),
        {
          headers: authHeaders
        }
      );

    const profile =
      profileResponse.ok
        ? await profileResponse.json()
        : {};

    const callerName = (
      profile.fields?.name
        ?.stringValue ||
      profile.fields?.username
        ?.stringValue ||
      'Someone'
    ).slice(0, 40);

    const video =
      fields.video?.booleanValue ===
      true;

    const callKind = video
      ? 'video call'
      : 'voice call';

    const sends =
      await Promise.allSettled(
        tokens.map(token =>
          fetch(
            'https://fcm.googleapis.com/v1/projects/' +
              env.FIREBASE_PROJECT_ID +
              '/messages:send',
            {
              method: 'POST',
              headers: {
                ...authHeaders,
                'content-type':
                  'application/json'
              },
              body: JSON.stringify({
                message: {
                  token,

                  notification: {
                    title: video
                      ? 'Incoming Chat Plus video call'
                      : 'Incoming Chat Plus voice call',

                    body:
                      callerName +
                      ' is calling you'
                  },

                  data: {
                    type:
                      'incoming_call',

                    conversationId,

                    callId,

                    video: video
                      ? 'true'
                      : 'false',

                    callKind
                  },

                  webpush: {
                    fcm_options: {
                      link:
                        'https://ijalali347-crypto.github.io/ourfamilyapp/'
                    }
                  }
                }
              })
            }
          )
        )
      );

    return json({
      ok: true,
      attempted: sends.length
    });
  } catch (_) {
    return json(
      {
        error:
          'Unable to send call notification'
      },
      500
    );
  }
}

export default {
  async fetch(request, env) {
    const url =
      new URL(request.url);

    if (request.method === 'OPTIONS') {
      return corsResponse();
    }

    if (
      request.headers.get('origin') !==
      ALLOWED_ORIGIN
    ) {
      return json(
        {error: 'Origin not allowed'},
        403
      );
    }

    if (
      request.method === 'POST' &&
      url.pathname ===
        '/turn-credentials'
    ) {
      return generateTurnCredentials(
        request,
        env
      );
    }

    if (
      request.method === 'POST' &&
      url.pathname ===
        '/notify-call'
    ) {
      return notifyCall(
        request,
        env
      );
    }

    return json(
      {error: 'Not found'},
      404
    );
  }
};
