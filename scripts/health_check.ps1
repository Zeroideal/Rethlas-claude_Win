# One-click health check
# Usage: .\scripts\health_check.ps1

$ErrorActionPreference = "SilentlyContinue"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Rethlas-claude Windows Health Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$allOk = $true

# 1. Check Python
Write-Host "`n[1/8] Checking Python..." -ForegroundColor Yellow
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCmd) {
    $pythonVersion = & python --version 2>&1
    Write-Host "  OK: $pythonVersion" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Python not found in PATH" -ForegroundColor Red
    $allOk = $false
}

# 2. Check Node.js / npm
Write-Host "`n[2/8] Checking Node.js and npm..." -ForegroundColor Yellow
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($nodeCmd -and $npmCmd) {
    $nodeVersion = & node --version 2>&1
    $npmVersion = & npm --version 2>&1
    Write-Host "  OK: Node $nodeVersion, npm $npmVersion" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Node.js/npm not found" -ForegroundColor Red
    $allOk = $false
}

# 3. Check Claude Code CLI
Write-Host "`n[3/8] Checking Claude Code CLI..." -ForegroundColor Yellow
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    $claudeVersion = & claude --version 2>&1
    Write-Host "  OK: Claude Code $claudeVersion" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Claude Code CLI not found." -ForegroundColor Red
    Write-Host "       Install: npm install -g @anthropic-ai/claude-code" -ForegroundColor Yellow
    $allOk = $false
}

# 4. Check virtual environments
Write-Host "`n[4/8] Checking virtual environments..." -ForegroundColor Yellow
$genVenv = Join-Path $repoRoot "agents\generation\.venv"
$verVenv = Join-Path $repoRoot "agents\verification\.venv"

if (Test-Path $genVenv) {
    Write-Host "  OK: Generation venv exists" -ForegroundColor Green
} else {
    Write-Host "  MISSING: Generation venv not found" -ForegroundColor Red
    $allOk = $false
}

if (Test-Path $verVenv) {
    Write-Host "  OK: Verification venv exists" -ForegroundColor Green
} else {
    Write-Host "  MISSING: Verification venv not found" -ForegroundColor Red
    $allOk = $false
}

# 5. Check .env file
Write-Host "`n[5/8] Checking .env configuration..." -ForegroundColor Yellow
$envFile = Join-Path $repoRoot ".env"
if (Test-Path $envFile) {
    Write-Host "  OK: .env file exists" -ForegroundColor Green
    $envContent = [System.IO.File]::ReadAllText($envFile)
    if ($envContent -match 'ANTHROPIC_API_KEY\s*=\s*([^\s#]+)') {
        $keyValue = $matches[1]
        if ($keyValue -and $keyValue -ne 'your-api-key-here') {
            Write-Host "  OK: ANTHROPIC_API_KEY is set" -ForegroundColor Green
        } else {
            Write-Host "  WARNING: ANTHROPIC_API_KEY is placeholder" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  WARNING: ANTHROPIC_API_KEY not found in .env" -ForegroundColor Yellow
    }

    if ($envContent -match 'ANTHROPIC_BASE_URL\s*=\s*[^\s#]+') {
        Write-Host "  OK: ANTHROPIC_BASE_URL is set" -ForegroundColor Green
    } else {
        Write-Host "  INFO: ANTHROPIC_BASE_URL not set" -ForegroundColor Cyan
    }
} else {
    Write-Host "  MISSING: .env file not found" -ForegroundColor Red
    $allOk = $false
}

# 6. Check Verification Service
Write-Host "`n[6/8] Checking Verification Service..." -ForegroundColor Yellow
$verifyPort = if ($env:VERIFY_PORT) { $env:VERIFY_PORT } else { "8091" }
$healthOutput = curl.exe -s "http://127.0.0.1:$verifyPort/health" 2>$null
if ($healthOutput -match '"status"\s*:\s*"ok"') {
    Write-Host "  OK: Verification service running on port $verifyPort" -ForegroundColor Green
} elseif ($healthOutput) {
    Write-Host "  WARNING: Verification service responded but status not OK" -ForegroundColor Yellow
} else {
    Write-Host "  INFO: Verification service not running on port $verifyPort" -ForegroundColor Cyan
    Write-Host "        Start it with: .\scripts\start_verification.ps1" -ForegroundColor Cyan
}

# 7. Check config files
Write-Host "`n[7/8] Checking configuration files..." -ForegroundColor Yellow
$genMcp = Join-Path $repoRoot "agents\generation\.mcp.json"
$verMcp = Join-Path $repoRoot "agents\verification\.mcp.json"

if (Test-Path $genMcp) {
    $content = Get-Content $genMcp -Raw
    if ($content -match '"command"\s*:\s*"python"') {
        Write-Host "  OK: Generation .mcp.json uses 'python'" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Generation .mcp.json may use 'python3'" -ForegroundColor Yellow
    }
} else {
    Write-Host "  FAIL: Generation .mcp.json not found" -ForegroundColor Red
    $allOk = $false
}

if (Test-Path $verMcp) {
    $content = Get-Content $verMcp -Raw
    if ($content -match '"command"\s*:\s*"python"') {
        Write-Host "  OK: Verification .mcp.json uses 'python'" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Verification .mcp.json may use 'python3'" -ForegroundColor Yellow
    }
} else {
    Write-Host "  FAIL: Verification .mcp.json not found" -ForegroundColor Red
    $allOk = $false
}

# 8. Check example problem
Write-Host "`n[8/8] Checking example problem..." -ForegroundColor Yellow
$exampleFile = Join-Path $repoRoot "agents\generation\data\example.md"
if (Test-Path $exampleFile) {
    Write-Host "  OK: Example problem exists" -ForegroundColor Green
} else {
    Write-Host "  WARNING: Example problem not found" -ForegroundColor Yellow
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
if ($allOk) {
    Write-Host " All critical checks passed!" -ForegroundColor Green
    Write-Host " You are ready to run Rethlas-claude." -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor Cyan
    Write-Host "  1. Start Verification Service:" -ForegroundColor White
    Write-Host "     .\scripts\start_verification.ps1" -ForegroundColor Yellow
    Write-Host "  2. In another terminal, run Generation:" -ForegroundColor White
    Write-Host "     .\scripts\run_generation.ps1" -ForegroundColor Yellow
} else {
    Write-Host " Some checks failed. Please fix the issues above." -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
