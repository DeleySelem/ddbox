#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from flask import Flask, render_template, request, session, redirect, url_for, jsonify
from flask_socketio import SocketIO, join_room, emit
import os
import re
import time
import json
import secrets
import string
import base64
import threading
from collections import defaultdict
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.hashes import SHA256

MLKEM_1024_EK_LEN = 1568
MLKEM_1024_CT_LEN = 1568
MLKEM_1024_SS_LEN = 32

try:
    from fips203 import ML_KEM_1024, EncapsulationKey
    MLKEM_1024_EK_LEN = getattr(ML_KEM_1024, "EK_SIZE", 1568)
    MLKEM_1024_CT_LEN = getattr(ML_KEM_1024, "CT_SIZE", 1568)
    MLKEM_1024_SS_LEN = getattr(ML_KEM_1024, "SS_SIZE", 32)
except Exception as e:
    print(f"Warning: fips203 ML_KEM_1024 unavailable: {e}")
    ML_KEM_1024 = None
    EncapsulationKey = None

try:
    from cryptography.hazmat.primitives.asymmetric import mldsa
    MLDSA87_VK_LEN = 2592
except Exception as e:
    print(f"Warning: cryptography mldsa unavailable: {e}")
    mldsa = None
    MLDSA87_VK_LEN = 2592


def ml_kem_1024_encaps(ek_bytes: bytes) -> tuple[bytes, bytes]:
    if ML_KEM_1024 is None or EncapsulationKey is None:
        raise RuntimeError("Install `fips203` (`pip install fips203`) and `libfips203.so` for ML-KEM-1024.")
    ek_obj = EncapsulationKey(ek_bytes)
    ct, ss = ek_obj.encaps()
    return bytes(ct), bytes(ss)


def verify_ml_dsa_87(vk_bytes: bytes, payload_bytes: bytes, sig_bytes: bytes) -> bool:
    if mldsa is None:
        raise RuntimeError("Upgrade `cryptography` (`>=48`) for ML-DSA-87 verification.")
    try:
        pub = mldsa.MLDSA87PublicKey.from_public_bytes(vk_bytes)
        pub.verify(sig_bytes, payload_bytes)
        return True
    except Exception:
        return False


app = Flask(__name__)
app.config["SECRET_KEY"] = os.urandom(24)
app.config["SESSION_COOKIE_SECURE"] = True
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"

socketio = SocketIO(app, cors_allowed_origins='*', async_mode='threading')

rooms = {}
rate_limit = defaultdict(list)
RATE_LIMIT = 5

message_rate_limit = defaultdict(lambda: defaultdict(list))
MESSAGE_RATE_LIMIT = 10

TS_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")


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


def encrypt_key_for_kem_ek(key_bytes: bytes, ek_bytes: bytes) -> dict:
    if len(ek_bytes) != MLKEM_1024_EK_LEN:
        raise ValueError(f"Invalid ML-KEM-1024 ek length: {len(ek_bytes)} != {MLKEM_1024_EK_LEN}")
    ct, shared_secret = ml_kem_1024_encaps(ek_bytes)
    wrap_key = HKDF(
        algorithm=SHA256(),
        length=32,
        salt=None,
        info=b"ddbox-ml-kem-1024-group-key-wrap",
    ).derive(shared_secret)
    nonce = os.urandom(12)
    ciphertext = AESGCM(wrap_key).encrypt(nonce, key_bytes, None)
    return {
        "kem": "ML-KEM-1024",
        "ct": base64.b64encode(ct).decode(),
        "iv": base64.b64encode(nonce).decode(),
        "ciphertext": base64.b64encode(ciphertext).decode(),
    }


def rotate_group_key(room):
    if room not in rooms:
        return
    if rooms[room].get("offline_e2ee"):
        start_rekey_timer(room)
        return
    new_key = secrets.token_bytes(32)
    rooms[room]['group_key'] = new_key
    for name, info in rooms[room]['members'].items():
        try:
            encrypted = encrypt_key_for_kem_ek(new_key, info['ek'])
            emit('new_group_key', {'encrypted_key': encrypted, 'offline_e2ee': False}, to=info['sid'])
        except Exception as e:
            print(f"Failed to send new ML-KEM-1024 key to {name}: {e}")
    start_rekey_timer(room)


def start_rekey_timer(room):
    if room not in rooms:
        return
    if rooms[room].get('rekey_timer'):
        rooms[room]['rekey_timer'].cancel()
    timer = threading.Timer(300, rotate_group_key, args=[room])
    timer.daemon = True
    timer.start()
    rooms[room]['rekey_timer'] = timer


