# PaperAgent OPEA Cloud

This directory contains the **OPEA-native cloud orchestration layer** used by the PaperAgent AI for Good competition edition.

The local edge workflow remains responsible for privacy-sensitive writing assistance on the user's AI PC. The cloud workflow is decomposed into OPEA MicroServices and composed as an OPEA MegaService for enterprise literature retrieval and grounded question answering.

## OPEA topology

```text
Question
  |
  v
PaperAgent OPEA MegaService :7008
  |
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
Grounded academic answer
```

The MegaService uses OPEA `ServiceOrchestrator` to build the runtime DAG:

```text
paperagent-retriever -> paperagent-prompt -> opea-service@llm
```

The retriever and prompt builder are PaperAgent domain components registered as OPEA MicroServices. The LLM layer uses the official OPEA TextGen service and can connect to a user-supplied OpenAI-compatible endpoint.

## Components

| Component | OPEA role | Port | Implementation |
| --- | --- | ---: | --- |
| `paperagent-retriever` | `ServiceType.RETRIEVER` | 7011 | Custom PaperAgent OPEA MicroService |
| `paperagent-prompt` | `ServiceType.PROMPT_TEMPLATE` | 7012 | Custom PaperAgent OPEA MicroService |
| `opea-llm` | `ServiceType.LLM` | 9000 | Official `opea/llm-textgen` / `OpeaTextGenService` |
| `paperagent-megaservice` | `ServiceType.GATEWAY`, MegaService | 7008 | OPEA `ServiceOrchestrator` |

Only the synthetic competition corpus is shipped in Git. Runtime PDF-derived records remain in ignored/runtime storage.

## Recommended deployment

On the Windows competition machine, use the repository-level deployment entry:

```powershell
.\deploy.bat
```

The default mode prepares the AI-PC edge runtime and, when Docker Desktop is ready, also deploys the OPEA cloud stack.

Deployment modes:

```powershell
# Edge + OPEA cloud
.\deploy.bat

# AI-PC / edge only
.\deploy.bat -EdgeOnly

# OPEA cloud only
.\deploy.bat -OPEAOnly

# Prepare configuration/dependencies without starting services
.\deploy.bat -SkipStart
```

For OPEA deployment, the user must provide all three cloud LLM settings. The repository does not contain provider defaults:

- `LLM endpoint`
- `LLM model ID`
- `LLM API key`

Interactive deployment prompts for these values. For non-interactive deployment, set:

```powershell
$env:PAPERAGENT_LLM_ENDPOINT = "https://your-provider.example"
$env:PAPERAGENT_LLM_MODEL_ID = "your-model-id"
$env:PAPERAGENT_LLM_API_KEY = "your-api-key"
.\deploy.bat -NonInteractive
```

The deployment script creates `CLOUD/opea/.env` locally. That file is git-ignored and must never be committed.

`PAPERAGENT_LLM_ENDPOINT` may be entered with or without a trailing `/v1`; the OPEA deployment helper normalizes it for the official OPEA TextGen service.

## Manual Docker Compose deployment

If you want to manage the OPEA stack directly:

```bash
cd CLOUD/opea
cp .env.example .env
```

Fill in your own OpenAI-compatible values:

```dotenv
LLM_ENDPOINT=https://your-provider.example
LLM_MODEL_ID=your-model-id
OPENAI_API_KEY=your-api-key
```

Then run:

```bash
docker compose --env-file .env up -d --build
```

## Verification

OPEA services expose the standard OPEA health endpoints. The deployment script waits for all four services and then validates the topology plus one RAG request.

Manual topology check:

```bash
curl http://localhost:7008/v1/topology
```

Expected flow:

```text
paperagent-retriever -> paperagent-prompt -> opea-service@llm
```

Call the MegaService:

```bash
curl -X POST http://localhost:7008/v1/paperagent \
  -H "Content-Type: application/json" \
  -d '{"text":"How can an edge-cloud academic assistant protect private drafts while using cloud literature intelligence?"}'
```

Run the Python smoke test:

```bash
python smoke_test.py
```

On the Windows competition machine, the integrated verifier also checks OPEA when `CLOUD/opea/.env` exists:

```powershell
.\verify_new_computer.bat
```

## Connect the Gradio cloud UI

`start_all_services.bat` automatically points the local Gradio UI to:

```text
http://127.0.0.1:7008
```

When the OPEA MegaService is healthy, questions use the OPEA pipeline first. If OPEA is unavailable, the UI automatically falls back to the compatibility path so the local demo remains usable.

## Security

- `.env` is local-only and git-ignored.
- No LLM provider endpoint, model ID, API key, or MinerU token is hardcoded in the public configuration templates.
- Credentials are injected through interactive deployment or environment variables.
- Original/private paper corpora are excluded from the competition repository.
- Runtime uploads and generated chunks are ignored.
- See the root `SECURITY.md` and `DATA_POLICY.md`.
