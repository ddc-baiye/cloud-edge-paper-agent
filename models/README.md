# Local Model Runtime Assets

This directory is intentionally kept out of Git except for this manifest. `deploy.bat` prepares the required model assets automatically.

## Required models

| Local directory | Purpose | Device | Provisioning |
| --- | --- | --- | --- |
| `Qwen3-8b-ov-npu/` | Grammar checking and academic polishing | Intel NPU | Download `OpenVINO/Qwen3-8B-int4-ov` |
| `HY-MT1.5-1.8B-int4-ov/` | Academic translation | CPU | Convert `tencent/HY-MT1.5-1.8B` to INT4 OpenVINO IR, or download the repository specified by `PAPERAGENT_HYMT_OV_REPO` |

A complete installation must contain:

```text
models/
├─ Qwen3-8b-ov-npu/
│  ├─ openvino_model.xml
│  └─ openvino_model.bin
└─ HY-MT1.5-1.8B-int4-ov/
   ├─ openvino_model.xml
   └─ openvino_model.bin
```

Do not commit model weights or generated accelerator caches to the competition repository.
