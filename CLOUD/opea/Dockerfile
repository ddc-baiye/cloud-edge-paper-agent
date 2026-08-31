FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/app/CLOUD:/app/CLOUD/src

WORKDIR /app

RUN pip install --no-cache-dir \
    "opea-comps>=1.5,<1.6" \
    "httpx>=0.28,<0.29" \
    "pyyaml>=6,<7"

COPY CLOUD /app/CLOUD

WORKDIR /app/CLOUD
