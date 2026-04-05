import os
from pathlib import Path
from flask import Flask, render_template, abort

app = Flask(__name__)

STORIES_DIR = Path(os.environ.get("STORIES_DIR", "/stories"))


def parse_story(path: Path) -> dict:
    text = path.read_text(encoding="utf-8").strip()
    lines = text.split("\n")
    title = lines[0].strip() if lines else path.stem.replace("-", " ").replace("_", " ").title()
    paragraphs = [ln.strip() for ln in lines[1:] if ln.strip()]
    word_count = sum(len(p.split()) for p in paragraphs)
    preview = paragraphs[0][:200].rsplit(" ", 1)[0] + "\u2026" if paragraphs else ""
    return {
        "slug": path.name,
        "title": title,
        "paragraphs": paragraphs,
        "word_count": word_count,
        "preview": preview,
    }


def get_stories() -> list[dict]:
    if not STORIES_DIR.exists():
        return []
    stories = []
    for p in sorted(STORIES_DIR.iterdir()):
        if p.is_file() and not p.name.startswith("."):
            stories.append(parse_story(p))
    return stories


@app.route("/")
def index():
    return render_template("index.html", stories=get_stories())


@app.route("/story/<slug>")
def story(slug):
    # Prevent path traversal
    if "/" in slug or "\\" in slug or slug.startswith("."):
        abort(400)
    path = STORIES_DIR / slug
    if not path.exists() or not path.is_file():
        abort(404)
    return render_template("story.html", story=parse_story(path))


@app.errorhandler(404)
def not_found(_e):
    return render_template("404.html"), 404


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False)
