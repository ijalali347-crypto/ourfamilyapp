
const {onDocumentUpdated} = require('firebase-functions/v2/firestore');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getMessaging} = require('firebase-admin/messaging');
initializeApp();
async function notify(event) {
  const old = event.data.before.data();
  const call = event.data.after.data();
  if (old.status === 'ringing' || call.status !== 'ringing') return;
  const db = getFirestore();
  const [incomingBlock, outgoingBlock] = await Promise.all([
    db.doc('users/' + call.recipientId + '/callBlocks/' + call.callerId).get(),
    db.doc('users/' + call.callerId + '/callBlocks/' + call.recipientId).get()
  ]);
  if (incomingBlock.exists || outgoingBlock.exists) return;
  const current = await event.data.after.ref.get();
  if (current.data()?.status !== 'ringing') return;
  const devices = await db.collection('users/' + call.recipientId + '/pushTokens').get();
  const valid = devices.docs.filter(doc => typeof doc.data().token === 'string');
  // FCM limits each multicast request to 500 tokens.
  for (let offset = 0; offset < valid.length; offset += 500) {
    const batch = valid.slice(offset, offset + 500);
    const result = await getMessaging().sendEachForMulticast({
      tokens: batch.map(doc => doc.data().token),
      data: {callPath: event.data.after.ref.path},
      webpush: {headers: {TTL: '60', Urgency: 'high'}}
    });
    await Promise.all(result.responses.map((response, i) => {
      if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(response.error?.code))
        return batch[i].ref.delete();
      return Promise.resolve();
    }));
  }
}
exports.personalCallNotification = onDocumentUpdated('conversations/{conversationId}/calls/{callId}', notify);
exports.familyCallNotification = onDocumentUpdated('families/{familyId}/conversations/{conversationId}/calls/{callId}', notify);
