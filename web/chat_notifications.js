
window.enableChatNotifications = async function (vapidKey, config) {
  if (!('serviceWorker' in navigator) || !('Notification' in window)) throw new Error('Notifications are not supported here. Install Chat Plus on the home screen and try again.');
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') throw new Error('Notification permission was not granted.');
  const appSDK = await import('https://www.gstatic.com/firebasejs/10.13.2/firebase-app.js');
  const messagingSDK = await import('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging.js');
  if (!await messagingSDK.isSupported()) throw new Error('Push notifications are not supported by this browser.');
  const app = appSDK.getApps()[0] || appSDK.initializeApp(config);
  const registration = await navigator.serviceWorker.register('firebase-messaging-sw.js', { scope: './firebase-cloud-messaging-push-scope/' });
  await new Promise((resolve, reject) => {
    if (registration.active) return resolve();
    const worker = registration.installing || registration.waiting;
    if (!worker) return reject(new Error('Notification service could not start.'));
    worker.addEventListener('statechange', () => {
      if (worker.state === 'activated') resolve();
      if (worker.state === 'redundant') reject(new Error('Notification service failed to activate.'));
    });
  });
  const messaging = messagingSDK.getMessaging(app);
  window.disableChatNotifications = () => messagingSDK.deleteToken(messaging);
  return messagingSDK.getToken(messaging, { vapidKey, serviceWorkerRegistration: registration });
};
