#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


DRM_MEMORY_RE = re.compile(r"drm-(total|resident|shared|memory)-([^:]+):\s+(.+)$")


def parse_size_to_kib(value: str) -> int:
    parts = value.strip().split()
    if not parts:
        return 0

    try:
        amount = float(parts[0])
    except ValueError:
        return 0

    unit = parts[1].lower() if len(parts) > 1 else "kib"
    if unit in ("kib", "kb"):
        return int(amount)
    if unit in ("mib", "mb"):
        return int(amount * 1024)
    if unit in ("gib", "gb"):
        return int(amount * 1024 * 1024)
    return int(amount)


def read_swap_kib(pid: str) -> int:
    try:
        for line in Path(f"/proc/{pid}/status").read_text(errors="ignore").splitlines():
            if line.startswith("VmSwap:"):
                return parse_size_to_kib(line.split(":", 1)[1])
    except OSError:
        pass
    return 0


def read_gpu_metrics_from_fdinfo_texts(fdinfo_texts) -> dict:
    best_total = 0
    best_resident = 0
    best_shared = 0

    for text in fdinfo_texts:
        total = resident = shared = memory = 0
        for line in text.splitlines():
            match = DRM_MEMORY_RE.match(line)
            if not match:
                continue

            kind, _region, raw_value = match.groups()
            value = parse_size_to_kib(raw_value)
            if kind == "total":
                total += value
            elif kind == "resident":
                resident += value
            elif kind == "shared":
                shared += value
            elif kind == "memory":
                # amdgpu kept this as a deprecated fdinfo alias for resident memory.
                memory += value

        resident = max(resident, memory)
        total = max(total, resident)

        best_total = max(best_total, total)
        best_resident = max(best_resident, resident)
        best_shared = max(best_shared, shared)

    return {
        "gpuMemoryKB": best_total,
        "gpuResidentKB": best_resident,
        "gpuSharedKB": best_shared,
    }


def read_gpu_metrics(pid: str) -> dict:
    fdinfo_dir = Path(f"/proc/{pid}/fdinfo")
    try:
        fdinfos = list(fdinfo_dir.iterdir())
    except OSError:
        return {
            "gpuMemoryKB": 0,
            "gpuResidentKB": 0,
            "gpuSharedKB": 0,
        }

    fdinfo_texts = []
    for fdinfo in fdinfos:
        try:
            fdinfo_texts.append(fdinfo.read_text(errors="ignore"))
        except OSError:
            continue

    return read_gpu_metrics_from_fdinfo_texts(fdinfo_texts)


def run_self_test() -> int:
    i915_metrics = read_gpu_metrics_from_fdinfo_texts([
        """drm-driver:\ti915
drm-total-system0:\t1351748 KiB
drm-shared-system0:\t246 MiB
drm-resident-system0:\t872580 KiB
drm-total-stolen-system0:\t0
drm-shared-stolen-system0:\t0
drm-resident-stolen-system0:\t0
"""
    ])
    assert i915_metrics == {
        "gpuMemoryKB": 1351748,
        "gpuResidentKB": 872580,
        "gpuSharedKB": 251904,
    }, i915_metrics

    amdgpu_metrics = read_gpu_metrics_from_fdinfo_texts([
        """drm-driver:\tamdgpu
drm-memory-vram:\t128 MiB
drm-memory-gtt:\t64 MiB
drm-shared-vram:\t16 MiB
drm-shared-gtt:\t4 MiB
"""
    ])
    assert amdgpu_metrics == {
        "gpuMemoryKB": 196608,
        "gpuResidentKB": 196608,
        "gpuSharedKB": 20480,
    }, amdgpu_metrics

    mixed_amdgpu_metrics = read_gpu_metrics_from_fdinfo_texts([
        """drm-driver:\tamdgpu
drm-total-vram:\t300 MiB
drm-resident-vram:\t240 MiB
drm-shared-vram:\t32 MiB
drm-total-gtt:\t100 MiB
drm-resident-gtt:\t80 MiB
drm-shared-gtt:\t8 MiB
"""
    ])
    assert mixed_amdgpu_metrics == {
        "gpuMemoryKB": 409600,
        "gpuResidentKB": 327680,
        "gpuSharedKB": 40960,
    }, mixed_amdgpu_metrics

    print("ok")
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return run_self_test()

    pids = []
    for arg in sys.argv[1:]:
        for part in arg.split(","):
            part = part.strip()
            if part.isdigit():
                pids.append(part)

    result = {}
    for pid in dict.fromkeys(pids):
        metrics = read_gpu_metrics(pid)
        metrics["swapKB"] = read_swap_kib(pid)
        result[pid] = metrics

    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
