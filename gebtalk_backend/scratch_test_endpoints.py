import urllib.request
import json
import base64

API = "http://127.0.0.1:5000/api"

def test_upload():
    url = f"{API}/upload"
    boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
    payload = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="file"; filename="audit_test.pdf"\r\n'
        "Content-Type: application/pdf\r\n\r\n"
        "%PDF-1.4 GEBTALK AUDIT SAMPLE CONTENT\r\n"
        f"--{boundary}--\r\n"
    ).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        res = json.loads(resp.read().decode())
        print("Upload Result:", res)
        return res.get("url") or res.get("file_url")

def test_poll():
    url = f"{API}/notifications/poll?user_id=usr_test&last_msg_id=0"
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=5) as resp:
        res = json.loads(resp.read().decode())
        print("Poll Result (keys):", list(res.keys()))

if __name__ == "__main__":
    file_url = test_upload()
    test_poll()
