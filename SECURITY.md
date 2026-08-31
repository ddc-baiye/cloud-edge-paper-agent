# Security and Credential Handling

PaperAgent must not store production credentials or private provider configuration in Git.

## Rules for this public competition repository

1. Keep `CLOUD/config.yaml` local only; use `CLOUD/config.example.yaml` as the committed template.
2. Keep `CLOUD/opea/.env` local only; use `CLOUD/opea/.env.example` as the committed template.
3. Do not publish NAT traversal tokens, intranet configuration, local backup files, logs, uploads, model weights, accelerator caches, or private paper corpora.
4. Run `scripts/scan_sensitive.ps1` before every submission or public release.
5. Use only synthetic or redistribution-safe demonstration data.

## Deployment-time variables

The one-click deployment accepts provider-neutral cloud LLM configuration:

- `PAPERAGENT_LLM_ENDPOINT`
- `PAPERAGENT_LLM_MODEL_ID`
- `PAPERAGENT_LLM_API_KEY`
- `MINERU_API_TOKEN` (optional)

Compatibility aliases accepted by the deployment scripts include:

- `LLM_ENDPOINT`
- `LLM_MODEL_ID`
- `OPENAI_API_KEY`

Model-source overrides:

- `PAPERAGENT_QWEN_OV_REPO` for an alternate Qwen OpenVINO repository
- `PAPERAGENT_HYMT_SOURCE_REPO` for an alternate HY-MT source repository
- `PAPERAGENT_HYMT_OV_REPO` for a pre-converted HY-MT OpenVINO repository

No default LLM provider endpoint, model ID, or API key is stored in the public repository. Interactive deployment requests the values locally when the OPEA cloud is enabled.

Runtime values are written only to ignored local configuration files:

```text
CLOUD/config.yaml
CLOUD/opea/.env
```

If a secret is accidentally committed, revoke it immediately. Removing the value from the latest version does not remove it from Git history.
