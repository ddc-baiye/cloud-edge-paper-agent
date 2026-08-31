# PaperAgent — AI for Good OPEA Competition Edition

PaperAgent is an **OPEA-based edge-cloud enterprise academic document assistant**. It combines privacy-sensitive local OpenVINO inference on an AI PC with an OPEA MicroService/MegaService cloud pipeline for literature retrieval and grounded academic question answering.

This repository is prepared for the **AI for Good challenge on generative AI applications for enterprise scenarios using OPEA**. Credentials, provider-specific defaults, private development data, real paper corpora, machine-specific backups, runtime logs, model weights, and tunnel configuration are intentionally excluded.

## Competition positioning

PaperAgent separates workloads according to privacy and compute characteristics:

- **Edge privacy layer** — grammar checking and academic polishing run locally with Qwen3 on Intel NPU; academic translation runs locally with HY-MT on CPU.
- **OPEA enterprise cloud layer** — academic retrieval and grounded Q&A are decomposed into OPEA MicroServices and composed through `ServiceOrchestrator` as a PaperAgent MegaService.
- **Document ingestion layer** — PDF ingestion supports MinerU with PyMuPDF fallback; runtime documents and generated paper records are excluded from Git.

The edge service is intentionally not forced into the OPEA runtime. OPEA is used where modular, cloud-native composition is most valuable: the enterprise knowledge workflow.

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
PaperAgent Prompt MicroService :7012
      |  ServiceType.PROMPT_TEMPLATE
      |  output: ChatCompletionRequest
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

This is a real OPEA composition:

1. `CLOUD/opea/retriever_service.py` registers a custom OPEA `ServiceType.RETRIEVER` MicroService.
2. The retriever emits the standard OPEA `SearchedDoc` model.
3. `CLOUD/opea/prompt_service.py` registers a custom OPEA `ServiceType.PROMPT_TEMPLATE` MicroService and converts retrieved evidence into a chat-native request.
4. `opea/llm-textgen` provides the official OPEA LLM MicroService and connects to a **user-supplied** OpenAI-compatible endpoint.
5. `CLOUD/opea/megaservice.py` uses OPEA `ServiceOrchestrator` to form the runtime DAG:

```text
paperagent-retriever -> paperagent-prompt -> opea-service@llm
```

6. The MegaService exposes `/v1/paperagent` and `/v1/topology`.
7. The existing Gradio cloud UI uses the MegaService first and automatically falls back to the compatibility path when OPEA is unavailable.

Detailed OPEA documentation is in [`CLOUD/opea/README.md`](CLOUD/opea/README.md).

## Main capabilities

- OPEA enterprise RAG: MicroService + ServiceOrchestrator + MegaService.
- Academic paper retrieval over the sanitized competition corpus/runtime document store.
- Academic prompt composition as an OPEA `PROMPT_TEMPLATE` MicroService.
- Grounded literature Q&A through the official OPEA LLM TextGen service.
- Qwen3 OpenVINO grammar checking and academic polishing on Intel NPU.
- HY-MT1.5 1.8B INT4 OpenVINO translation on CPU.
- Optional MinerU PDF ingestion with PyMuPDF fallback.
- Vue/Vite + Flask + Gradio behind a unified Nginx entry.
- Chinese/English interface support.

## One-click deployment

### Target environment

For the complete competition demo:

- Windows 10/11 x64
- Intel Core Ultra platform with a working Intel NPU driver
- Docker Desktop with the Docker Compose plugin for the OPEA cloud stack
- Internet access during first deployment
- At least **15 GB free disk space recommended** during first model preparation

Run:

```powershell
.\deploy.bat
```

Default deployment prepares both:

```text
AI-PC / Edge runtime
  + Qwen3 OpenVINO / NPU
  + HY-MT OpenVINO / CPU
  + Vue + Flask + Gradio + Nginx

OPEA Cloud runtime
  + PaperAgent Retriever MicroService
  + PaperAgent Prompt MicroService
  + Official OPEA LLM TextGen
  + PaperAgent MegaService
```

If Docker/Compose is not ready during the default deployment, the Edge deployment continues and OPEA is skipped with an explicit warning. After Docker Desktop is ready, run `deploy.bat -OPEAOnly`.

### Deployment modes

```powershell
# Edge + OPEA cloud
.\deploy.bat

# Edge / AI-PC only
.\deploy.bat -EdgeOnly

# OPEA cloud only
.\deploy.bat -OPEAOnly

# Prepare configuration/dependencies without starting services
.\deploy.bat -SkipStart

# Require both OpenVINO model directories to already exist locally
.\deploy.bat -SkipModelDownload

# CI/non-interactive mode
.\deploy.bat -NonInteractive
```

