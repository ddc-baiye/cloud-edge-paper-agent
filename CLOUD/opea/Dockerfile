FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/app/CLOUD:/app/CLOUD/src

WORKDIR /app

RUN pip install --no-cache-dir \
    "opea-comps==1.5" \
    "httpx>=0.28,<0.29" \
    "pyyaml>=6,<7"

# Copy only the source files required by the custom OPEA services.
# Local configuration, credentials, uploads, generated chunks, logs and model
# weights are deliberately never copied into the competition service image.
RUN mkdir -p /app/CLOUD/src /app/CLOUD/opea /app/CLOUD/chunks/lunwen /app/CLOUD/extra_chunks/lunwen

COPY CLOUD/src/chat_bot.py /app/CLOUD/src/chat_bot.py
COPY CLOUD/opea/retriever_service.py /app/CLOUD/opea/retriever_service.py
COPY CLOUD/opea/prompt_service.py /app/CLOUD/opea/prompt_service.py
COPY CLOUD/opea/megaservice.py /app/CLOUD/opea/megaservice.py
COPY CLOUD/chunks/lunwen/demo_paper.jsonl /app/CLOUD/chunks/lunwen/demo_paper.jsonl

WORKDIR /app/CLOUD
