#!/usr/bin/env python3
"""App-Store-Connect-API: ES256-Token lokal signieren, GET/POST ausführen.

Kein pyjwt/cryptography auf dieser Maschine — die Signatur macht `openssl`
über einen Unterprozess. Der private Schlüssel bleibt auf der Platte.
"""
import base64, json, subprocess, sys, time, urllib.request, os

KEY_ID = "D5BM7BM3H5"
ISSUER = "69a6de6f-1f1c-47e3-e053-5b8c7c11a4d1"
KEY_PATH = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")

def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

def der_to_raw(der: bytes) -> bytes:
    """ECDSA-Signatur: openssl liefert DER, JWS will r||s zu je 32 Byte."""
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 3
    out = b""
    for _ in range(2):
        assert der[i] == 0x02
        length = der[i + 1]
        val = der[i + 2 : i + 2 + length].lstrip(b"\x00")
        out += val.rjust(32, b"\x00")
        i += 2 + length
    return out

def token() -> str:
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    payload = {"iss": ISSUER, "iat": int(time.time()),
               "exp": int(time.time()) + 900, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64(json.dumps(header).encode())}.{b64(json.dumps(payload).encode())}"
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY_PATH],
                         input=signing_input.encode(), capture_output=True,
                         check=True).stdout
    return f"{signing_input}.{b64(der_to_raw(der))}"

def call(method: str, path: str, body=None):
    url = path if path.startswith("http") else "https://api.appstoreconnect.apple.com" + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")

if __name__ == "__main__":
    method = sys.argv[1]
    path = sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    status, payload = call(method, path, body)
    print(status)
    print(json.dumps(payload, indent=2, ensure_ascii=False))