## User-supplied cloud LLM configuration

The public repository contains **no default LLM provider endpoint, model ID, or API key**.

For a full/OPEA deployment, the script prompts for:

1. OpenAI-compatible LLM endpoint
2. Model ID
3. API key

For non-interactive deployment:

```powershell
$env:PAPERAGENT_LLM_ENDPOINT = "https://your-provider.example"
$env:PAPERAGENT_LLM_MODEL_ID = "your-model-id"
$env:PAPERAGENT_LLM_API_KEY = "your-api-key"
.\deploy.bat -NonInteractive
```

`PAPERAGENT_LLM_ENDPOINT` may be supplied with or without a trailing `/v1`; the OPEA deployment helper normalizes the endpoint for the official OPEA TextGen service.

Optional MinerU configuration:

```powershell
$env:MINERU_API_TOKEN = "your-token"
```

Credentials are written only to local git-ignored runtime configuration files:

```text
CLOUD/config.yaml
CLOUD/opea/.env
```

## Required local models

| Model | Purpose | Runtime | Local path |
| --- | --- | --- | --- |
| Qwen3 8B INT4 OpenVINO | Grammar checking and academic polishing | Intel NPU | `models/Qwen3-8b-ov-npu/` |
| HY-MT1.5 1.8B INT4 OpenVINO | Academic translation | CPU | `models/HY-MT1.5-1.8B-int4-ov/` |

The deployment script downloads Qwen3 as a pre-converted OpenVINO INT4 model and prepares HY-MT as INT4 OpenVINO IR. Model weights are runtime assets and are never committed.

## Verification

After deployment:

```powershell
.\verify_new_computer.bat
```

The verifier checks the Edge runtime. When `CLOUD/opea/.env` exists, it additionally checks:

- Docker and Docker Compose
- Retriever `:7011`
- Prompt Builder `:7012`
- OPEA LLM `:9000`
- MegaService `:7008`
- OPEA topology
- one OPEA RAG query

Manual topology endpoint:

```text
http://localhost:7008/v1/topology
```

Expected flow:

```text
paperagent-retriever -> paperagent-prompt -> opea-service@llm
```

## Runtime URLs and ports

| Component | Port |
| --- | ---: |
| Unified Nginx UI entry | 5000 |
| Edge Flask API | 5001 |
| Vue/Vite frontend | 5173 |
| Cloud Gradio UI | 7007 |
| OPEA MegaService | 7008 |
| OPEA Retriever | 7011 |
| OPEA Prompt Builder | 7012 |
| Official OPEA LLM TextGen | 9000 |

Main local UI:

```text
http://localhost:5000/
```

`start_all_services.bat` automatically points the Gradio cloud UI to `http://127.0.0.1:7008`. When OPEA is unavailable, the UI falls back to the compatibility path.

## Competition data policy

Only a small synthetic paper record is included:

```text
CLOUD/chunks/lunwen/demo_paper.jsonl
```

The original development corpus is not part of this release. Runtime uploads are stored only in ignored/runtime directories. See `DATA_POLICY.md` and `SECURITY.md`.

## Repository layout

```text
CLOUD/
├─ src/                     Gradio UI, compatibility path, PDF workflow
├─ chunks/lunwen/           synthetic competition record only
└─ opea/
   ├─ retriever_service.py  custom OPEA RETRIEVER MicroService
   ├─ prompt_service.py     custom OPEA PROMPT_TEMPLATE MicroService
   ├─ megaservice.py        OPEA ServiceOrchestrator / MegaService
   ├─ docker-compose.yml    OPEA cloud topology
   ├─ Dockerfile            custom PaperAgent OPEA service image
   └─ .env.example          safe provider-neutral template

EDGE/                       local OpenVINO edge service and Vue frontend
nginx/                      reverse-proxy template
scripts/                    deployment, verification and sanitization scripts
models/README.md            runtime model layout only; no weights
deploy.bat                  unified Edge + OPEA deployment entry
verify_new_computer.bat     integrated deployment verification
DATA_POLICY.md              publication/data rules
SECURITY.md                 credential handling rules
```

## Security check before submission

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\scan_sensitive.ps1 -TrackedSourceOnly
```

The OPEA `.env`, cloud API keys, MinerU tokens, local configuration, runtime PDF files, generated paper chunks, model weights and caches are excluded from Git.

## Third-party components

PaperAgent integrates OPEA, OpenVINO, Qwen3, HY-MT, Nginx and other third-party components under their respective licenses. Review each upstream license before redistribution. The competition repository intentionally excludes third-party model weight files.
