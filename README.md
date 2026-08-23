# ddbox

DDBox is a web‑based encrypted chat application designed for dead‑drop style communication, where sensitive messages are exchanged in real time with an emphasis on confidentiality and ephemerality. The name evokes spycraft – a place to leave encrypted drops for trusted recipients.

SETUP

1. Download the repo:

```bash
git clone https://github.com/deleyselem/ddbox
```

2. Navigate to the ./ddbox folder and run this
in the terminal


```bash
#!/bin/bash
echo "-------===[ DDBOX ]===-------"
echo "《《《☆ SETUP+INSTALL ☆》》》"
by: D373Y 5373M

echo "IMPORTANT INFORMATION - READ!"

echo "End-to-end encrypted group messaging."
echo "Read README.md for full protocol listing"
echo "and detailed info about the weaknesses,"
echo "you must understand and evaluate your"
echo "level of curiosity for government hackers."
echo "For example if you sell drugs with your"
echo "friends, not a high alert, but selling"
echo "weapons of mass destruction or child"
echo "porn, you might want to concider another"
echo "safer messaging system."
sleep 10
echo 
echo "Understanding the programs encryption"
echo "level gives you not a false confidence"
echo "like for example Signal app which says"
echo "it is secure, but is actually controlled" echo "by government agencie, like Anom app was"
echo "an FBI bate with which they busted 50 kg"
echo "of marihuana before it got to Finland"
echo "I heard all the phone calls..."
echo
sleep 10
echo "So what can you do to not get caught"
echo "by feds?"
echo
echo "Always read the code, understand the"
echo "level of security, and estimate your"
echo "value to be hacked. Never install apps"
echo "with code you do not understand how it"
echo "works. If something is unclear, it is"
echo "most prominently obfuscated for a reason."
echo "This program is I2P inspired, but I have"
echo "zero trust for I2P hidden internet project"
echo "and I am sure the whole protocol is for" echo "catching pedophiles online. Since even"
echo "AIs give you boobytrapped code if you"
echo "ask it to do truly anonymous chat or"
echo "market place. So read the code, or search"
echo "for "gov", "@fbi" to see if it sends mail"
echo "to FBI when run. Do not run such codes"
echo "if you wish not for FBIs surveillance"
echo "upon your ass."
echo
sleep 10
echo "Firing it up!"
echo
echo "Creating folder and"
echo -n "copying files:" | echo -n "."
mkdir templates | echo -n "."
cp base.html ./templates/base.html | echo -n "."
cp boot.html ./templates/boot.html | echo -n "."
cp home.html ./templates/home.html | echo -n "."
cp room.html ./templates/room.html | echo -n "."
echo -n "OK"
echo
echo
echo-n "Removing files:"
echo -n "t" | echo -n "."
rm base.html | echo -n "."
rm boot.html | echo -n "."
rm home.html | echo -n "."
rm room.html | echo -n "...OK"
```

# Encryption breakdown

DDBox – Secure Deaddrop Chat

DDBox is a web‑based encrypted chat application designed for dead‑drop style communication, where sensitive messages are exchanged in real time with an emphasis on confidentiality and ephemerality. The name evokes spycraft – a place to leave encrypted drops for trusted recipients.


Overview

DDBox provides:

· End‑to‑end encrypted group messaging – all messages are encrypted with a shared AES‑256‑GCM key before leaving the client.
· Private room creation – each room has a unique, unpredictable 8‑character alphanumeric code.
· Encrypted page delivery – the chat interface itself is delivered as an encrypted HTML blob, decrypted client‑side with a per‑room passphrase.
· Automatic group key rotation – the group key is refreshed every 5 minutes, limiting the lifetime of any single key.
· User presence and fingerprints – a user list shows public key fingerprints for out‑of‑band verification.

The server acts as a message relay and key distributor, but does not store plaintext messages. However, the server does hold the group key in memory, which is the central trust assumption.


Protocol & Architecture

1. Components

· Backend – Flask + Flask‑SocketIO (Python)
· Frontend – Vanilla JavaScript, Web Crypto API
· Transport – HTTPS (enforced) + WebSocket (Socket.IO) with cors_allowed_origins='*'
· Cryptographic primitives (client & server):
  · AES‑GCM (256‑bit)
  · ECDH (P‑256 curve)
  · PBKDF2 (100 000 iterations) for page passphrase derivation
  · HKDF (SHA‑256) for key derivation from ECDH shared secrets


