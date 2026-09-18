# ── Imagen base fija (sin usar :latest) ─────────────────────────────────────
FROM python:3.12.11-slim-bookworm

# ── Metadata ────────────────────────────────────────────────────────────────
LABEL maintainer="Henrique Alvarado"
LABEL project="avance2-red-social"

# ── Variables de entorno del sistema ────────────────────────────────────────
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# ── Directorio de trabajo ────────────────────────────────────────────────────
WORKDIR /app

# ── Instalar dependencias del sistema (sin extras) ──────────────────────────
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Instalar dependencias Python ─────────────────────────────────────────────
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ── Copiar código fuente ──────────────────────────────────────────────────────
COPY app.py .
COPY templates/ templates/
COPY static/ static/

# ── Crear usuario no-root ─────────────────────────────────────────────────────
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
USER appuser

# ── Exponer puerto ────────────────────────────────────────────────────────────
EXPOSE 5000

# ── Health check ──────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/salud')" || exit 1

# ── Comando de inicio con gunicorn ────────────────────────────────────────────
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "app:app"]
