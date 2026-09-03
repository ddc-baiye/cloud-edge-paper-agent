# PaperAgent Competition Demo Guide

This guide is intended for reviewers who want to verify the complete PaperAgent prototype rather than only inspect source code.

## 1. Target Environment

Recommended complete-demo environment:

- Windows 10/11 x64
- Intel Core Ultra platform with Intel NPU driver
- Docker Desktop with Docker Compose
- Internet access for first-time dependency and model download
- Sufficient free disk space for Qwen3, HY-MT, Python packages, and container images

Model weights are not stored in Git. The deployment script downloads them automatically.

## 2. One-click Deployment

Open PowerShell or Command Prompt in the repository root and run:

```powershell
.\deploy.bat
```

Default model source: ModelScope.

The first deployment prepares:

- Qwen3-8B INT4 OpenVINO for Intel NPU
- HY-MT1.5-1.8B, converted to OpenVINO INT4 for CPU translation
- Edge Flask service
- Vue frontend
- Gradio cloud interface
- Nginx unified entry
- OPEA Retriever MicroService
- OPEA Prompt MicroService
- OPEA LLM TextGen service
- PaperAgent MegaService

If the required models already exist and pass validation, they are reused.

### Optional deployment modes

```powershell
# Complete edge + OPEA deployment
.\deploy.bat

# Edge only
.\deploy.bat -EdgeOnly

# OPEA cloud only
.\deploy.bat -OPEAOnly

# Reuse models already prepared locally
.\deploy.bat -SkipModelDownload

# Prepare without starting services
.\deploy.bat -SkipStart

# Non-interactive deployment
.\deploy.bat -NonInteractive
```

To force Hugging Face instead of ModelScope for model preparation:

```powershell
$env:PAPERAGENT_MODEL_SOURCE = "huggingface"
.\deploy.bat
```

## 3. Runtime Entry Points

After startup:

| Component | URL |
| --- | --- |
| Main PaperAgent UI | `http://localhost:5000/` |
| Edge API | `http://localhost:5001/` |
| Cloud UI | `http://localhost:7007/` |
| OPEA MegaService | `http://localhost:7008/v1/paperagent` |
| OPEA topology | `http://localhost:7008/v1/topology` |

## 4. Demo Workflow A - Local Academic Writing Assistance

1. Open `http://localhost:5000/`.
2. Select the edge/local writing workflow.
3. Paste an academic paragraph containing grammar or style issues.
4. Run **Grammar Check**.
5. Run **Academic Polish**.
6. Confirm that Qwen3 is executing through the local OpenVINO NPU path.

What this demonstrates:

- local model execution;
- privacy-sensitive text processing on the AI PC;
- Qwen3 INT4 OpenVINO inference;
- Intel NPU acceleration.

## 5. Demo Workflow B - Local Academic Translation

1. Paste an English or Chinese academic paragraph.
2. Select the target language.
3. Run translation.
4. Confirm that HY-MT1.5-1.8B produces the translated text through the local CPU OpenVINO path.

What this demonstrates:

- dedicated multilingual translation model;
- local CPU inference;
- model specialization instead of routing every task to the same cloud LLM.

## 6. Demo Workflow C - OPEA Literature RAG

The repository includes a sanitized synthetic demonstration record:

```text
CLOUD/chunks/lunwen/demo_paper.jsonl
```

Use the cloud/literature assistant to ask a question related to the included demonstration content.

Suggested evaluation pattern:

```text
What is the main contribution described in the indexed paper?
```

Then inspect:

```text
http://localhost:7008/v1/topology
```

Expected service chain:

```text
paperagent-retriever -> paperagent-prompt -> opea-service@llm
```

What this demonstrates:

- OPEA Retriever MicroService;
- OPEA Prompt Template MicroService;
- official OPEA LLM TextGen integration;
- ServiceOrchestrator/MegaService composition;
- grounded literature answer generation.

## 7. Verification Script

Run:

```powershell
.\verify_new_computer.bat
```

The verifier checks the edge services and, when the OPEA environment exists, additionally checks the OPEA MicroServices, MegaService, topology, and one RAG request.

## 8. Sensitive-data Check

Before packaging or publishing a submission build:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\scan_sensitive.ps1 -TrackedSourceOnly
```

The competition repository must not include:

- API keys or tokens;
- private `.env` files;
- real research corpora;
- runtime uploads;
- model weights;
- internal IP addresses or tunnel configuration;
- machine-specific backups.

## 9. Reviewer Focus

The complete prototype is intended to demonstrate four points together:

1. **Real local AI inference** - the edge functions are backed by downloaded models, not mocked interfaces.
2. **Real OPEA composition** - retrieval, prompt construction, LLM service, and orchestration are separate runtime services.
3. **Privacy-aware cloud-edge placement** - writing assistance remains local while knowledge orchestration can use cloud services.
4. **Reproducible open-source delivery** - code, deployment automation, safe demo data, architecture documentation, and verification scripts are included in the public repository.
