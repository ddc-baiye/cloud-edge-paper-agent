# Local Model Runtime Assets

This directory is intentionally excluded from Git except for this README and `model-manifest.yaml`. `deploy.bat` prepares the required model assets automatically before the application starts.

## Required models

| Local directory | Purpose | Device | Default provisioning |
| --- | --- | --- | --- |
| `Qwen3-8b-ov-npu/` | Grammar checking and academic polishing | Intel NPU | ModelScope `OpenVINO/Qwen3-8B-int4-cw-ov` |
| `HY-MT1.5-1.8B-int4-ov/` | Academic translation | CPU | ModelScope `Tencent-Hunyuan/HY-MT1.5-1.8B`, then local OpenVINO INT4 export |

ModelScope is the default competition download source. If a ModelScope download fails, `scripts/download_models.ps1` falls back to Hugging Face automatically.

To force Hugging Face as the primary source:

```powershell
$env:PAPERAGENT_MODEL_SOURCE = "huggingface"
.\deploy.bat
```

A complete installation must contain:

```text
models/
├─ README.md
├─ model-manifest.yaml
├─ Qwen3-8b-ov-npu/
│  ├─ openvino_model.xml
│  └─ openvino_model.bin
└─ HY-MT1.5-1.8B-int4-ov/
   ├─ openvino_model.xml
   └─ openvino_model.bin
```

The source repository does not redistribute model weights. Model licenses remain governed by the corresponding upstream model repositories.
