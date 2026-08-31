# Security and Credential Handling

PaperAgent must not store production credentials in Git.

## Rules for this public competition repository

1. Keep `CLOUD/config.yaml` local only; use `CLOUD/config.example.yaml` as the committed template.
2. Do not publish NAT traversal tokens, intranet configuration, local backup files, logs, uploads, model weights, or accelerator caches.
3. Run `scripts/scan_sensitive.ps1` before every submission or public release.
4. Use only synthetic or redistribution-safe demonstration data.

## Deployment-time variables

The one-click deployment script accepts:

- `PAPERAGENT_LLM_API_KEY`
- `DEEPSEEK_API_KEY` as an LLM-key fallback
- `MINERU_API_TOKEN`
- `PAPERAGENT_QWEN_OV_REPO` for an alternate Qwen OpenVINO repository
- `PAPERAGENT_HYMT_SOURCE_REPO` for an alternate HY-MT source repository
- `PAPERAGENT_HYMT_OV_REPO` for a pre-converted HY-MT OpenVINO repository

If credential variables are not set, interactive deployment can request them locally. Values are written only to ignored local configuration.

If a secret is accidentally committed, revoke it immediately. Removing the value from the latest version does not remove it from Git history.
