#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from flask import Flask, render_template, request, session, redirect, url_for, jsonify
from flask_socketio import SocketIO, join_room, leave_room, emit
import os
import time
import secrets
import string
import hashlib
import base64
import threading
from collections import defaultdict
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.hashes import SHA256

app = Flask(__name__)
app.config["SECRET_KEY"] = os.urandom(24)
app.config["SESSION_COOKIE_SECURE"] = True          # HTTPS only (ngrok provides HTTPS)         app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
socketio = SocketIO(app, cors_allowed_origins='*')

rooms = {}
rate_limit = defaultdict(list)
RATE_LIMIT = 5  # initial POST rate limit

# Message rate limiting: per (room, name) store list of timestamps
message_rate_limit = defaultdict(lambda: defaultdict(list))
MESSAGE_RATE_LIMIT = 10  # messages per minute

def is_rate_limited(ip):
    now = time.time()
    cutoff = now - 60
    rate_limit[ip] = [t for t in rate_limit[ip] if t > cutoff]
    if len(rate_limit[ip]) >= RATE_LIMIT:
        return True
    rate_limit[ip].append(now)
    return False

def is_message_rate_limited(room, name):
    now = time.time()
    cutoff = now - 60
    timestamps = message_rate_limit[room][name]
    timestamps[:] = [t for t in timestamps if t > cutoff]
    if len(timestamps) >= MESSAGE_RATE_LIMIT:
        return True
    timestamps.append(now)
    return False

def generate_unique_code(length=8):
    alphabet = string.ascii_uppercase + string.digits
    while True:
        code = ''.join(secrets.choice(alphabet) for _ in range(length))
        if code not in rooms:
            return code

def generate_random_passphrase(length=32):
    return secrets.token_hex(length)

def derive_key(passphrase, salt, iterations=100000):
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=iterations,
    )
    return kdf.derive(passphrase.encode())

def encrypt_text_aes(text, passphrase):
    salt = os.urandom(16)
    key = derive_key(passphrase, salt)
    aesgcm = AESGCM(key)
    nonce = os.urandom(12)
    ct = aesgcm.encrypt(nonce, text.encode(), None)
    return {
        'salt': base64.b64encode(salt).decode(),
        'nonce': base64.b64encode(nonce).decode(),
        'ciphertext': base64.b64encode(ct).decode()
    }

def decrypt_text_aes(enc_dict, passphrase):
    salt = base64.b64decode(enc_dict['salt'])
    nonce = base64.b64decode(enc_dict['nonce'])
    ct = base64.b64decode(enc_dict['ciphertext'])
    key = derive_key(passphrase, salt)
    aesgcm = AESGCM(key)
    return aesgcm.decrypt(nonce, ct, None).decode()

def encrypt_key_for_public_key(key_bytes, public_key_raw):
    """Encrypt key_bytes using ECDH with ephemeral key, given raw uncompressed public key."""
    peer_public = ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), public_key_raw)
    ephemeral_private = ec.generate_private_key(ec.SECP256R1())
    ephemeral_public = ephemeral_private.public_key()
    shared = ephemeral_private.exchange(ec.ECDH(), peer_public)
    hkdf = HKDF(algorithm=SHA256(), length=32, salt=None, info=b'group-key-encryption')
    aes_key = hkdf.derive(shared)
    nonce = os.urandom(12)
    ciphertext = AESGCM(aes_key).encrypt(nonce, key_bytes, None)
    ephemeral_der = ephemeral_public.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )
    return {
        'ephemeral_pub': base64.b64encode(ephemeral_der).decode(),
        'iv': base64.b64encode(nonce).decode(),
        'ciphertext': base64.b64encode(ciphertext).decode()
    }

def rotate_group_key(room):
    if room not in rooms:
        return
    new_key = secrets.token_bytes(32)
    rooms[room]['group_key'] = new_key
    for name, info in rooms[room]['members'].items():
        try:
            encrypted = encrypt_key_for_public_key(new_key, info['public_key'])
            emit('new_group_key', {'encrypted_key': encrypted}, to=info['sid'])
        except Exception as e:
            print(f"Failed to send new key to {name}: {e}")
    start_rekey_timer(room)

def start_rekey_timer(room):
    if room not in rooms:
        return
    if rooms[room].get('rekey_timer'):
        rooms[room]['rekey_timer'].cancel()
    timer = threading.Timer(300, rotate_group_key, args=[room])  # 5 minutes
    timer.daemon = True
    timer.start()
    rooms[room]['rekey_timer'] = timer

def broadcast_user_list(room):
    """Helper to emit updated user list and count to all in room."""
    if room not in rooms:
        return
    members_list = [
        {'name': n, 'public_key': base64.b64encode(info['public_key']).decode()}
        for n, info in rooms[room]['members'].items()
    ]
    emit('update_user_list', members_list, room=room)
    emit('update_member_count', len(rooms[room]['members']), room=room)

