#!/usr/bin/env python3
import json
from pathlib import Path


CPU_ROOT = Path("/sys/devices/system/cpu")


def read_text(path: Path) -> str:
    try:
        return path.read_text().strip()
    except OSError:
        return ""


def read_int(path: Path) -> int:
    value = read_text(path)
    try:
        return int(value)
    except ValueError:
        return 0


def mhz_from_khz(value: int) -> int:
    return round(value / 1000) if value > 0 else 0


def cpu_dirs():
    return sorted(
        [p for p in CPU_ROOT.glob("cpu[0-9]*") if p.is_dir()],
        key=lambda p: int(p.name[3:]),
    )


cores = []
for cpu in cpu_dirs():
    cpufreq = cpu / "cpufreq"
    if not cpufreq.exists():
        continue
    idx = int(cpu.name[3:])
    cur_mhz = mhz_from_khz(read_int(cpufreq / "scaling_cur_freq"))
    cores.append({"index": idx, "mhz": cur_mhz})

freqs = [core["mhz"] for core in cores if core["mhz"] > 0]

first_cpufreq = next((cpu / "cpufreq" for cpu in cpu_dirs() if (cpu / "cpufreq").exists()), None)
epp = ""
epp_available = []
governor = ""
governors_available = []
limit_min_mhz = 0
limit_max_mhz = 0

if first_cpufreq:
    epp = read_text(first_cpufreq / "energy_performance_preference")
    epp_available = read_text(first_cpufreq / "energy_performance_available_preferences").split()
    governor = read_text(first_cpufreq / "scaling_governor")
    governors_available = read_text(first_cpufreq / "scaling_available_governors").split()
    limit_min_mhz = mhz_from_khz(read_int(first_cpufreq / "scaling_min_freq"))
    limit_max_mhz = mhz_from_khz(read_int(first_cpufreq / "scaling_max_freq"))

print(json.dumps({
    "avg_mhz": round(sum(freqs) / len(freqs)) if freqs else 0,
    "max_mhz": max(freqs) if freqs else 0,
    "epp": epp,
    "epp_available": epp_available,
    "governor": governor,
    "governors_available": governors_available,
    "limit_min_mhz": limit_min_mhz,
    "limit_max_mhz": limit_max_mhz,
    "cores": cores,
}))
