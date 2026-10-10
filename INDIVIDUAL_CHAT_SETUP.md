# Chat Plus personal accounts and voice fixes

New accounts choose a username and immediately see their personal chat inbox.
They no longer create a family or need a family administrator to invite another
person. New chat finds a registered username and creates the same conversation
ID for both participants, including if both start the chat simultaneously.
All existing family spaces are listed under Previous family chats; no existing
documents are moved or deleted. A new personal conversation and an old family
conversation between the same people remain separate histories.

## Rollout order

1. In Firebase project `our-family-app-9e21a`, publish the complete
   `firestore.rules` in Firestore Database → Rules. The file includes both the
   new personal paths and the existing family rules, plus read receipts and calls.
2. Deploy `firestore.indexes.json` to exempt voice payloads from indexing:
   `firebase deploy --only firestore --project our-family-app-9e21a` deploys
   both the rules and this index configuration. Review existing custom index
   definitions in the project before replacing its index configuration.
3. Merge the application change. The existing deployment workflow publishes
   the updated web app to the same GitHub Pages URL.
4. Close and reopen the app on both phones. Test with two distinct accounts.
   Tap New chat, enter the other account's username, and send text both ways.
   The second person should see that conversation in their personal inbox.

## Voice messages

Tap the microphone and allow access, speak, then tap Stop. Play the preview
and tap Send beside it. A failed send keeps the recording available for retry.
The browser chooses a supported recorder MIME type (including MP4 on Safari)
instead of forcing WebM/Opus. Playback failures are visible in the message.

Short recordings are stored in their private Firestore message document under
the same Firebase identity and member permissions as text. This removes the
separate Supabase upload/authentication dependency for new voice messages.
Maximum duration is 60 seconds and maximum raw size is 600,000 bytes; larger
recordings are rejected before writing. Base64 encoding can reach 800,000
bytes, below Firestore's 1 MiB document limit. This increases Firestore reads
and bandwidth for voice-heavy chats; use authenticated object storage with
short-lived access for longer recordings or larger usage. `audioBase64` is
excluded from indexes. Old audio links and existing photo/video uploads keep
their previous storage behavior; inaccessible or expired old links cannot be
repaired by this code change.

## Live calls

The inbox watches incoming call updates while the app remains open. It handles
the change from preparing to ringing, even when the recipient is viewing a
different personal chat. Remote WebRTC audio is attached to a renderer.
Microphone, signaling, and candidate failures are displayed instead of silently
closing the call. Calls are one-to-one only. Closed/background app ringing
still requires push notifications; it is not implemented here.

STUN-only calling can fail on mobile/restricted networks. Set the optional
`TURN_URL`, `TURN_USERNAME`, and `TURN_CREDENTIAL` build definitions to your
TURN provider's client credentials. These values are shipped in the browser
bundle, so do not use a provider account secret or an administrative key.
For production, issue expiring credentials through a trusted backend.

## Validation

Run `flutter analyze --no-fatal-infos`, `flutter test`, and a release web build.
Run `npm install`, then
`npx firebase emulators:exec --only firestore --project demo-chat-plus 'npm run test:rules'`.
The rules tests cover recipient visibility without a family, outsider denial,
sender impersonation, read receipts, bounded private voice messages, and call
roles and state transitions. Two physical phones are still needed to confirm
microphone permission, codec playback and WebRTC network behavior.
