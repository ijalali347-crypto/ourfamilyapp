window.chatPlusGetPushToken = async function(vapidKey) {
  if (!('serviceWorker' in navigator)) throw new Error('Service workers are not supported on this phone.');
  if (!window.firebase || !firebase.messaging) throw new Error('Firebase messaging bridge did not load.');
  const registration = await navigator.serviceWorker.register(
    '/ourfamilyapp/firebase-messaging-sw.js',
    { scope: '/ourfamilyapp/' }
  );
  await navigator.serviceWorker.ready;
  if (!firebase.apps.length) {
    firebase.initializeApp({
      apiKey: '__FIREBASE_API_KEY__',
      appId: '__FIREBASE_APP_ID__',
      messagingSenderId: '__FIREBASE_SENDER_ID__',
      projectId: '__FIREBASE_PROJECT_ID__',
      authDomain: '__FIREBASE_AUTH_DOMAIN__'
    });
  }
  return await firebase.messaging().getToken({
    vapidKey: vapidKey,
    serviceWorkerRegistration: registration
  });
};
