# Python Typer Wrapper (Post-v1)

This is an optional orchestration wrapper for `collect-endpoint-evidence.ps1`.

## Install

```bash
pip install typer
```

## Usage

```bash
python wrapper/python/eec_wrapper.py run --case-id INC-10492 --output-dir ./out
python wrapper/python/eec_wrapper.py run --dry-run --include system,network
python wrapper/python/eec_wrapper.py cleanup --output-dir ./out --retention-days 7
```

Notes:
- The wrapper shells out to `pwsh`/`powershell`.
- It does not replace PowerShell collector logic.
