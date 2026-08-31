# PaperAgent — AI for Good OPEA Competition Edition

PaperAgent is an **OPEA-based edge-cloud enterprise academic document assistant**. It combines privacy-sensitive local OpenVINO inference on an AI PC with an OPEA MicroService/MegaService cloud pipeline for literature retrieval and grounded academic question answering.

This repository is prepared for the **AI for Good challenge on generative AI applications for enterprise scenarios using OPEA**. The competition release intentionally excludes credentials, private development data, real paper corpora, machine-specific backups, runtime logs, model weights, and tunnel configuration.

## Competition positioning

PaperAgent separates workloads according to privacy and compute characteristics:

- **Edge privacy layer** — grammar checking and academic polishing run locally with Qwen3 on Intel NPU; academic translation runs locally with HY-MT on CPU.
- **OPEA enterprise cloud layer** — academic retrieval and grounded Q&A are decomposed into OPEA MicroServices and composed through `ServiceOrchestrator` as a PaperAgent MegaService.
- **Document ingestion layer** — PDF ingestion supports MinerU with PyMuPDF fallback; runtime documents and generated paper records are excluded from Git.

The edge service is intentionally not forced into the OPEA runtime. OPEA is used where its modular, cloud-native service composition is most valuable: the enterprise cloud knowledge workflow.

## OPEA cloud architecture

```text
                              Enterprise / Cloud

Academic Question
      |
      v
PaperAgent OPEA MegaService :7008
      |
      |  OPEA ServiceOrchestrator
      v
PaperAgent Retriever MicroService :7011
      |  ServiceType.RETRIEVER
      |  output: OPEA SearchedDoc
      v
Official OPEA LLM TextGen :9000
      |  ServiceType.LLM
      |  OpeaTextGenService
      v
Grounded Literature Answer


                               AI PC / Edge

Academic Draft
      |
      +--> Qwen3 8B INT4 OpenVINO --> Intel NPU --> Grammar / Polish
      |
      +--> HY-MT1.5 1.8B INT4 OpenVINO --> CPU --> Translation
```

This is a real OPEA composition rather than a wrapper label:

1. `CLOUD/opea/retriever_service.py` registers a custom OPEA `ServiceType.RETRIEVER` MicroService.
2. The retriever emits the standard OPEA `SearchedDoc` model.
3. `opea/llm-textgen` provides the official OPEA LLM MicroService and connects to a user-supplied OpenAI-compatible endpoint.
4. `CLOUD/opea/megaservice.py` uses OPEA `ServiceOrchestrator` to form the runtime DAG `paperagent-retriever -> opea-service@llm`.
5. The PaperAgent MegaService exposes `/v1/paperagent` and an observable `/v1/topology` endpoint.
6. The existing Gradio cloud UI uses the MegaService when `OPEA_GATEWAY_URL` is configured and falls back to the compatibility path if OPEA is unavailable.

Detailed OPEA deployment instructions are in [`CLOUD/opea/README.md`](CLOUD/opea/README.md).

## Main capabilities

- **OPEA enterprise RAG**: MicroService + ServiceOrchestrator + MegaService cloud architecture.
- **Academic paper retrieval**: custom PaperAgent OPEA retriever over the sanitized competition corpus/runtime document store.
- **Grounded literature Q&A**: official OPEA LLM TextGen connected to an OpenAI-compatible model endpoint.
- **Edge writing assistant**: grammar checking and academic polishing with Qwen3 OpenVINO on Intel NPU.
- **Local translation**: HY-MT1.5 1.8B INT4 OpenVINO on CPU.
- **PDF ingestion**: optional MinerU integration with PyMuPDF fallback.
- **Unified local UI**: Vue/Vite + Flask + Gradio behind Nginx.
- **Bilingual interface**: Chinese and English support.

## Quick start — OPEA cloud

OPEA cloud deployment is containerized and independent from the Windows AI-PC runtime.

```bash
cd CLOUD/opea
cp .env.example .env
```

