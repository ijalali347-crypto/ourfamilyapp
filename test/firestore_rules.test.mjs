import { readFile } from 'node:fs/promises';
import { after, before, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, where, setDoc, updateDoc, serverTimestamp, arrayUnion, deleteDoc } from 'firebase/firestore';

let env;
const chat = 'conversations/test-chat';
before(async () => {
  env = await initializeTestEnvironment({ projectId: 'demo-chat-plus', firestore: {
    host: '127.0.0.1', port: 8080, rules: await readFile('firestore.rules', 'utf8'),
  } });
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), chat), {
      type: 'direct', memberIds: ['alice', 'bob'], adminIds: ['alice'], createdBy: 'alice',
      title: 'Private chat', lastMessage: '', createdAt: new Date(), updatedAt: new Date(),
    });
  });
});
const db = uid => env.authenticatedContext(uid).firestore();

test('new-chat transaction can read a missing ID, without exposing existing private chats', async () => {
  await assertSucceeds(getDoc(doc(db('alice'), 'conversations/new-chat')));
  await assertFails(getDoc(doc(db('stranger'), chat)));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'conversations/new-chat')));
});
test('recipient sees shared conversation without any family document', async () => {
  await assertSucceeds(getDocs(query(collection(db('bob'), 'conversations'), where('memberIds', 'array-contains', 'bob'))));
  await assertFails(getDocs(collection(db('bob'), 'conversations')));
});
test('messages cross accounts; outsiders and spoofed senders are denied', async () => {
  const path = `${chat}/messages/message`;
  await assertSucceeds(setDoc(doc(db('alice'), path), { senderId: 'alice', type: 'text', text: 'Hello', readBy: ['alice'], createdAt: serverTimestamp() }));
  await assertSucceeds(getDoc(doc(db('bob'), path)));
  await assertFails(getDoc(doc(db('stranger'), path)));
  await assertFails(setDoc(doc(db('bob'), `${chat}/messages/spoof`), { senderId: 'alice', type: 'text', text: 'Spoof', readBy: ['bob'], createdAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(doc(db('bob'), path), { readBy: arrayUnion('bob') }));
  await assertFails(updateDoc(doc(db('bob'), path), { text: 'Edited by recipient' }));
  await assertFails(updateDoc(doc(db('bob'), path), { readBy: ['bob'] }));
});
test('voice messages stay private and reject oversized recordings', async () => {
  const voice = { senderId: 'alice', type: 'audio', audioBase64: 'YWJj', audioMimeType: 'audio/mp4', durationSeconds: 3, readBy: ['alice'], createdAt: serverTimestamp() };
  await assertSucceeds(setDoc(doc(db('alice'), `${chat}/messages/voice`), voice));
  await assertSucceeds(getDoc(doc(db('bob'), `${chat}/messages/voice`)));
  await assertFails(getDoc(doc(db('stranger'), `${chat}/messages/voice`)));
  await assertFails(setDoc(doc(db('alice'), `${chat}/messages/too-long`), { ...voice, durationSeconds: 61 }));
  await assertFails(setDoc(doc(db('alice'), `${chat}/messages/too-big`), { ...voice, audioBase64: 'A'.repeat(800001) }));
});
test('only caller offers, only recipient answers, and terminal calls cannot reopen', async () => {
  const path = `${chat}/calls/call`;
  await assertSucceeds(setDoc(doc(db('alice'), path), { callerId: 'alice', recipientId: 'bob', memberIds: ['alice', 'bob'], status: 'preparing', createdAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db('bob'), path), { status: 'ringing', offer: { type: 'offer', sdp: 'offer' } }));
  await assertSucceeds(updateDoc(doc(db('alice'), path), { status: 'ringing', offer: { type: 'offer', sdp: 'offer' } }));
  await assertSucceeds(getDocs(query(collection(db('bob'), `${chat}/calls`), where('recipientId', '==', 'bob'))));
  await assertFails(updateDoc(doc(db('alice'), path), { status: 'accepted', answer: { type: 'answer', sdp: 'answer' } }));
  await assertSucceeds(updateDoc(doc(db('bob'), path), { status: 'accepted', answer: { type: 'answer', sdp: 'answer' } }));
  await assertFails(updateDoc(doc(db('bob'), path), { callerId: 'bob' }));
  await assertSucceeds(setDoc(doc(db('bob'), `${path}/candidates/ice`), { senderId: 'bob', candidate: 'candidate', sdpMid: null, sdpMLineIndex: 0, createdAt: serverTimestamp() }));
  await assertFails(getDoc(doc(db('stranger'), `${path}/candidates/ice`)));
  await assertSucceeds(updateDoc(doc(db('bob'), path), { status: 'ended', endedAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db('alice'), path), { status: 'ringing', offer: { type: 'offer', sdp: 'again' } }));
});


test('call blocking is owner-controlled and prevents calls across conversations', async () => {
  const block = 'users/bob/callBlocks/alice';
  await assertFails(setDoc(doc(db('alice'), block), { createdAt: serverTimestamp() }));
  await assertSucceeds(setDoc(doc(db('bob'), block), { createdAt: serverTimestamp() }));
  await assertFails(getDocs(collection(db('alice'), 'users/bob/callBlocks')));
  const call = { callerId: 'alice', recipientId: 'bob', memberIds: ['alice', 'bob'], status: 'preparing', createdAt: serverTimestamp() };
  await assertFails(setDoc(doc(db('alice'), `${chat}/calls/blocked`), call));
  await assertFails(deleteDoc(doc(db('alice'), block)));
  await assertSucceeds(deleteDoc(doc(db('bob'), block)));
  await assertSucceeds(setDoc(doc(db('alice'), `${chat}/calls/allowed`), call));
  await assertSucceeds(setDoc(doc(db('bob'), block), { createdAt: serverTimestamp() }));
  await assertFails(updateDoc(doc(db('alice'), `${chat}/calls/allowed`), { status: 'ringing', offer: { type: 'offer', sdp: 'offer' } }));
});
