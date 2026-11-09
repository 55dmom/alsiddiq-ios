#!/usr/bin/env python3
"""Server-side checks for the CI live run (bash 3.2 on macOS mangles nested JSON quoting, so this is Python)."""
import json, os, sys, urllib.request, urllib.error
SU, K = os.environ["SU"], os.environ["K"]
AP, VP, TP, TP2, CID = (os.environ[k] for k in ("AP", "VP", "TP", "TP2", "CID"))

def req(method, path, body=None, token=None, headers=None):
    h = {"apikey": K, "Authorization": "Bearer " + (token or K), "Content-Type": "application/json"}
    h.update(headers or {})
    data = None if body is None else (body if isinstance(body, bytes) else json.dumps(body).encode())
    r = urllib.request.Request(SU + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(r, timeout=40) as x: raw = x.read(); code = x.status
    except urllib.error.HTTPError as e: raw = e.read(); code = e.code
    try: return code, json.loads(raw or b"null")
    except Exception: return code, raw.decode(errors="replace")[:300]

def access(body, token=None): return req("POST", "/functions/v1/access", body, token)
def login(kind, pw):
    c, d = access({"action": "login", "kind": kind, "password": pw})
    return c, d

if sys.argv[1] == "before":
    c, d = login("teacher", TP)
    print(d["session"]["refresh_token"] if c == 200 else "")
    sys.exit(0)

old_rt = sys.stdin.read().strip()
print("== server checks (after the admin changed the teachers' password in the app)")
print("setup again (must be refused):", access({"action": "setup", "admin_password": TP2 + "x", "viewer_password": TP2 + "y"})[0])
print("old teachers password:", login("teacher", TP)[0])
c, d = login("teacher", TP2); print("new teachers password:", c, (d.get("profile") or {}).get("access_kind") if isinstance(d, dict) else d)
c, _ = req("POST", "/auth/v1/token?grant_type=refresh_token", {"refresh_token": old_rt}); print("old teachers session refresh:", c)
print("viewer password in the admin box:", login("admin", VP)[0])
print("teachers password in the admin box:", login("admin", TP2)[0])
print("admin password in the teachers box:", login("teacher", AP)[0])
c, d = login("admin", AP); at = d["session"]["access_token"] if c == 200 else None
print("admin login:", c)
print("== what the server holds (read as the admin)")
for t, sel in [("recitations", "student_id,notes,teacher_id,by_name"), ("attendance", "student_id,day,status,by_name"),
               ("students", "full_name,notes,circle_id,photo_path"), ("teacher_names", "name"),
               ("announcements", "title,by_name"), ("circles", "name,schedule,teacher_name")]:
    c, d = req("GET", f"/rest/v1/{t}?select={sel}", token=at)
    print(t, c, json.dumps(d, ensure_ascii=False)[:1500])
# remove the throwaway photo files through the storage API (the rows are wiped by the maintainer)
c, d = req("POST", "/storage/v1/object/list/student-photos", {"prefix": CID + "/", "limit": 1000}, token=at)
names = []
for folder in (d if isinstance(d, list) else []):
    c2, d2 = req("POST", "/storage/v1/object/list/student-photos", {"prefix": f"{CID}/{folder['name']}/", "limit": 1000}, token=at)
    names += [f"{CID}/{folder['name']}/{o['name']}" for o in (d2 if isinstance(d2, list) else [])]
print("photo files found:", len(names))
if names:
    c, d = req("DELETE", "/storage/v1/object/student-photos", {"prefixes": names}, token=at)
    print("photo files removed:", c, len(d) if isinstance(d, list) else d)
