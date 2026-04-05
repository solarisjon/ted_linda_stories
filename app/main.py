import os
import re
import secrets
from functools import wraps
from pathlib import Path

from flask import (
    Flask, render_template, abort,
    request, redirect, url_for, session,
)

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "dev-insecure-key-change-me")

STORIES_DIR   = Path(os.environ.get("STORIES_DIR", "/stories"))
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "")


# ── Helpers ────────────────────────────────────────────────────────

def parse_story(path: Path) -> dict:
    text  = path.read_text(encoding="utf-8").strip()
    lines = text.split("\n")
    title = lines[0].strip() if lines else path.stem.replace("-", " ").replace("_", " ").title()
    paragraphs = [ln.strip() for ln in lines[1:] if ln.strip()]
    word_count = sum(len(p.split()) for p in paragraphs)
    preview    = paragraphs[0][:200].rsplit(" ", 1)[0] + "\u2026" if paragraphs else ""
    return {
        "slug":       path.name,
        "title":      title,
        "paragraphs": paragraphs,
        "word_count": word_count,
        "preview":    preview,
    }


def get_stories() -> list[dict]:
    if not STORIES_DIR.exists():
        return []
    return [
        parse_story(p)
        for p in sorted(STORIES_DIR.iterdir())
        if p.is_file() and not p.name.startswith(".")
    ]


def title_to_slug(title: str) -> str:
    slug = title.lower().strip()
    slug = re.sub(r"[^\w\s-]", "", slug)
    slug = re.sub(r"[\s_]+", "_", slug)
    return slug.strip("_-") or "story"


def safe_slug(slug: str) -> bool:
    return bool(slug) and "/" not in slug and "\\" not in slug and not slug.startswith(".")


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("authenticated"):
            return redirect(url_for("admin_login", next=request.path))
        return f(*args, **kwargs)
    return decorated


# ── Public routes ──────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html", stories=get_stories())


@app.route("/story/<slug>")
def story(slug):
    if not safe_slug(slug):
        abort(400)
    path = STORIES_DIR / slug
    if not path.exists() or not path.is_file():
        abort(404)
    return render_template("story.html", story=parse_story(path))


# ── Admin routes ───────────────────────────────────────────────────

@app.route("/admin/login", methods=["GET", "POST"])
def admin_login():
    error = None
    if request.method == "POST":
        pw = request.form.get("password", "")
        if ADMIN_PASSWORD and secrets.compare_digest(pw, ADMIN_PASSWORD):
            session["authenticated"] = True
            return redirect(request.args.get("next") or url_for("admin_upload"))
        error = "Incorrect password."
    return render_template("admin_login.html", error=error)


@app.route("/admin/logout")
def admin_logout():
    session.clear()
    return redirect(url_for("index"))


@app.route("/admin/upload", methods=["GET", "POST"])
@login_required
def admin_upload():
    error = success = None

    if request.method == "POST":
        action = request.form.get("action", "upload")

        if action == "upload":
            title   = request.form.get("title", "").strip()
            content = request.form.get("content", "").strip()
            if not title:
                error = "A title is required."
            elif not content:
                error = "Story content cannot be empty."
            else:
                slug = title_to_slug(title)
                path = STORIES_DIR / slug
                if path.exists():
                    error = f'A story with that title already exists (file: {slug}).'
                else:
                    STORIES_DIR.mkdir(parents=True, exist_ok=True)
                    path.write_text(f"{title}\n{content}\n", encoding="utf-8")
                    success = f'"{title}" has been published!'

        elif action == "delete":
            slug = request.form.get("slug", "")
            if not safe_slug(slug):
                abort(400)
            path = STORIES_DIR / slug
            if path.exists() and path.is_file():
                path.unlink()
            return redirect(url_for("admin_upload"))

    return render_template(
        "admin_upload.html",
        stories=get_stories(),
        error=error,
        success=success,
    )


@app.route("/admin/edit/<slug>", methods=["GET", "POST"])
@login_required
def admin_edit(slug):
    if not safe_slug(slug):
        abort(400)
    path = STORIES_DIR / slug
    if not path.exists() or not path.is_file():
        abort(404)

    error = None

    if request.method == "POST":
        title   = request.form.get("title", "").strip()
        content = request.form.get("content", "").strip()
        if not title:
            error = "A title is required."
        elif not content:
            error = "Story content cannot be empty."
        else:
            new_slug = title_to_slug(title)
            new_path = STORIES_DIR / new_slug
            # If slug changed, make sure the new name isn't taken
            if new_slug != slug and new_path.exists():
                error = f'Another story already uses that title (file: {new_slug}).'
            else:
                new_path.write_text(f"{title}\n{content}\n", encoding="utf-8")
                if new_slug != slug:
                    path.unlink()
                return redirect(url_for("admin_upload"))

    # Read raw content (preserve original line structure for the textarea)
    raw = path.read_text(encoding="utf-8").strip().split("\n", 1)
    title   = raw[0].strip()
    content = raw[1].strip() if len(raw) > 1 else ""

    return render_template("admin_edit.html", slug=slug, title=title, content=content, error=error)


# ── Error handlers ─────────────────────────────────────────────────

@app.errorhandler(404)
def not_found(_e):
    return render_template("404.html"), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