Fill in your own OpenAI-compatible endpoint/model/key in `.env`, then run:

```bash
docker compose --env-file .env up -d --build
```

Verify the OPEA composition:

```bash
curl http://localhost:7008/v1/topology
```

Call the PaperAgent MegaService:

```bash
curl -X POST http://localhost:7008/v1/paperagent \
  -H "Content-Type: application/json" \
  -d '{"text":"How can edge-cloud AI improve privacy-aware academic assistance?"}'
```

To route the existing Gradio cloud UI through OPEA:

```bash
export OPEA_GATEWAY_URL=http://localhost:7008
```

Windows PowerShell:

```powershell
$env:OPEA_GATEWAY_URL = "http://localhost:7008"
```

### OPEA cloud ports

| Component | Port |
| --- | ---: |
| PaperAgent OPEA MegaService | 7008 |
| PaperAgent OPEA Retriever | 7011 |
| Official OPEA LLM TextGen | 9000 |

## Quick start — AI PC / edge demo

### Target environment

- Windows 10/11 x64
- Intel Core Ultra platform with a working Intel NPU driver
- Internet access during first deployment
- At least **15 GB free disk space recommended** during first deployment

Double-click:

```text
deploy.bat
```

or run:

```powershell
.\deploy.bat
```

The deployment script prepares uv, Node.js, Nginx, both local OpenVINO models, Python/frontend dependencies, local configuration, environment verification and the sensitive-data scan.

After deployment:

```text
start_all_services.bat
verify_new_computer.bat
```

Local UI:

```text
http://localhost:5000/
```

### Required local models

| Model | Purpose | Runtime | Local path |
| --- | --- | --- | --- |
| Qwen3 8B INT4 OpenVINO | Grammar checking and academic polishing | Intel NPU | `models/Qwen3-8b-ov-npu/` |
| HY-MT1.5 1.8B INT4 OpenVINO | Academic translation | CPU | `models/HY-MT1.5-1.8B-int4-ov/` |

The deployment script downloads Qwen3 as a pre-converted OpenVINO INT4 model and prepares HY-MT as INT4 OpenVINO IR. Model weights are runtime assets and are never committed.

### Local ports

| Component | Port |
| --- | ---: |
| Unified Nginx entry | 5000 |
| Edge Flask API | 5001 |
| Vue/Vite frontend | 5173 |
| Cloud Gradio UI | 7007 |

## Competition data policy

Only a small synthetic paper record is included:

```text
CLOUD/chunks/lunwen/demo_paper.jsonl
```

The original development corpus is not part of this release. Runtime uploads are stored only in ignored/runtime directories. See `DATA_POLICY.md` and `SECURITY.md`.

## Repository layout

```text
CLOUD/
├─ src/                     Gradio UI, retrieval compatibility path, PDF workflow
├─ chunks/lunwen/           synthetic competition record only
└─ opea/
   ├─ retriever_service.py  custom OPEA RETRIEVER MicroService
   ├─ megaservice.py        OPEA ServiceOrchestrator / MegaService
   ├─ docker-compose.yml    enterprise OPEA cloud topology
   ├─ Dockerfile            custom PaperAgent OPEA service image
   └─ .env.example          safe runtime configuration template

EDGE/                       local OpenVINO edge service and Vue frontend
nginx/                      reverse-proxy template
scripts/                    deployment, validation and sanitization scripts
models/README.md            runtime model layout only; no weights
deploy.bat                  AI-PC one-click deployment
DATA_POLICY.md              publication/data rules
SECURITY.md                 credential handling rules
```

## Security checklist before submission

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\scan_sensitive.ps1 -TrackedSourceOnly
```

The OPEA `.env`, cloud API keys, MinerU tokens, local configuration, runtime PDF files, generated paper chunks, model weights and caches are excluded from Git.

## Third-party components

PaperAgent integrates OPEA, OpenVINO, Qwen3, HY-MT, Nginx and other third-party components under their respective licenses. Review each upstream license before redistribution. The competition repository intentionally excludes third-party model weight files.
