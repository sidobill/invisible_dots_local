# Runs invisible_dots with a local model (Ollama) instead of OpenRouter.
# Use:  powershell -ExecutionPolicy Bypass -File .\local-model.ps1 [model] [context]
#   default: qwen3:8b with 40960 tokens (the most qwen3:8b supports)
#   example: .\local-model.ps1 llama3.1:8b 65536
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$model = if ($args.Count -gt 0) { $args[0] } else { "qwen3:8b" }
$context = if ($args.Count -gt 1) { $args[1] } else { "40960" }

$ollama = (Get-Command ollama -ErrorAction SilentlyContinue).Source
if (-not $ollama) { $ollama = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe" }
if (-not (Test-Path $ollama)) {
  winget install -e --id Ollama.Ollama
  $ollama = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
  if (-not (Test-Path $ollama)) { throw "ollama.exe not found; open a new terminal and run again" }
}

# The Dot's prompt and the web pages it reads are large. The engine reads the window Ollama loads the model
# with, so this is the only place to change it. Flash attention and an 8-bit KV cache halve the memory it takes.
foreach ($pair in @(@("OLLAMA_CONTEXT_LENGTH", $context), @("OLLAMA_FLASH_ATTENTION", "1"), @("OLLAMA_KV_CACHE_TYPE", "q8_0"))) {
  [Environment]::SetEnvironmentVariable($pair[0], $pair[1], "User")
  Set-Item -Path "Env:$($pair[0])" -Value $pair[1]
}

Write-Host "Restarting Ollama with a $context-token context..."
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
