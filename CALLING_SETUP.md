# Chat Plus voice calls — Firestore rule additions

The first-stage WebRTC call UI uses these Firestore paths:

`families/{familyId}/conversations/{conversationId}/calls/{callId}`
`families/{familyId}/conversations/{conversationId}/calls/{callId}/candidates/{candidateId}`

**Do not replace your entire Firestore rules file with this snippet.**
Inside your existing `match /families/{familyId}/conversations/{conversationId}` block, add:

```javascript
match /calls/{callId} {
  function chatMember() {
    return request.auth != null &&
      request.auth.uid in get(/databases/$(database)/documents/families/$(familyId)/conversations/$(conversationId)).data.memberIds;
  }
  allow get, list: if chatMember();
  allow create: if chatMember() &&
    request.resource.data.callerId == request.auth.uid &&
    request.resource.data.status == 'preparing' &&
    request.resource.data.recipientId in get(/databases/$(database)/documents/families/$(familyId)/conversations/$(conversationId)).data.memberIds;
  allow update: if chatMember() &&
    request.resource.data.callerId == resource.data.callerId &&
    request.resource.data.recipientId == resource.data.recipientId &&
    request.resource.data.memberIds == resource.data.memberIds &&
    request.resource.data.status in ['ringing', 'accepted', 'ended', 'declined'];
  allow delete: if false;

  match /candidates/{candidateId} {
    allow get, list: if chatMember();
    allow create: if chatMember() &&
      request.resource.data.senderId == request.auth.uid &&
      request.resource.data.candidate is string;
    allow update, delete: if false;
  }
}
```

The above is an initial rule example. Review it alongside your full existing rules and test in the Firestore rules simulator before publishing.

**Limitations:** both people must currently have the conversation open to receive an incoming call. Background ringing requires push notifications and a global call listener. STUN-only connections can fail on restricted networks; a TURN service will be required for reliable calls. This is not yet production-ready.
