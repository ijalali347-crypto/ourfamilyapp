importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: '__FIREBASE_API_KEY__',
  appId: '__FIREBASE_APP_ID__',
  messagingSenderId: '__FIREBASE_SENDER_ID__',
  projectId: '__FIREBASE_PROJECT_ID__',
  authDomain: '__FIREBASE_AUTH_DOMAIN__'
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'Chat Plus';
  return self.registration.showNotification(title, {
    body: payload.notification?.body || 'Incoming call',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: payload.data?.callId ? 'call-' + payload.data.callId : 'chat-plus',
    renotify: true,
    requireInteraction: true,
    vibrate: [700, 250, 700, 250, 1000],
    data: payload.data || {}
  });
});
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(clients.matchAll({type: 'window', includeUncontrolled: true}).then((windows) => {
    for (const client of windows) if ('focus' in client) return client.focus();
    return clients.openWindow('/ourfamilyapp/');
  }));
});