2. Room Creation & Joining

Room Creation

1. Client submits a name (max 30 chars) with CSRF token.
2. Server generates a unique room code (8 alphanumeric) and a group key (32 random bytes) and a page passphrase (32 hex chars).
3. Room is stored in memory: {members: {}, messages: [], group_key, page_passphrase, rekey_timer}.
4. Client is redirected to /boot with session storing room and name.


Room Joining

1. Client submits name and room code; server verifies room exists.
2. Session stores room and name.
3. Client is redirected to /boot.


3. Encrypted Page Delivery

· Upon loading /boot, the client fetches /get_encrypted_page which returns:
  · encrypted: {salt, nonce, ciphertext} (AES‑GCM encrypted HTML)
  · passphrase: the plaintext page passphrase
· Client uses PBKDF2 to derive the AES key from the passphrase and salt, decrypts the HTML, and writes it into the document, effectively replacing the boot page with the live chat room.

This double‑encryption ensures that the chat HTML (which contains JavaScript and logic) is not served in plaintext over the wire, even though it ultimately runs in the browser.


4. Real‑time Connection & Key Exchange

1. The room HTML immediately generates an ECDH P‑256 key pair (private/public).
2. It connects to Socket.IO and sends the public key (base64) in the auth field.
3. Server stores the public key along with the client’s session ID.
4. Server sends the current group key to the new client, encrypted specifically for that client’s public key:
   · Server generates an ephemeral ECDH key pair.
   · Computes the shared secret with the client’s public key.
   · Derives an AES key via HKDF.
   · Encrypts the group key with AES‑GCM.
   · Sends {ephemeral_pub, iv, ciphertext} over the WebSocket.
5. Client decrypts with its private key and stores the group key for message encryption/decryption.
6. The server broadcasts the updated user list to all members.


5. Messaging

· A user types a message.
· Client encrypts the plaintext with AES‑GCM using the group key and a random 12‑byte nonce.
· The ciphertext (including the nonce prepended) is base64‑encoded and sent via message event.
· Server prepends the sender’s name (from session) and a timestamp, stores the object {name, ciphertext, timestamp} in the room’s message history.
· Server broadcasts the same object to all other members (not to the sender).
· Each recipient decrypts the ciphertext with the group key and displays the message.


6. Message History

· On connect, after receiving the group key, the client emits request_history.
· Server responds with the entire stored message list (ciphertexts + metadata).
· Client decrypts each in order and renders them.


7. Group Key Rotation

· A background timer (5 minutes) triggers rotate_group_key for each room.
· A new random 32‑byte key is generated.
· The new key is encrypted individually for each member’s public key (same procedure as initial delivery) and sent via new_group_key event.
· Clients update their local group key and display a system notification.
· The rotation timer is reset after each rotation.


8. Disconnect & Cleanup

· On client disconnect, the member is removed from the room.
· A system message is broadcast to remaining members.
· The user list and member count are updated.
· If the room becomes empty, the rekey timer is cancelled (room remains, but no messages are stored persistently).


9. Additional Endpoints

· /logs/<room> – returns the full message history (plain JSON) for the authenticated user; used in the “Logs” popup.


Security Model

Trust assumptions:

· Server is trusted to:
  · Generate and distribute the group key correctly.
  · Relay messages faithfully.
  · Not log plaintext (though it could).
· Clients are trusted to not leak their private keys or the group key.
· Transport layer (HTTPS) protects data in transit against passive eavesdroppers.


What is protected:

· Message confidentiality – only group members holding the key can decrypt messages.
· Message integrity & authenticity – AES‑GCM prevents tampering; however, any group member can forge messages (since the key is shared).
· Page confidentiality – the chat interface is not served in plaintext; only the client with the passphrase can render it.


What is NOT protected:

· Forward secrecy – if a group key is compromised (e.g., server memory dump), all past messages encrypted with that key become readable. Rekeying does not protect old messages.
· Identity authentication – no proof of identity; anyone can join a room with any name. Impersonation is trivial.
· Server compromise – an attacker with access to the server’s memory can obtain the group key and decrypt all messages (both past and future). The server could also modify the code to log plaintext.
· Message non‑repudiation – messages are not signed; the server only stores the sender’s name as provided by the client.


