"""Generate self-contained web pages from the same policy bundled in Flutter.

Run: python tool/generate_privacy_policy.py [--check]
No network calls, third-party dependencies, or publication actions.
"""
import argparse
import base64
import html
import json
from pathlib import Path
from urllib.parse import quote, urlencode

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "docs" / "privacy"
POLICY = ROOT / "assets" / "privacy" / "privacy_policy.json"

CSS = """
:root{color-scheme:light;font-family:system-ui,-apple-system,Segoe UI,sans-serif;
color:#374151;background:#f4faf9;line-height:1.7}
*{box-sizing:border-box}body{margin:0}main{max-width:820px;margin:32px auto;
padding:32px;background:white;border-radius:20px;box-shadow:0 8px 32px #0f766e12}
header{border-bottom:1px solid #d5e9e5;padding-bottom:24px;margin-bottom:24px}
.brand{display:flex;align-items:center;gap:16px}.brand img{width:72px;height:72px;
object-fit:contain}h1,h2{color:#0f766e;line-height:1.3}h1{margin:0;font-size:2rem}
h2{font-size:1.3rem;margin-top:32px}
a{color:#0f766e;overflow-wrap:anywhere}a:focus-visible{outline:3px solid #0d9488;
outline-offset:4px}nav{display:flex;flex-wrap:wrap;gap:16px;margin-top:20px}
.button{display:inline-block;padding:12px 20px;border-radius:12px;
background:#0f766e;color:white;text-decoration:none;font-weight:600}
footer{margin-top:32px;border-top:1px solid #d5e9e5;padding-top:20px}
@media(max-width:600px){main{margin:0;padding:24px 20px;border-radius:0}
h1{font-size:1.6rem}.brand img{width:56px;height:56px}}
"""


def esc(value):
    return html.escape(value, quote=True)


def paragraphs(section):
    return "\n".join(f"<p>{esc(p)}</p>" for p in section["paragraphs"])


def page(policy, title, body, logo):
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="{esc(title)} for Bantay Ulang.">
<title>{esc(policy['appName'])} — {esc(title)}</title><style>{CSS}</style></head>
<body><main><header><div class="brand"><img src="data:image/png;base64,{logo}"
alt="Bantay Ulang logo"><div><h1>{esc(title)}</h1><p>{esc(policy['appName'])}</p>
</div></div>
<nav aria-label="Privacy navigation"><a href="index.html">Privacy Policy</a>
<a href="account-deletion.html">Request account deletion</a></nav></header>
{body}<footer><p>{esc(policy['publisher'])}<br>
<a href="mailto:{esc(policy['contactEmail'])}">{esc(policy['contactEmail'])}</a>
</p></footer></main></body></html>
"""


def render():
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    logo = base64.b64encode((ROOT / "assets/img/logo_BU.png").read_bytes()).decode()
    sections = "\n".join(
        f'<section id="{esc(s["id"])}"><h2>{esc(s["title"])}</h2>'
        f'{paragraphs(s)}</section>' for s in policy["sections"]
    )
    updated = f"<p>Last updated: {esc(policy['lastUpdated'])}</p>"
    full_policy = page(policy, "Privacy Policy", updated + "\n" + sections, logo)
    mailto = "mailto:" + policy["contactEmail"] + "?" + urlencode({
        "subject": "Bantay Ulang account deletion",
        "body": "I request deletion of my Bantay Ulang account and associated "
                "personal data.\nRegistered account email: \n",
    }, quote_via=quote)
    retention = next(s for s in policy["sections"] if s["id"] == "retention-deletion")
    body = f"""<h2>Send an account and data deletion request</h2>
<p>Email <a href="mailto:{esc(policy['contactEmail'])}">
{esc(policy['contactEmail'])}</a> with the subject “Bantay Ulang account deletion”.
Identify your registered account email and send from that address where possible.
Do not send your password.</p>
<p><a class="button" href="{esc(mailto)}">Compose deletion request</a></p>
<p>This button opens your email application; it does not send a message or delete
an account. If no email application opens, send your request manually to the
address above. You do not need to sign in to read this page.</p>
<h2>Deletion and retention information</h2>{paragraphs(retention)}
"""
    return {"index.html": full_policy,
            "account-deletion.html": page(policy, "Account Deletion Request", body, logo)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if web pages are stale")
    options = parser.parse_args()
    pages = render()
    if options.check:
        stale = [name for name, content in pages.items()
                 if not (OUTPUT / name).is_file() or
                 (OUTPUT / name).read_text(encoding="utf-8") != content]
        if stale:
            raise SystemExit("Regenerate privacy pages: " + ", ".join(stale))
        print("Web pages match the bundled policy.")
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for name, content in pages.items():
            (OUTPUT / name).write_text(content, encoding="utf-8")
        print("Generated privacy and deletion-request HTML pages.")


if __name__ == "__main__":
    main()
