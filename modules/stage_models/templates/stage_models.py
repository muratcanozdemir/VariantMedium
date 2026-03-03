#!/usr/bin/env python

import hashlib
import requests
from pathlib import Path


def download_file(url: str, dest: Path) -> None:
    for attempt in range(5):
        try:
            response = requests.get(url, timeout=60)
            response.raise_for_status()
            dest.write_bytes(response.content)
            return
        except requests.RequestException as e:
            print(f"Attempt {attempt + 1}/5 failed: {e}")
    raise RuntimeError(f"Failed to download {url} after 5 attempts")


def verify_sha256(file_path: Path, expected: str) -> None:
    h = hashlib.sha256()
    with file_path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    actual = h.hexdigest()
    if actual != expected:
        raise ValueError(
            f"SHA-256 mismatch for {file_path.name}\n"
            f"  expected: {expected}\n"
            f"  actual:   {actual}"
        )
    print(f"  SHA-256 verified: {file_path.name}")


def generate_version_yml() -> None:
    with open("versions.yml", "w") as f:
        f.write("${task.process}\n")
        f.write("stage_models: ${params.version}\n")


def main() -> None:
    # URLs pinned to specific HuggingFace commit SHAs — never resolve/main/
    # To update: fetch the commit SHA from the HuggingFace repo and update
    # both the URL and sha256 atomically. See docs/models/info.txt for provenance.
    files = [
        {
            "url": "https://huggingface.co/tron-mainz/3ddensenet_snv/resolve/${params.model_commit_snv}/3ddensenet_snv.pt",
            "filename": "3ddensenet_snv.pt",
            "sha256": "${params.model_sha256_snv}",
        },
        {
            "url": "https://huggingface.co/tron-mainz/3ddensenet_indel/resolve/${params.model_commit_indel}/3ddensenet_indel.pt",
            "filename": "3ddensenet_indel.pt",
            "sha256": "${params.model_sha256_indel}",
        },
        {
            "url": "https://huggingface.co/tron-mainz/extra_trees.snv/resolve/${params.model_commit_extra_trees_snv}/extra_trees.snv.joblib",
            "filename": "extra_trees.snv.joblib",
            "sha256": "${params.model_sha256_extra_trees_snv}",
        },
        {
            "url": "https://huggingface.co/tron-mainz/extra_trees.indel/resolve/${params.model_commit_extra_trees_indel}/extra_trees.indel.joblib",
            "filename": "extra_trees.indel.joblib",
            "sha256": "${params.model_sha256_extra_trees_indel}",
        },
    ]

    output_dir = Path("./models")
    output_dir.mkdir(parents=True, exist_ok=True)

    for f in files:
        dest = output_dir / f["filename"]
        print(f"Downloading {f['filename']} ...")
        download_file(f["url"], dest)
        verify_sha256(dest, f["sha256"])

    print("All models downloaded and verified")
    generate_version_yml()


if __name__ == "__main__":
    main()