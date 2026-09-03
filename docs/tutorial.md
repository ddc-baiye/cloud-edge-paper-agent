# PaperAgent Tutorial

This tutorial provides a recommended walkthrough for reviewers to deploy and evaluate the complete PaperAgent prototype.

## 1. Environment Preparation

Recommended environment:

- Windows 10/11 x64
- Intel Core Ultra platform with Intel NPU driver
- Docker Desktop with Docker Compose
- Internet access for first-time model and dependency download

Model weights are downloaded automatically during deployment and are not stored in the repository.

## 2. One-click Deployment

Open PowerShell in the repository root:

```powershell
.\deploy.bat
```

The deployment process prepares:

- Qwen3-8B INT4 OpenVINO inference model
- HY-MT1.5-1.8B translation model
- Edge AI services
- OPEA MicroServices
- PaperAgent MegaService
- Web interfaces

After successful deployment, the system provides local and cloud-edge AI capabilities.

## 3. Local AI Writing Assistant

Open:

```text
http://localhost:5000/
```

Workflow:

1. Enter an academic paragraph.
2. Run Grammar Check.
3. Run Academic Polish.
4. Review the improved result.

This demonstrates:

- Local AI inference on AI PC.
- Privacy-sensitive writing processing.
- Qwen3-8B INT4 OpenVINO acceleration.

## 4. Local Academic Translation

Workflow:

1. Enter academic content.
2. Select translation task.
3. Generate translated output.

This demonstrates:

- Dedicated translation model.
- Local CPU inference.
- HY-MT1.5-1.8B based translation capability.

## 5. OPEA Literature RAG Assistant

Use the included sanitized demo data:

```text
CLOUD/chunks/lunwen/demo_paper.jsonl
```

Example question:

```text
What is the main contribution described in the indexed paper?
```

Runtime flow:

```text
PDF / Document
      ↓
Retriever MicroService
      ↓
Prompt MicroService
      ↓
OPEA LLM TextGen
      ↓
MegaService
      ↓
Grounded Answer
```

Verify OPEA topology:

```text
http://localhost:7008/v1/topology
```

## 6. Architecture Overview

PaperAgent adopts a cloud-edge architecture:

- Edge AI PC: private writing assistance and translation.
- Cloud OPEA services: document retrieval, prompt construction, and grounded generation.
- Unified orchestration: PaperAgent MegaService.

## 7. Troubleshooting

### Model download failure

Check network connectivity and retry deployment.

### Docker service unavailable

Ensure Docker Desktop and Docker Compose are running.

### NPU inference unavailable

Confirm Intel NPU driver installation and device availability.

## 8. Evaluation Checklist

Reviewers can verify:

- One-click deployment.
- Real model-backed inference.
- OPEA MicroService composition.
- Cloud-edge privacy-aware workflow.
- Sanitized open-source delivery.
