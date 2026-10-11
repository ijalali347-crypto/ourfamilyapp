
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = new URL('./', self.location.href).href;
  event.waitUntil(clients.matchAll({type: 'window', includeUncontrolled: true}).then(async windows => {
    for (const client of windows) {
      if (client.url.startsWith(target) && 'focus' in client) return client.focus();
    }
    return clients.openWindow(target);
  }));
});
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');
firebase.initializeApp({
  apiKey: 'AIzaSyAi2k2dK7nE7oFI3Y3ikfy5opSep-8Qb84',
  appId: '1:1066197684028:web:c7ecbb5e8d613f3da99839',
  messagingSenderId: '1066197684028',
  projectId: 'our-family-app-9e21a',
  authDomain: 'our-family-app-9e21a.firebaseapp.com'
});
firebase.messaging().onBackgroundMessage(payload => {
  return self.registration.showNotification('Chat Plus incoming call', {
    body: 'Someone is calling you. Tap to open Chat Plus.',
    tag: payload.data.callPath, requireInteraction: true,
    data: {callPath: payload.data.callPath}
  });
});
