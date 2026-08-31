# PaperAgent Competition Data Policy

This public competition repository contains source code and a minimal synthetic demonstration dataset only.

## Excluded from publication

The following content must never be committed:

- API keys, access tokens, JWTs, tunnel credentials, cookies, certificates, or passwords.
- `CLOUD/config.yaml` or any machine-local configuration containing credentials.
- Real user uploads, logs, generated outputs, cached files, or temporary files.
- Private/internal IP addresses, intranet-only configuration, or machine-specific backup snapshots.
- Local model weights and accelerator caches.
- The original development paper corpus under `CLOUD/chunks` or `CLOUD/extra_chunks`.
- Unpublished papers, private manuscripts, participant data, or third-party data without redistribution permission.

## Included demonstration data

`CLOUD/chunks/lunwen/demo_paper.jsonl` is synthetic and was created specifically for this repository. It is not copied from a real publication and contains no personal or confidential information.

## Local configuration

Deployment copies `CLOUD/config.example.yaml` to `CLOUD/config.yaml`. The generated file is ignored by Git. Credentials should be entered locally or supplied via deployment-time environment variables.

## Before every public submission

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\scan_sensitive.ps1 -TrackedSourceOnly
```

If a real secret is ever committed to this repository, revoke it immediately. Deleting it in a later commit is not sufficient; rebuild the public history before continuing to use the repository for competition submission.
