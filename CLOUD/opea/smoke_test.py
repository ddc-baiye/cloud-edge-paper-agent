"""Minimal smoke test for the PaperAgent OPEA MegaService.

Usage:
    python smoke_test.py
    python smoke_test.py --base-url http://localhost:7008
"""

import argparse
import json
import sys
import urllib.error
import urllib.request


def get_json(url: str):
    with urllib.request.urlopen(url, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def post_json(url: str, payload: dict):
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://localhost:7008")
    args = parser.parse_args()
    base = args.base_url.rstrip("/")

    try:
        topology = get_json(f"{base}/v1/topology")
        flow = topology.get("flow") or []
        expected = ["paperagent-retriever", "paperagent-prompt", "opea-service@llm"]
        if flow != expected:
            raise RuntimeError(f"Unexpected OPEA flow: {flow!r}")
        print(f"[OK] OPEA topology: {' -> '.join(flow)}")

        response = post_json(
            f"{base}/v1/paperagent",
            {
                "text": "How does PaperAgent combine edge privacy with cloud literature intelligence?",
                "temperature": 0.2,
                "max_tokens": 512,
            },
        )
        if response.get("framework") != "OPEA":
            raise RuntimeError(f"Framework marker is missing: {response!r}")
        if not str(response.get("answer") or "").strip():
            raise RuntimeError("MegaService returned an empty answer")
        print("[OK] PaperAgent MegaService returned an OPEA answer")
        return 0
    except (urllib.error.URLError, TimeoutError, RuntimeError, ValueError) as exc:
        print(f"[FAIL] OPEA smoke test failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