def broadcast_user_list(room):
    if room not in rooms:
        return
    members_list = [
        {
            'name': n,
            'public_key': base64.b64encode(info['ek']).decode(),
            'signing_key': base64.b64encode(info['vk']).decode(),
        }
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
        offline_e2ee = bool(request.form.get("offline_e2ee"))

        if not name or len(name) > 30:
            return render_template("home.html", error="Name required (max 30 chars)", code=code, name=name)
        if join != False and not code:
            return render_template("home.html", error="Room code required", code=code, name=name)
        if code and len(code) > 20:
            return render_template("home.html", error="Invalid room code", code=code, name=name)

        room = code
        if create != False:
            room = generate_unique_code()
            group_key = None if offline_e2ee else secrets.token_bytes(32)
            rooms[room] = {
                "members": {},
                "messages": [],
                "creator_name": name,
                "page_passphrase": generate_random_passphrase(),
                "group_key": group_key,
                "offline_e2ee": offline_e2ee,
                "rekey_timer": None,
                "next_message_id": 1,
            }
            mode_label = "OFFLINE-E2EE" if offline_e2ee else "ML-KEM-1024 + ML-DSA-87"
            print(f"\033[92mRoom {room} created by {name} ({mode_label})\033[0m")
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
    is_host = (rooms[room].get("creator_name") == name)
    offline_e2ee = bool(rooms[room].get("offline_e2ee"))
    html = render_template(
        "room.html",
        code=room,
        public_key="",
        name=name,
        is_host=is_host,
        offline_e2ee=offline_e2ee,
    )
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


@socketio.on("connect")
def connect(auth):
    room = session.get("room")
    name = session.get("name")
    if not room or not name:
        print(f"[connect rejected] missing session: room={room!r}, name={name!r}")
        return False
    if room not in rooms:
        print(f"[connect rejected] room {room!r} not in memory (server restarted?)")
        return False

    if not isinstance(auth, dict):
        print(f"[connect rejected] auth not dict for {name} in {room}")
        return False
    ek_b64 = auth.get("public_key")
    vk_b64 = auth.get("signing_key")
    if not ek_b64 or not vk_b64:
        print(f"[connect rejected] missing public_key or signing_key for {name} in {room}")
        return False

    try:
        ek_bytes = base64.b64decode(ek_b64)
        vk_bytes = base64.b64decode(vk_b64)
        if len(ek_bytes) != MLKEM_1024_EK_LEN or len(vk_bytes) != MLDSA87_VK_LEN:
            print(f"[connect rejected] bad key lengths for {name}: ek={len(ek_bytes)} (exp {MLKEM_1024_EK_LEN}), vk={len(vk_bytes)} (exp {MLDSA87_VK_LEN})")
            return False
    except Exception as e:
        print(f"[connect rejected] base64 decode error for {name}: {e}")
        return False

    sid = request.sid
    rooms[room]["members"][name] = {"sid": sid, "ek": ek_bytes, "vk": vk_bytes}
    join_room(room)

    for member_name, info in rooms[room]["members"].items():
        if member_name == name:
            continue
        emit('new_member', {
            'member_name': name,
            'public_key': ek_b64,
            'signing_key': vk_b64,
            'sid': sid
        }, to=info['sid'])

    broadcast_user_list(room)

    if rooms[room].get("offline_e2ee"):
        emit('group_key', {'offline_e2ee': True, 'encrypted_key': None}, to=sid)
    else:
        try:
            encrypted_key = encrypt_key_for_kem_ek(rooms[room]['group_key'], ek_bytes)
            emit('group_key', {'offline_e2ee': False, 'encrypted_key': encrypted_key}, to=sid)
        except Exception as e:
            print(f"[connect rejected] Failed to send ML-KEM-1024 group key to {name}: {e}")
            rooms[room]["members"].pop(name, None)
            return False

    if len(rooms[room]['members']) == 1:
        start_rekey_timer(room)


@socketio.on("request_history")
def request_history(data=None):
    room = session.get("room")
    name = session.get("name")
    if not room or not name or room not in rooms:
        return
    since_id = 0
    if isinstance(data, dict):
        try:
            since_id = int(data.get("since_id", 0) or 0)
        except (TypeError, ValueError):
            since_id = 0
    history = [m for m in rooms[room]["messages"] if m["id"] > since_id]
    emit('history', history, to=request.sid)


@socketio.on("message")
def message(data):
    room = session.get("room")
    name = session.get("name")
    if not room or not name or room not in rooms:
        return None
    if not isinstance(data, dict):
        return None

    ciphertext = data.get("ciphertext")
    sig_b64 = data.get("signature")
    raw_ts = data.get("timestamp")
    if not ciphertext or not sig_b64:
        return None
    if len(ciphertext) > 32768 or len(sig_b64) > 16384:
        return None
    if is_message_rate_limited(room, name):
        return None

    member_info = rooms[room]["members"].get(name)
    if not member_info:
        return None

    try:
        sig_bytes = base64.b64decode(sig_b64)
    except Exception:
        return None

    timestamp = raw_ts if isinstance(raw_ts, str) and TS_PATTERN.match(raw_ts) else time.strftime("%Y-%m-%d %H:%M:%S")
    canonical_payload = json.dumps(
        {"room": room, "sender": name, "timestamp": timestamp, "ciphertext": ciphertext},
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")

    if not verify_ml_dsa_87(member_info["vk"], canonical_payload, sig_bytes):
        print(f"Rejected invalid ML-DSA-87 signature from {name} in room {room}")
        return None

    msg_id = rooms[room]["next_message_id"]
    rooms[room]["next_message_id"] = msg_id + 1
    msg_obj = {
        "id": msg_id,
        "name": name,
        "ciphertext": ciphertext,
        "signature": sig_b64,
        "signing_key": base64.b64encode(member_info["vk"]).decode(),
        "timestamp": timestamp,
    }
    rooms[room]["messages"].append(msg_obj)

    for member_name, info in rooms[room]["members"].items():
        if info["sid"] == request.sid:
            continue
        emit('message', msg_obj, to=info['sid'])

    return msg_obj


@socketio.on("disconnect")
def disconnect(reason=None):
    room = session.get("room")
    name = session.get("name")
    sid = request.sid
    if not room or not name or room not in rooms:
        return

    member_info = rooms[room]["members"].get(name)
    if not member_info or member_info["sid"] != sid:
        return

    leave_room(room)
    del rooms[room]["members"][name]

    for member_name, info in rooms[room]["members"].items():
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


if __name__ == "__main__":
    print("\nStarting DDBOX server on http://0.0.0.0:5000 (ML-KEM-1024 + ML-DSA-87)")
    print("Async mode: threading (eventlet retired upstream)")
    print("For public access, use ngrok: `ngrok http 5000`")
    socketio.run(app, host='0.0.0.0', port=5000, debug=False, use_reloader=False)
