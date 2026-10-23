"""Publishes or updates the mod on mods.factorio.com.

Reads the API key from FACTORIO_API_KEY (process or Windows user environment). The key needs the
ModPortal scopes for uploading, publishing and editing mods.

Usage:
  python tools/publish.py publish        first release: creates the mod page with description and images
  python tools/publish.py upload         uploads dist/<name>_<version>.zip as a new release
  python tools/publish.py details        updates description, category, tags, license and source link
  python tools/publish.py images         uploads the gallery images and sets their order
"""
import json
import os
import sys
import urllib.parse
import urllib.request
import uuid

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
API = "https://mods.factorio.com/api/v2/mods/"
INFO = json.load(open(os.path.join(ROOT, "info.json"), encoding="utf-8"))
SOURCE = "https://github.com/vertexvaar/factorio-expandable-chests"
CATEGORY = "content"
LICENSE = "default_mit"
TAGS = ["storage", "logistics", "circuit-network"]
IMAGES = ["previews/portal/6-overview.png", "previews/portal/1-proxy-window.png", "previews/portal/4-requester-window.png"]


def api_key():
    key = os.environ.get("FACTORIO_API_KEY")
    if not key and os.name == "nt":
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
            key = winreg.QueryValueEx(k, "FACTORIO_API_KEY")[0]
    if not key:
        sys.exit("FACTORIO_API_KEY is not set")
    return key


def request(url, fields=None, files=None, auth=True):
    """POSTs form fields (lists become repeated fields) and files ({field: path}); returns the JSON answer."""
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, value in (fields or {}).items():
        for v in (value if isinstance(value, list) else [value]):
            body += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, name, v)).encode()
    for name, path in (files or {}).items():
        filename = os.path.basename(path)
        kind = "application/zip" if path.endswith(".zip") else "image/png"
        body += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
                 % (boundary, name, filename, kind)).encode()
        body += open(path, "rb").read() + b"\r\n"
    body += ("--%s--\r\n" % boundary).encode()
    headers = {"Content-Type": "multipart/form-data; boundary=" + boundary}
    if auth:
        headers["Authorization"] = "Bearer " + api_key()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=bytes(body), headers=headers)) as r:
            return json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        sys.exit("%s failed: %s %s" % (url.split("?")[0], e.code, e.read().decode(errors="replace")[:500]))


def zip_path():
    path = os.path.join(ROOT, "dist", "%s_%s.zip" % (INFO["name"], INFO["version"]))
    if not os.path.exists(path):
        sys.exit("build it first: python tools/package.py")
    return path


def description():
    return open(os.path.join(ROOT, "portal", "description.md"), encoding="utf-8").read()


def publish():
    upload_url = request(API + "init_publish", {"mod": INFO["name"]})["upload_url"]
    result = request(upload_url, {"description": description(), "category": CATEGORY, "license": LICENSE,
                                  "source_url": SOURCE}, {"file": zip_path()}, auth=False)
    print("published:", result.get("url", result))


def upload():
    upload_url = request(API + "releases/init_upload", {"mod": INFO["name"]})["upload_url"]
    print("uploaded:", request(upload_url, files={"file": zip_path()}, auth=False))


def details():
    result = request(API + "edit_details", {"mod": INFO["name"], "description": description(), "category": CATEGORY,
                                            "license": LICENSE, "source_url": SOURCE, "tags": TAGS})
    print("details:", result.get("success", result))


def images():
    ids = []
    for image in IMAGES:
        upload_url = request(API + "images/add", {"mod": INFO["name"]})["upload_url"]
        ids.append(request(upload_url, files={"image": os.path.join(ROOT, image)}, auth=False)["id"])
    print("images:", request(API + "images/edit", {"mod": INFO["name"], "images": ",".join(ids)}).get("success"))


if __name__ == "__main__":
    actions = {"publish": [publish, details, images], "upload": [upload], "details": [details], "images": [images]}
    if len(sys.argv) != 2 or sys.argv[1] not in actions:
        sys.exit(__doc__)
    for action in actions[sys.argv[1]]:
        action()