@app.route("/", methods=["POST", "GET"])
def home():
    if request.method == "POST":
        ip = request.remote_addr
        if is_rate_limited(ip):
            return render_template("home.html", error="Too many requests, try later.", code="", name="")

        token = session.get('csrf_token')
        if not token or token != request.form.get('csrf_token'):
            return render_template("home.html", error="Invalid CSRF token", code="", name="")

        name = request.form.get("name", "").strip()
        code = request.form.get("code", "").strip()
        join = request.form.get("join", False)
        create = request.form.get("create", False)

        if not name or len(name) > 30:
            return render_template("home.html", error="Name required (max 30 chars)", code=code, name=name)
        if join != False and not code:
            return render_template("home.html", error="Room code required", code=code, name=name)
        if code and len(code) > 20:
            return render_template("home.html", error="Invalid room code", code=code, name=name)

        room = code
        if create != False:
            room = generate_unique_code()
            group_key = secrets.token_bytes(32)
            rooms[room] = {
                "members": {},
                "messages": [],
                "creator_name": name,
                "page_passphrase": generate_random_passphrase(),
                "group_key": group_key,
                "rekey_timer": None
            }
            print(f"\033[92mRoom {room} created by {name}\033[0m")
        elif code not in rooms:
            return render_template("home.html", error="Room does not exist.", code=code, name=name)

        session["room"] = room
        session["name"] = name
        return redirect(url_for("boot"))

    if 'csrf_token' not in session:
        session['csrf_token'] = secrets.token_hex(16)
    return render_template("home.html", csrf_token=session['csrf_token'])

@app.route("/boot")
def boot():
    if not session.get("room") or not session.get("name"):
        return redirect(url_for("home"))
    return render_template("boot.html")

@app.route("/get_encrypted_page")
def get_encrypted_page():
    room = session.get("room")
    name = session.get("name")
    if not room or not name or room not in rooms:
        return jsonify({"error": "Not authenticated"}), 401

    passphrase = rooms[room]["page_passphrase"]
    html = render_template("room.html", code=room, public_key="", name=name)
    encrypted = encrypt_text_aes(html, passphrase)
    return jsonify({
        "encrypted": encrypted,
        "passphrase": passphrase
    })

@app.route("/room")
def room():
    room = session.get("room")
    if room and room in rooms:
        return redirect(url_for("boot"))
    return redirect(url_for("home"))

@app.route("/logs/<room>")
def get_logs(room):
    if session.get("room") != room or session.get("name") not in rooms.get(room, {}).get("members", {}):
        return jsonify({"error": "Unauthorized"}), 403
    return jsonify({"messages": rooms[room]["messages"]})

# ----------------- Socket.IO Events -----------------

@socketio.on("connect")
def connect(auth):
    room = session.get("room")
    name = session.get("name")
    if not room or not name or room not in rooms:
        return False

    public_key_b64 = auth.get("public_key")
    if not public_key_b64:
        return False
    try:
        public_key_raw = base64.b64decode(public_key_b64)
        if len(public_key_raw) != 65 or public_key_raw[0] != 0x04:
            return False
    except:
        return False

    sid = request.sid
    rooms[room]["members"][name] = {"sid": sid, "public_key": public_key_raw}
    join_room(room)

    # Notify existing members about the new member
    for member_name, info in rooms[room]["members"].items():
        if member_name == name:
            continue
        emit('new_member', {
            'member_name': name,
            'public_key': public_key_b64,
            'sid': sid
        }, to=info['sid'])

    # Broadcast updated user list
    broadcast_user_list(room)

    # Send the current group key to the new member
    try:
        encrypted_key = encrypt_key_for_public_key(rooms[room]['group_key'], public_key_raw)
        emit('group_key', {'encrypted_key': encrypted_key}, to=sid)
    except Exception as e:
        print(f"Failed to send group key to {name}: {e}")
        return False

    if len(rooms[room]['members']) == 1:
        start_rekey_timer(room)

@socketio.on("request_history")
def request_history():
    room = session.get("room")
    name = session.get("name")
    if not room or not name or room not in rooms:
        return
    history = rooms[room]["messages"]
    emit('history', history, to=request.sid)

@socketio.on("message")
def message(data):
    room = session.get("room")
    name = session.get("name")
    if not room or not name or room not in rooms:
        return
    ciphertext = data.get("ciphertext")
    if not ciphertext:
        return
    if len(ciphertext) > 10000:
        return
    if is_message_rate_limited(room, name):
        return

    rooms[room]["messages"].append({
        "name": name,
        "ciphertext": ciphertext,
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
    })
    for member_name, info in rooms[room]["members"].items():
        if member_name == name:
            continue
        emit('message', {
            "name": name,
            "ciphertext": ciphertext,
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
        }, to=info['sid'])

@socketio.on("disconnect")
def disconnect(reason):
    room = session.get("room")
    name = session.get("name")
    if not room or not name or room not in rooms:
        return
    leave_room(room)
    if name in rooms[room]["members"]:
        del rooms[room]["members"][name]
    for member_name, info in rooms[room]["members"].items():
        if member_name == name:
            continue
        emit('system_message', {
            "message": f"{name} has left the room",
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
        }, to=info['sid'])
    broadcast_user_list(room)

    if len(rooms[room]['members']) == 0:
        if rooms[room].get('rekey_timer'):
            rooms[room]['rekey_timer'].cancel()
            rooms[room]['rekey_timer'] = None

@socketio.on_error_default
def error_handler(e):
    print(f"WebSocket Error: {str(e)}")

# ----------------- Run Server -----------------
if __name__ == "__main__":
    print("\nStarting DDBOX server on http://0.0.0.0:5000")
    print("For public access, use ngrok: `ngrok http 5000`")
    socketio.run(app, host='0.0.0.0', port=5000, debug=False, use_reloader=False)