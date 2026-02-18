#!/usr/bin/env python3
"""Post-v1 Typer wrapper for endpoint-evidence-collector.

This wrapper is optional and intended for orchestration parity across platforms.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import List, Optional

import typer

app = typer.Typer(help="Cross-platform wrapper for endpoint-evidence-collector")


def _resolve_powershell() -> str:
    for candidate in ("pwsh", "powershell"):
        if shutil.which(candidate):
            return candidate
    raise typer.BadParameter("Neither 'pwsh' nor 'powershell' was found on PATH.")


def _script_path() -> Path:
    repo_root = Path(__file__).resolve().parents[2]
    script = repo_root / "collect-endpoint-evidence.ps1"
    if not script.exists():
        raise typer.BadParameter(f"Script not found: {script}")
    return script


def _run(cmd: List[str]) -> int:
    proc = subprocess.run(cmd, check=False)
    return proc.returncode


@app.command("run")
def run_collection(
    case_id: Optional[str] = typer.Option(None, "--case-id", help="Case/incident identifier"),
    ticket_id: Optional[str] = typer.Option(None, "--ticket-id", help="Ticket identifier"),
    output_dir: str = typer.Option("./out", "--output-dir", help="Output directory root"),
    redaction_level: str = typer.Option("standard", "--redaction-level", help="standard|strict"),
    include: Optional[str] = typer.Option(None, "--include", help="Comma-separated collectors"),
    exclude: Optional[str] = typer.Option(None, "--exclude", help="Comma-separated collectors"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Plan only; no collection"),
    retention_days: int = typer.Option(7, "--retention-days", help="Retention period in days"),
) -> None:
    """Run the PowerShell collector script through a Python Typer interface."""
    ps = _resolve_powershell()
    script = _script_path()

    cmd = [ps, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)]
    if case_id:
        cmd += ["-CaseId", case_id]
    if ticket_id:
        cmd += ["-TicketId", ticket_id]
    cmd += ["-OutputDir", output_dir, "-RedactionLevel", redaction_level, "-RetentionDays", str(retention_days)]

    if include:
        cmd += ["-Include", *[item.strip() for item in include.split(",") if item.strip()]]
    if exclude:
        cmd += ["-Exclude", *[item.strip() for item in exclude.split(",") if item.strip()]]
    if dry_run:
        cmd.append("-DryRun")

    raise typer.Exit(code=_run(cmd))


@app.command("cleanup")
def cleanup(
    output_dir: str = typer.Option("./out", "--output-dir", help="Output directory root"),
    retention_days: int = typer.Option(7, "--retention-days", help="Retention period in days"),
) -> None:
    """Run retention cleanup only."""
    ps = _resolve_powershell()
    script = _script_path()

    cmd = [
        ps,
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
        "-OutputDir",
        output_dir,
        "-RetentionDays",
        str(retention_days),
        "-RetentionCleanupOnly",
    ]
    raise typer.Exit(code=_run(cmd))


if __name__ == "__main__":
    app()
