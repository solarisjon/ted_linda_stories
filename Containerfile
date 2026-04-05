FROM python:3.12-slim

LABEL maintainer="ted-linda-stories"
LABEL description="Ted & Linda's family story collection"

# Create non-root user
RUN useradd -r -u 1001 -m appuser

WORKDIR /app

# Install dependencies first (layer cache)
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ .

# Stories are expected to be mounted at /stories
# (baked in at build time via COPY, volume mount overrides on update)
RUN mkdir -p /stories
COPY stories/ /stories/
RUN chown -R appuser:appuser /app /stories

USER appuser

ENV STORIES_DIR=/stories
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

EXPOSE 8080

# 2 workers is fine for a personal site; adjust if needed
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--access-logfile", "-", "main:app"]
