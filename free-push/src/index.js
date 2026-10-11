import {createRemoteJWKSet, jwtVerify, importPKCS8, SignJWT} from 'jose';

const FIREBASE_KEYS = createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {status, headers: {'content-type': 'application/json', 'access-control-allow-origin': 'https://ijalali347-crypto.github.io', 'vary': 'Origin'}});
}

async function googleAccessToken(credentials) {
  const now = Math.floor(Date.now() / 1000);
  const key = await importPKCS8(credentials.private_key, 'RS256');
  const assertion = await new SignJWT({scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging'})
    .setProtectedHeader({alg: 'RS256'})
    .setIssuer(credentials.client_email)
    .setSubject(credentials.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(now).setExpirationTime(now + 3600).sign(key);
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {'content-type': 'application/x-www-form-urlencoded'},
    body: new URLSearchParams({grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion})
  });
  if (!response.ok) throw Error('Google token exchange failed');
  return (await response.json()).access_token;
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers: {'access-control-allow-origin': 'https://ijalali347-crypto.github.io', 'access-control-allow-methods': 'POST, OPTIONS', 'access-control-allow-headers': 'authorization, content-type'}});
    if (request.method !== 'POST' || new URL(request.url).pathname !== '/notify-call') return json({error: 'Not found'}, 404);
    if (request.headers.get('origin') !== 'https://ijalali347-crypto.github.io') return json({error: 'Origin not allowed'}, 403);
    try {
      const firebaseIdToken = request.headers.get('authorization')?.replace(/^Bearer /, '');
      if (!firebaseIdToken) return json({error: 'Login required'}, 401);
      const {payload} = await jwtVerify(firebaseIdToken, FIREBASE_KEYS, {
        issuer: 'https://securetoken.google.com/' + env.FIREBASE_PROJECT_ID,
        audience: env.FIREBASE_PROJECT_ID,
        algorithms: ['RS256']
      });
      if (payload.email_verified !== true) return json({error: 'Verify email first'}, 403);
      const {conversationId, callId} = await request.json();
      if (typeof conversationId !== 'string' || typeof callId !== 'string' || !/^[A-Za-z0-9._-]{1,180}$/.test(conversationId) || !/^[A-Za-z0-9_-]{1,180}$/.test(callId)) return json({error: 'Invalid call'}, 400);
      const credentials = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON);
      if (credentials.project_id !== env.FIREBASE_PROJECT_ID) throw Error('Project mismatch');
      const accessToken = await googleAccessToken(credentials);
      const base = 'https://firestore.googleapis.com/v1/projects/' + env.FIREBASE_PROJECT_ID + '/databases/(default)/documents';
      const authHeaders = {authorization: 'Bearer ' + accessToken};
      const callUrl = base + '/conversations/' + encodeURIComponent(conversationId) + '/calls/' + encodeURIComponent(callId);
      const callResponse = await fetch(callUrl, {headers: authHeaders});
      if (!callResponse.ok) return json({error: 'Call not found'}, 404);
      const call = await callResponse.json();
      const fields = call.fields || {};
      if (fields.callerId?.stringValue !== payload.sub || fields.status?.stringValue !== 'ringing') return json({error: 'Not authorized or no longer ringing'}, 403);
      if (fields.pushNotifiedAt) return json({ok: true, alreadySent: true});
      const recipientId = fields.recipientId?.stringValue;
      if (!recipientId || recipientId === payload.sub) return json({error: 'Invalid recipient'}, 400);
      const createdAt = Date.parse(fields.createdAt?.timestampValue || '');
      if (!Number.isFinite(createdAt) || Math.abs(Date.now() - createdAt) > 120000) return json({error: 'Call expired'}, 400);

      // Claim the notification once, using the document version as a precondition.
      const claimUrl = callUrl + '?updateMask.fieldPaths=pushNotifiedAt&currentDocument.updateTime=' + encodeURIComponent(call.updateTime);
      const claim = await fetch(claimUrl, {
        method: 'PATCH',
        headers: {...authHeaders, 'content-type': 'application/json'},
        body: JSON.stringify({fields: {pushNotifiedAt: {timestampValue: new Date().toISOString()}}})
      });
      if (!claim.ok) return json({ok: true, alreadySent: true});

      const devicesResponse = await fetch(base + '/pushTokens/' + encodeURIComponent(recipientId) + '/devices?pageSize=100', {headers: authHeaders});
      if (!devicesResponse.ok) throw Error('Could not read recipient devices');
      const devices = (await devicesResponse.json()).documents || [];
      const tokens = devices.map(device => device.fields?.registration?.stringValue).filter(Boolean);
      const profileResponse = await fetch(base + '/users/' + encodeURIComponent(payload.sub), {headers: authHeaders});
      const profile = profileResponse.ok ? await profileResponse.json() : {};
      const callerName = (profile.fields?.username?.stringValue || 'Someone').slice(0, 40);
      const sends = await Promise.allSettled(tokens.map(token => fetch(
        'https://fcm.googleapis.com/v1/projects/' + env.FIREBASE_PROJECT_ID + '/messages:send',
        {
          method: 'POST',
          headers: {...authHeaders, 'content-type': 'application/json'},
          body: JSON.stringify({message: {
            token,
            notification: {title: 'Incoming Chat Plus call', body: '@' + callerName + ' is calling you'},
            data: {type: 'incoming_call', conversationId, callId},
            webpush: {fcm_options: {link: 'https://ijalali347-crypto.github.io/ourfamilyapp/'}}
          }})
        }
      )));
      return json({ok: true, attempted: sends.length});
    } catch (error) {
      return json({error: 'Unable to send call notification'}, 500);
    }
  }
};
