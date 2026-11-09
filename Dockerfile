# syntax=docker/dockerfile:1

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/app

# Dependencies first, so code changes don't invalidate this layer
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Application code. Flask resolves templates/ and assets/ from the directory
# of main.py (/app); the SQLite file and uploads are created in the working
# directory, which is /data so they can live on a single volume.
COPY main.py createdb.py /app/
COPY templates /app/templates
COPY assets /app/assets

# The app uploads to ./imagenes (i.e. /data/imagenes) but serves /imagenes/*
# from its own directory, so /app/imagenes points at the data volume.
RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /data/imagenes \
    && ln -s /data/imagenes /app/imagenes \
    && chown -R appuser:appuser /data /app
USER appuser

WORKDIR /data

# Holds tareas.db and the uploaded images. Named volume:
#   docker run -v taskhub-data:/data ...
# Bind mount (host dir must be writable by uid 10001, or pass --user):
#   docker run -v "$PWD/data:/data" ...
VOLUME ["/data"]

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/', timeout=3)"

# PASSWORD is required at runtime (used by /api/reset and /api/delete).
# A single worker with threads is deliberate: SQLite allows one writer, so
# multiple processes would produce "database is locked" errors.
CMD ["gunicorn", "--chdir", "/data", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "4", "--access-logfile", "-", "main:app"]
