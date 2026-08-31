# PaperAgent — Competition Edition

PaperAgent is an edge-cloud academic assistant. It combines local OpenVINO inference for privacy-sensitive writing assistance with an optional cloud workflow for paper retrieval, document parsing, and literature-oriented question answering.

This repository is prepared for competition submission. Credentials, private development data, real paper corpora, machine-specific backups, runtime logs, model weights, and tunnel configuration are intentionally excluded.

## Main capabilities

- **Edge writing assistant**: grammar checking and academic polishing with a local Qwen3 OpenVINO model on Intel NPU.
- **Local translation**: academic translation with a local HY-MT1.5 1.8B INT4 OpenVINO model on CPU.
- **Cloud paper assistant**: Gradio-based paper retrieval and grounded question answering through a user-supplied OpenAI-compatible LLM endpoint.
- **PDF ingestion**: optional MinerU integration, with PyMuPDF fallback where applicable.
- **Unified local entry point**: Nginx routes the Vue frontend, edge API, and cloud UI behind `http://localhost:5000/`.
- **Bilingual UI**: Chinese and English interface support.

## Architecture

```text
Browser
  |
  v
Nginx :5000
  |----------------------|----------------------|
  v                      v                      v
Vue/Vite :5173      Edge Flask :5001      Cloud Gradio :7007
                         |                      |
              |----------|----------|           v
              v                     v     Paper retrieval + LLM
     Qwen3 8B OpenVINO       HY-MT1.5 1.8B
        Intel NPU           OpenVINO / CPU
```

## Required local models

PaperAgent uses **two local models**. Both are required for the complete competition demo:

| Model | Purpose | Runtime | Local path |
| --- | --- | --- | --- |
| Qwen3 8B INT4 OpenVINO | Grammar checking and academic polishing | Intel NPU | `models/Qwen3-8b-ov-npu/` |
| HY-MT1.5 1.8B INT4 OpenVINO | Academic translation | CPU | `models/HY-MT1.5-1.8B-int4-ov/` |

The deployment script prepares both automatically:

1. Qwen3 is downloaded as a pre-converted OpenVINO INT4 model from `OpenVINO/Qwen3-8B-int4-ov`.
2. HY-MT is sourced from `tencent/HY-MT1.5-1.8B` and converted locally to INT4 OpenVINO IR with the current Optimum Intel/OpenVINO exporter.

For environments where the team publishes a pre-converted HY-MT OpenVINO repository, set `PAPERAGENT_HYMT_OV_REPO`; deployment will download that repository directly instead of performing the conversion.

Model weights are runtime assets. They are ignored by Git and must not be committed to the competition repository.

## Competition data policy

Only a small synthetic retrieval record is included:

```text
CLOUD/chunks/lunwen/demo_paper.jsonl
```

The development paper corpus is not part of this release. See `DATA_POLICY.md` and `SECURITY.md` before publishing or submitting the repository.

## One-click deployment

### Target environment

- Windows 10/11 x64
- Intel Core Ultra platform with a working Intel NPU driver
- Internet access for dependency/model download during first deployment
- At least **15 GB of free disk space recommended** during first deployment because the HY-MT source checkpoint is downloaded temporarily before INT4 OpenVINO conversion

### Start

Double-click:

```text
deploy.bat
```

or run:

```powershell
.\deploy.bat
```

The deployment workflow will:

1. Install or locate `uv`.
2. Install or locate Node.js LTS.
3. Download Nginx 1.30.1 when absent.
4. Download the Qwen3 8B INT4 OpenVINO model.
5. Download and convert HY-MT1.5 1.8B to INT4 OpenVINO IR, or download a pre-converted repository when an override is configured.
6. Verify that **both** OpenVINO model directories contain the required IR files.
7. Create a local `CLOUD/config.yaml` from the safe template.
8. Create the Python 3.11 environment and install locked dependencies.
9. Run `npm ci` for the Vue frontend.
10. Verify OpenVINO/NPU availability and required project assets.
11. Run a sensitive-data scan.
12. Start PaperAgent and expose `http://localhost:5000/`.

After model preparation, the expected local layout is:

```text
models/
├─ Qwen3-8b-ov-npu/
│  ├─ openvino_model.xml
│  └─ openvino_model.bin
└─ HY-MT1.5-1.8B-int4-ov/
   ├─ openvino_model.xml
   └─ openvino_model.bin
```

### Optional deployment variables

You can avoid interactive credential input by setting environment variables before deployment:

```powershell
$env:PAPERAGENT_LLM_API_KEY = "your-key"
$env:MINERU_API_TOKEN = "your-token"
.\deploy.bat
```

`DEEPSEEK_API_KEY` is also accepted as an LLM-key fallback. Credentials are written only to the ignored local file `CLOUD/config.yaml`.

Model source overrides are also supported:

```powershell
# Optional: replace the default Qwen OpenVINO repository
$env:PAPERAGENT_QWEN_OV_REPO = "OpenVINO/Qwen3-8B-int4-ov"

# Optional: replace the source HY-MT repository used for local conversion
$env:PAPERAGENT_HYMT_SOURCE_REPO = "tencent/HY-MT1.5-1.8B"

# Optional: if you publish your already-converted HY-MT OpenVINO model,
# set this and deployment will download it directly instead of converting.
$env:PAPERAGENT_HYMT_OV_REPO = "YOUR_ACCOUNT/HY-MT1.5-1.8B-int4-ov"
```

Useful options:

```powershell
# Prepare everything without starting services
.\deploy.bat -SkipStart

# Do not download or convert models; require BOTH models to already exist locally
.\deploy.bat -SkipModelDownload

# CI/non-interactive deployment
.\deploy.bat -NonInteractive
```

## Manual start and verification

After a successful deployment:

```text
start_all_services.bat
verify_new_computer.bat
```

The verification script treats both Qwen3 and HY-MT OpenVINO IR files as required assets.

Default local ports:

| Component | Port |
| --- | ---: |
| Unified Nginx entry | 5000 |
| Edge Flask API | 5001 |
| Vue/Vite frontend | 5173 |
| Cloud Gradio service | 7007 |

## Repository layout

```text
CLOUD/                  cloud paper retrieval and Gradio UI
EDGE/                   local OpenVINO edge service and Vue frontend
nginx/                  reverse-proxy template
scripts/                deployment, validation, sanitization scripts
deploy.bat               one-click competition deployment
start_all_services.bat   service launcher
DATA_POLICY.md           publication/data rules
SECURITY.md              credential handling rules
```

## Security checklist before submission

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\scan_sensitive.ps1 -TrackedSourceOnly
```

## Third-party components

PaperAgent downloads or uses third-party software/models under their respective licenses. Review the license terms of OpenVINO, Qwen3, HY-MT, Nginx, and other dependencies before redistribution. The competition repository intentionally excludes model weight files.
