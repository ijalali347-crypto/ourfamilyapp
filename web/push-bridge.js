window.chatPlusGetPushToken = async function(vapidKey) {
  const registration = await navigator.serviceWorker.register('/ourfamilyapp/firebase-messaging-sw.js', {scope:'/ourfamilyapp/'});
  await navigator.serviceWorker.ready;
  if (!firebase.apps.length) firebase.initializeApp({
    apiKey:'AIzaSyAi2k2dK7nE7oFI3Y3ikfy5opSep-8Qb84',
    appId:'1:1066197684028:web:c7ecbb5e8d613f3da99839',
    messagingSenderId:'1066197684028',
    projectId:'our-family-app-9e21a',
    authDomain:'our-family-app-9e21a.firebaseapp.com'
  });
  return firebase.messaging().getToken({vapidKey:vapidKey, serviceWorkerRegistration:registration});
};