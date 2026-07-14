#Requires -Version 5.1
<#
.SYNOPSIS
    Valida la configuracion Terraform del proyecto podman-ecommerce.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$script:Passed = 0
$script:Failed = 0
$script:Warnings = 0

$TfDir = $PSScriptRoot

function Write-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = "")
    if ($Ok) {
        Write-Host "  PASS  $Name" -ForegroundColor Green
        $script:Passed++
    } else {
        Write-Host "  FAIL  $Name -- $Detail" -ForegroundColor Red
        $script:Failed++
    }
}

function Write-Warn {
    param([string]$Name, [string]$Detail = "")
    Write-Host "  WARN  $Name -- $Detail" -ForegroundColor Yellow
    $script:Warnings++
}

function Has-Pattern {
    param([string]$Content, [string]$Pattern)
    return [regex]::IsMatch($Content, $Pattern)
}

# -----------------------------------------------------------
Write-Host "`n=== Terraform Validation ===" -ForegroundColor Cyan

# 1. Archivos
Write-Host "`n[1/5] Archivos requeridos" -ForegroundColor White

foreach ($file in @("main.tf", "variables.tf", "outputs.tf", "providers.tf")) {
    Write-Result "File: $file" (Test-Path (Join-Path $TfDir $file)) "not found"
}

foreach ($file in @("terraform.tfvars.example", "scripts/setup.sh")) {
    $p = Join-Path $TfDir $file
    if (Test-Path $p) { Write-Result "Optional: $file" $true }
    else { Write-Warn "Optional: $file" "not found" }
}

# 2. Sintaxis HCL
Write-Host "`n[2/5] Sintaxis HCL" -ForegroundColor White

foreach ($file in @("main.tf", "variables.tf", "outputs.tf", "providers.tf")) {
    $path = Join-Path $TfDir $file
    if (-not (Test-Path $path)) { continue }
    $c = Get-Content $path -Raw
    $ob = ([regex]::Matches($c, '\{')).Count
    $cb = ([regex]::Matches($c, '\}')).Count
    $os = ([regex]::Matches($c, '\[')).Count
    $cs = ([regex]::Matches($c, '\]')).Count
    Write-Result "$file braces" ($ob -eq $cb) "open=$ob close=$cb"
    Write-Result "$file brackets" ($os -eq $cs) "open=$os close=$cs"
}

# 3. Variables
Write-Host "`n[3/5] Variables" -ForegroundColor White

$varsPath = Join-Path $TfDir "variables.tf"
if (Test-Path $varsPath) {
    $vc = Get-Content $varsPath -Raw
    Write-Result "db_password defined" (Has-Pattern $vc 'variable\s+"db_password"') "missing"
    Write-Result "sensitive=true present" (Has-Pattern $vc 'sensitive\s*=\s*true') "db_password should be sensitive"

    $blocks = [regex]::Matches($vc, 'variable\s+"(\w+)"[^}]*}')
    foreach ($m in $blocks) {
        $n = $m.Groups[1].Value
        if (-not (Has-Pattern $m.Value 'description\s*=')) {
            Write-Warn "Var '$n'" "missing description"
        }
    }
}

# 4. Recursos
Write-Host "`n[4/5] Recursos" -ForegroundColor White

$mainPath = Join-Path $TfDir "main.tf"
if (Test-Path $mainPath) {
    $m = Get-Content $mainPath -Raw

    foreach ($res in @(
        "azurerm_resource_group",
        "azurerm_virtual_network",
        "azurerm_subnet",
        "azurerm_public_ip",
        "azurerm_network_security_group",
        "azurerm_linux_virtual_machine"
    )) {
        $pat = 'resource\s+"' + $res + '"'
        Write-Result "Resource: $res" (Has-Pattern $m $pat) "not found"
    }

    foreach ($port in @("22", "80", "443", "9090")) {
        $pat = 'destination_port_range\s*=\s*"' + $port + '"'
        Write-Result "NSG port $port" (Has-Pattern $m $pat) "missing rule"
    }

    Write-Result "VM custom_data" (Has-Pattern $m 'custom_data') "VM wont auto-configure"
}

# 5. terraform validate
Write-Host "`n[5/5] terraform validate" -ForegroundColor White

$tfOk = $false
try { $null = & terraform version 2>$null; $tfOk = $true } catch {}

if ($tfOk) {
    try {
        Push-Location $TfDir
        $null = & terraform init -backend=false 2>&1
        $r = & terraform validate 2>&1
        $e = $LASTEXITCODE
        Pop-Location
        Write-Result "terraform validate" ($e -eq 0) "$r"
    } catch {
        Pop-Location
        Write-Result "terraform validate" $false $_.Exception.Message
    }
} else {
    Write-Warn "terraform" "not installed -- skipping"
}

# -----------------------------------------------------------
Write-Host "`n=== Resultado ===" -ForegroundColor Cyan
Write-Host "  Passed:   $($script:Passed)" -ForegroundColor Green
Write-Host "  Failed:   $($script:Failed)" -ForegroundColor $(if ($script:Failed -gt 0) { "Red" } else { "Green" })
Write-Host "  Warnings: $($script:Warnings)" -ForegroundColor Yellow

if ($script:Failed -gt 0) {
    Write-Host "`nVALIDATION FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nVALIDATION PASSED" -ForegroundColor Green
    exit 0
}
