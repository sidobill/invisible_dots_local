# Runs invisible_dots with a local model (Ollama) instead of OpenRouter.
# Use:  powershell -ExecutionPolicy Bypass -File .\local-model.ps1 [model]    (default model: qwen3:8b)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$model = if ($args.Count -gt 0) { $args[0] } else { "qwen3:8b" }

$ollama = (Get-Command ollama -ErrorAction SilentlyContinue).Source
if (-not $ollama) { $ollama = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe" }
if (-not (Test-Path $ollama)) {
  winget install -e --id Ollama.Ollama
  $ollama = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
  if (-not (Test-Path $ollama)) { throw "ollama.exe not found; open a new terminal and run again" }
}

# The Dot's prompt is large: Ollama's default window is too small. 32768 matches the engine patch.
[Environment]::SetEnvironmentVariable("OLLAMA_CONTEXT_LENGTH", "32768", "User")
$env:OLLAMA_CONTEXT_LENGTH = "32768"

Write-Host "Restarting Ollama with a 32k context..."
Get-Process -Name "ollama*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 2
Start-Process -FilePath $ollama -ArgumentList "serve" -WindowStyle Hidden
function Test-Ollama { try { Invoke-RestMethod http://127.0.0.1:11434/api/version -TimeoutSec 2 | Out-Null; $true } catch { $false } }
for ($i = 0; $i -lt 30 -and -not (Test-Ollama); $i++) { Start-Sleep 1 }
if (-not (Test-Ollama)) { throw "Ollama did not start on 127.0.0.1:11434" }

& $ollama pull $model
if ($LASTEXITCODE -ne 0) { throw "ollama pull failed" }

Write-Host "Rebuilding the CLI and the runtime image (picks up the local-model patches)..."
npm run build --workspace @invisible-dots/cli
if ($LASTEXITCODE -ne 0) { throw "CLI build failed" }
node apps/cli/dist/invisible-dots.mjs image build
if ($LASTEXITCODE -ne 0) { throw "image build failed" }

$env:INVISIBLE_DOTS_LOCAL_MODEL = "1"
Write-Host ""
Write-Host "Server starting. Set the Dot's model.id to $model, then restart the Dot's computer so it boots the new image."
node apps/cli/dist/invisible-dots.mjs server