Weaknesses & Attack Vectors

1. Server Has the Group Key

The server generates, stores, and redistributes the group key. A malicious or compromised server can:

· Decrypt all messages in real time.
· Log all plaintexts.
· Impersonate any user by sending messages with arbitrary names.

Mitigation – design a protocol where the group key is generated by a client and distributed without the server ever learning it (e.g., using a key‑exchange protocol like MLS). This would require more complex logic but eliminate the server’s ability to read content.

2. No Forward Secrecy

Even if the server is trusted today, a future compromise (or database leak) could expose old messages because the same group key is used for extended periods (up to 5 minutes). Each rotation only protects future messages.

Mitigation – use a ratcheting mechanism (e.g., Double Ratchet) that derives new keys for each message, ensuring that compromise of a current key does not reveal past messages.

3. No User Authentication / Spoofing

The server trusts the name stored in the session. An attacker can join a room with another user’s name (if that user is offline) and impersonate them. Even when online, there is no cryptographic binding between the name and the public key – the server does not verify that the public key belongs to the claimed identity.

Mitigation – require cryptographic signatures or use a public‑key infrastructure where each user proves ownership of their private key.

4. Lack of Message Signatures

All messages are encrypted with the same group key. Any member can encrypt a message and claim any sender name. There is no way for recipients to verify the actual origin.

Mitigation – sign each message with the sender’s private key. Recipients can verify the signature using the sender’s public key (which must be authenticated).

5. Public Key Fingerprints Without Verification

The user list shows SHA‑256 fingerprints of public keys, but there is no mechanism to compare them out‑of‑band. An active MITM (or a malicious server) could present different public keys to different clients, leading to undetected interception.

Mitigation – implement a secure out‑of‑band verification process (e.g., QR codes or short authentication strings).

6. Page Encryption – Passphrase Sent in Cleartext Over HTTPS

While HTTPS protects the passphrase in transit, the server itself knows the passphrase (since it generated it). If the server is compromised, the passphrase can be obtained, and the page HTML can be decrypted. This is a minor issue because the page content is static and not sensitive.

7. In‑Memory Storage of Messages

All messages are stored in memory. A server restart loses history, but more importantly, a memory dump can reveal all ciphertexts. Since the group key is also in memory, an attacker with memory access can decrypt everything.

Mitigation – avoid storing messages at all (or store only encrypted blobs that are not decryptable by the server). However, the server is already trusted, so this is partly moot.

8. Rate Limiting Weaknesses

· IP‑based rate limiting for room creation/joining is trivial to bypass with IP spoofing or multiple devices.
· Message rate limiting is per (room, name), but since names are not authenticated, an attacker can change names to evade limits.

9. Session Security

· Sessions are stored in Flask’s signed cookies (not encrypted). If the secret key is leaked, sessions can be forged.
· SESSION_COOKIE_SECURE and HTTPONLY are set, but SAMESITE is Lax, which offers limited CSRF protection (though CSRF is not a major threat here).

10. WebSocket (Socket.IO) Security

· cors_allowed_origins='*' allows any site to connect, potentially leading to cross‑site WebSocket hijacking if session cookies are sent. However, the authentication is based on session cookie and public key handshake, so an attacker would need the victim’s session cookie.

11. Logs Endpoint

/logs/<room> checks only session and membership, not the actual public key. If a session is hijacked, the attacker can view the entire history.

12. XSS Potential

The boot page uses document.write(plainHtml) after decryption. If the server’s encryption were somehow bypassed or the page HTML contained malicious scripts, it could lead to XSS. However, the server controls the HTML, so this is a server trust issue.


Summary

DDBox is a functional, well‑structured encrypted chat with a focus on ephemeral communication and a neat double‑encrypted page delivery. Its cryptographic choices (AES‑GCM, ECDH) are solid, and the implementation correctly uses Web Crypto APIs. However, its security hinges entirely on trusting the server – a design choice that makes it vulnerable to insider threats, server compromise, and impersonation. For a spy‑themed dead‑drop tool, this may be acceptable if the server is operated in a trusted environment and used with out‑of‑band verification, but it falls short of modern end‑to‑end encrypted messaging standards (like Signal or Matrix) that offer forward secrecy and strong identity verification.

The weaknesses listed are not fatal for a learning project or a low‑risk internal tool, but they should be understood before deploying in any sensitive context.