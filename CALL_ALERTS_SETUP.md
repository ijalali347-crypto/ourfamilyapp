# Chat Plus call blocking and alerts
Publish the complete updated Firestore rules before merging the application update.

In a one-to-one chat, open the three-dot menu and choose Block calls from this person. The block applies to their account across chats. Choose Unblock calls to restore calls. Text and voice messages are still available. An already connected call must be ended using End call.

Tap the bell in the inbox to enable call sound on each phone. Browser autoplay rules require this tap. Sound stops on answer, decline or end. Keep the tab open for foreground ringing.

## Background notifications
1. In Firebase project our-family-app-9e21a, open Project settings > Cloud Messaging > Web Push certificates and generate a key pair. Copy ONLY the public key.
2. Add GitHub repository Actions variable FCM_VAPID_KEY with that public key, then rebuild the web application.
3. Cloud Functions deployment requires a Firebase project eligible for functions deployment (normally Blaze billing). Review billing before enabling it.
4. With Firebase CLI authenticated to the correct project, run npm install in functions, then from the repository root run:
   firebase deploy --only functions --project our-family-app-9e21a
5. Open the updated application on each device, tap the bell and allow notifications. On iPhone, use an installed Home Screen app on a supported iOS version.
6. Test a call with recipient app closed, then a blocked caller. Tap the notification to open and answer.

A web notification uses the phone's notification settings. It cannot guarantee a continuous ringtone or native incoming-call screen when the web app is closed. Silent mode, focus mode, permission settings and browser/OS restrictions affect sound. Native Android/iOS calling integration is needed for a full phone-like experience.
Server notifications contain no message content. Push tokens are private to their account; the backend checks blocks before sending. Notifications expire after 60 seconds. Delivery is best effort, and a call ended during delivery can still produce a stale notification.
