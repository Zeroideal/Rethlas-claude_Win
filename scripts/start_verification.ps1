# Start Verification Service
# Usage: .\scripts\start_verification.ps1

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
$verDir = Join-Path $repoRoot "agents\verification"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Starting Verification Service" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check virtual environment
$venvPath = Join-Path $verDir ".venv"
if (-not (Test-Path $venvPath)) {
    Write-Error "Virtual environment not found at $venvPath"
    Write-Host "Please create it first:" -ForegroundColor Yellow
    Write-Host "  cd agents\verification" -ForegroundColor Yellow
    Write-Host "  python -m venv .venv" -ForegroundColor Yellow
    Write-Host "  .venv\Scripts\activate" -ForegroundColor Yellow
    Write-Host "  pip install -r requirements.txt" -ForegroundColor Yellow
    exit 1
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Green
$activateScript = Join-Path $venvPath "Scripts\activate.ps1"
if (Test-Path $activateScript) {
    . $activateScript
} else {
    Write-Error "Activate script not found: $activateScript"
    exit 1
}

# Load .env file
$envFile = Join-Path $repoRoot ".env"
if (Test-Path $envFile) {
    Write-Host "Loading .env file..." -ForegroundColor Green
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            [Environment]::SetEnvironmentVariable($key, $value, "Process")
        }
    }
}

# Check dependencies
python -c "import fastapi, pydantic" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Dependencies OK" -ForegroundColor Green
} else {
    Write-Host "Installing dependencies..." -ForegroundColor Yellow
    pip install -r (Join-Path $verDir "requirements.txt")
}

# Check API Key
if (-not $env:ANTHROPIC_API_KEY) {
    Write-Warning "ANTHROPIC_API_KEY is not set. The verification agent needs it to call Claude Code."
    Write-Host "Set it via .env file or environment variable." -ForegroundColor Yellow
}

# Show configuration
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
$displayModel = if ($env:CLAUDE_MODEL) { $env:CLAUDE_MODEL } else { 'Kimi-K2.6 (default)' }
$displayEffort = if ($env:CLAUDE_EFFORT) { $env:CLAUDE_EFFORT } else { 'xhigh (default)' }
Write-Host "  Model:   $displayModel"
Write-Host "  Effort:  $displayEffort"
Write-Host "  Port:    8091"
Write-Host "  API Key: $(if ($env:ANTHROPIC_API_KEY) { 'Configured' } else { 'NOT SET' })"
Write-Host ""
Write-Host "Starting uvicorn on http://0.0.0.0:8091 ..." -ForegroundColor Green
Write-Host "Health check: http://127.0.0.1:8091/health" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

# Start service
cd $verDir
uvicorn api.server:app --host 0.0.0.0 --port 8091
