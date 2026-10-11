const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.notifyIncomingCall = functions.firestore
  .document("conversations/{conversationId}/calls/{callId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    if (before.status === "ringing" || after.status !== "ringing") return null;

    const recipientId = after.recipientId;
    if (!recipientId) return null;

    const caller = await admin.firestore().collection("users").doc(after.callerId).get();
    const callerName = caller.exists ? (caller.data().username || "Someone") : "Someone";
    const devices = await admin.firestore().collection("pushTokens").doc(recipientId).collection("devices").get();
    const registrations = devices.docs.map(d => d.data().registration).filter(v => typeof v === "string" && v.length > 20);
    if (!registrations.length) return null;

    const response = await admin.messaging().sendEachForMulticast({
      tokens: registrations,
      notification: {
        title: "Incoming Chat Plus call",
        body: "@" + callerName + " is calling you"
      },
      data: {
        type: "incoming_call",
        conversationId: context.params.conversationId,
        callId: context.params.callId
      },
      webpush: {
        notification: {
          requireInteraction: true,
          tag: "call-" + context.params.callId
        },
        fcmOptions: {
          link: "https://ijalali347-crypto.github.io/ourfamilyapp/"
        }
      }
    });

    const batch = admin.firestore().batch();
    response.responses.forEach((item, i) => {
      if (!item.success && ["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(item.error?.code)) {
        const match = devices.docs.find(d => d.data().registration === registrations[i]);
        if (match) batch.delete(match.ref);
      }
    });
    await batch.commit();
    return null;
  });
