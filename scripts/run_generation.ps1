# Run Generation Agent
# Usage:
#   .\scripts\run_generation.ps1
#   .\scripts\run_generation.ps1 -ProblemFile "data/modrep/modrep.md"
#   .\scripts\run_generation.ps1 -ProblemFile "data/example.md" -MaxIterations 15

param(
    [string]$ProblemFile = "data/example.md",
    [int]$MaxIterations = 10,
    [string]$Model = "Kimi-K2.6",
    [string]$Effort = "xhigh",
    [switch]$RequireVerification = $true
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
if (-not $scriptDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
$genDir = Join-Path $repoRoot "agents\generation"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Rethlas-claude Generation Agent" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check virtual environment
$venvPath = Join-Path $genDir ".venv"
if (-not (Test-Path $venvPath)) {
    Write-Error "Virtual environment not found at $venvPath"
    Write-Host "Please create it first:" -ForegroundColor Yellow
    Write-Host "  cd agents\generation" -ForegroundColor Yellow
    Write-Host "  python -m venv .venv" -ForegroundColor Yellow
    Write-Host "  .venv\Scripts\activate" -ForegroundColor Yellow
    Write-Host "  pip install -r mcp\requirements.txt" -ForegroundColor Yellow
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

# Validate problem file
$problemPath = Join-Path $genDir $ProblemFile
if (-not (Test-Path $problemPath)) {
    Write-Error "Problem file not found: $problemPath"
    exit 1
}

# Compute problem_id
$problemRel = $ProblemFile -replace '^data/', ''
$problemRel = $problemRel -replace '\.md$',''
$problemId = Split-Path $problemRel -Leaf

# Check reference directory
$refDir = Join-Path $genDir "data\$problemRel.refs"
$refPrompt = ""
if (Test-Path $refDir) {
    $refPrompt = "Use reference_dir=data/$problemRel.refs if it exists."
    Write-Host "Found reference directory: data/$problemRel.refs" -ForegroundColor Green
}

# Create log directory
$logDir = Join-Path $genDir "logs\$problemRel"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "$problemId.md"

# Check Verification Service
$verifyUrl = "http://127.0.0.1:8091/health"
$healthOutput = curl.exe -s $verifyUrl 2>$null
if ($healthOutput -match '"status"\s*:\s*"ok"') {
    Write-Host "Verification service is running" -ForegroundColor Green
    $runMode = "verified"
} else {
    if ($RequireVerification) {
        Write-Error "Verification service not reachable at http://127.0.0.1:8091"
        Write-Host "Please start it first: .\scripts\start_verification.ps1" -ForegroundColor Yellow
        exit 1
    } else {
        Write-Warning "Verification service not reachable. Running in EXPLORATORY mode."
        $runMode = "exploratory"
    }
}

# Build prompt
$prompt = "Use CLAUDE.md exactly to solve the math problem in $ProblemFile. Use problem_id=$problemRel. run_mode=$runMode. mode_ceiling=verification. $refPrompt"

# Validate model name - claude CLI only accepts known Anthropic model names
# If using a proxy with custom model names, the proxy maps Anthropic names to actual models
$validModels = @('claude-opus-4-8','claude-opus-5','claude-sonnet-4-8','claude-sonnet-5','claude-fable-5','claude-haiku-4-5','claude-haiku-4-5-20251001')
$cliModel = $Model
if ($validModels -notcontains $Model) {
    # Model is not a valid Anthropic model name (e.g., proxy model like Kimi-K2.6)
    # Use a valid Anthropic model name - the proxy will map it to the actual model
    $cliModel = 'claude-opus-4-8'
    Write-Host "Note: Model '$Model' is not a native Anthropic model name." -ForegroundColor Yellow
    Write-Host "      Using '$cliModel' for claude CLI (proxy will map to actual model)." -ForegroundColor Yellow
    Write-Host ""
}

# Show configuration
Write-Host ""
Write-Host "Run Configuration:" -ForegroundColor Cyan
Write-Host "  Model:        $Model (CLI: $cliModel)"
Write-Host "  Effort:       $Effort"
Write-Host "  Problem:      $ProblemFile"
Write-Host "  Problem ID:   $problemRel"
Write-Host "  Run Mode:     $runMode"
Write-Host "  Log:          $logFile"
Write-Host ""

# Record start time
$startTime = Get-Date

# Run Generation Agent
Write-Host "Starting Generation Agent..." -ForegroundColor Green
Write-Host "This may take a long time. Press Ctrl+C to interrupt." -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

cd $genDir

# Execute and capture output - pass arguments directly to avoid array expansion issues
$claudeRc = 0
try {
    $output = & claude -p $prompt --model $cliModel --effort $Effort --dangerously-skip-permissions 2>&1
    $claudeRc = $LASTEXITCODE
    $output | Out-File -FilePath $logFile -Encoding UTF8
    $output | ForEach-Object { Write-Host $_ }
} catch {
    Write-Error "Failed to run claude: $_"
    exit 1
}

# Record end time
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($claudeRc -ne 0) {
    Write-Host " claude exited with code $claudeRc" -ForegroundColor Red
}
Write-Host " Finished $ProblemFile" -ForegroundColor Green
Write-Host " Total time: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Green
Write-Host ""
Write-Host "Results:" -ForegroundColor Cyan

# Check result files
$resultsDir = Join-Path $genDir "results\$problemRel"
$blueprintFile = Join-Path $resultsDir "blueprint.md"
$verifiedFile = Join-Path $resultsDir "blueprint_verified.md"

if (Test-Path $verifiedFile) {
    Write-Host "  VERIFIED: $verifiedFile" -ForegroundColor Green
} elseif (Test-Path $blueprintFile) {
    Write-Host "  Draft: $blueprintFile" -ForegroundColor Yellow
    Write-Host "  Verification may still be in progress..." -ForegroundColor Cyan
} else {
    Write-Host "  No output found in $resultsDir" -ForegroundColor Red
}

Write-Host ""
Write-Host "To view results in the browser:" -ForegroundColor Cyan
Write-Host "  1. Install Zola: https://www.getzola.org/documentation/getting-started/installation/" -ForegroundColor White
Write-Host "  2. cd agents\generation" -ForegroundColor White
Write-Host "  3. bash site\serve.sh" -ForegroundColor White
Write-Host "  4. Open http://localhost:3264" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
