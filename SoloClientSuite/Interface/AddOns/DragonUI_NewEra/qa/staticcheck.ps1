# DragonUI_NewEra/qa/staticcheck.ps1  (owner: QA/Harness Engineer)  -- CONTRACTS.md #5
#
# PowerShell port of staticcheck.sh, for Windows machines without bash. Same checks, same
# semantics, same exit codes. It:
#   1. luac -p (Lua 5.1) every .lua under the addon, if luac exists on PATH.
#   2. Verifies every file listed in DragonUI_NewEra.toc exists on disk.
#   3. Greps the .lua for known 3.3.5a runtime traps and reports file:line:
#        - SetShown(
#        - :SetMask(
#        - ScrollBox
#        - CreateFrame(... "FauxScrollFrameTemplate" ...) WITHOUT a name argument
#        - C_<Namespace>. usages cross-checked against compat/COVERAGE.md
#   4. Exits non-zero with a FAIL banner if a TOC file is missing or luac fails;
#      otherwise prints PASS. Trap hits are advisory (warnings), not fatal,
#      EXCEPT they do not flip the exit code by themselves.
#
# Runnable from anywhere: it cd's to the addon dir based on this script's location.
#   powershell -File qa\staticcheck.ps1
#   pwsh qa/staticcheck.ps1
#
# NOTE: keep this file plain ASCII. Windows PowerShell 5.1 reads .ps1 files without a UTF-8
# BOM using the legacy ANSI codepage, so any em-dash / smart-quote / section-sign character
# silently mangles into multi-byte garbage and can corrupt string literals later in the file.

[CmdletBinding()]
param()

# --- locate the addon root (parent of this script's qa/ dir) -----------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AddonDir  = Split-Path -Parent $ScriptDir
Set-Location -LiteralPath $AddonDir

$Toc      = "DragonUI_NewEra.toc"
$Coverage = "compat/COVERAGE.md"

$script:Fail      = $false   # flips to $true on any fatal condition (missing TOC file / luac error)
$script:WarnCount = 0

function Section([string]$Text) { Write-Host "== $Text ==" -ForegroundColor Cyan }
function Warn([string]$Text)    { Write-Host "WARN: $Text" -ForegroundColor Yellow; $script:WarnCount++ }
function Err([string]$Text)     { Write-Host "FAIL: $Text" -ForegroundColor Red;    $script:Fail = $true }
function Ok([string]$Text)      { Write-Host "ok: $Text" -ForegroundColor Green }

# Path relative to the addon root, forward-slashed (matches the bash script's normalization).
# [System.IO.Path]::GetRelativePath isn't available on the .NET Framework build Windows
# PowerShell 5.1 ships with, so do it manually (every file here is always under $AddonDir).
function RelPath([string]$FullPath) {
    $rel = $FullPath
    if ($FullPath.StartsWith($AddonDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $rel = $FullPath.Substring($AddonDir.Length).TrimStart('\', '/')
    }
    return ($rel -replace '\\', '/')
}

Write-Host "DragonUI_NewEra static check (addon: $AddonDir)"
Write-Host ""

# Collect all .lua files in the addon.
$LuaFileInfos = @(Get-ChildItem -LiteralPath $AddonDir -Recurse -File -Filter '*.lua' | Sort-Object FullName)
$LuaFiles = @($LuaFileInfos | ForEach-Object { RelPath $_.FullName })

# =============================================================================
# 1. luac -p syntax pass
# =============================================================================
Section "1. Lua 5.1 syntax (luac -p)"
$Luac = $null
foreach ($cand in @('luac5.1', 'luac')) {
    $cmd = Get-Command $cand -ErrorAction SilentlyContinue
    if ($cmd) { $Luac = $cmd.Source; break }
}

if (-not $Luac) {
    Write-Host "luac not found - skipping syntax pass." -ForegroundColor Yellow
} else {
    $luacVerRaw = (& $Luac -v 2>&1 | Select-Object -First 1)
    Write-Host "using $Luac ($luacVerRaw)"
    if ($LuaFiles.Count -eq 0) {
        Warn "no .lua files found to compile"
    } else {
        foreach ($f in $LuaFiles) {
            $output = & $Luac -p $f 2>&1
            if ($LASTEXITCODE -eq 0) {
                Ok $f
            } else {
                Err $f
                $output | ForEach-Object { Write-Host "      $_" }
            }
        }
    }
}
Write-Host ""

# =============================================================================
# 2. TOC file manifest
# =============================================================================
Section "2. TOC file manifest"
if (-not (Test-Path -LiteralPath $Toc)) {
    Err "TOC not found: $Toc"
} else {
    foreach ($raw in Get-Content -LiteralPath $Toc) {
        $line = $raw.Trim()
        if ([string]::IsNullOrEmpty($line)) { continue }
        if ($line.StartsWith('#')) { continue }              # comment (also covers ## metadata)
        # Only treat lines that look like file references (have a known extension).
        if ($line -notmatch '\.(lua|xml|toc)$') { continue }
        $rel = $line -replace '\\', '/'
        if (Test-Path -LiteralPath $rel) {
            Ok $rel
        } else {
            Err "TOC lists missing file: $rel"
        }
    }
}
Write-Host ""

# =============================================================================
# 3. Known 3.3.5a runtime traps
# =============================================================================
Section "3. 3.3.5a runtime trap grep"

function TrapGrep {
    param([string]$Label, [string]$Pattern)
    if ($LuaFileInfos.Count -eq 0) { return }
    # -CaseSensitive: bash's `grep -E` (no -i) is case-sensitive by default; PowerShell's
    # Select-String/-match are case-INSENSITIVE by default, which over-matches things like the
    # lowercase local `setShown(obj, on)` helper functions the bash version would never flag.
    $hits = @(
        Select-String -LiteralPath $LuaFileInfos.FullName -Pattern $Pattern -CaseSensitive |
            ForEach-Object { "$(RelPath $_.Path):$($_.LineNumber):$($_.Line.Trim())" }
    )
    if ($hits.Count -gt 0) {
        Write-Host "${Label}:" -ForegroundColor Yellow
        $hits | ForEach-Object { Write-Host "    $_" }
        $script:WarnCount += $hits.Count
    } else {
        Ok "no $Label hits"
    }
}

TrapGrep -Label 'SetShown(' -Pattern 'SetShown\s*\('
TrapGrep -Label ':SetMask(' -Pattern ':SetMask\s*\('
TrapGrep -Label 'ScrollBox' -Pattern 'ScrollBox'

# --- Unnamed FauxScrollFrameTemplate CreateFrame calls -----------------------
# A correct 3.3.5 call passes a name: CreateFrame("ScrollFrame", "MyName", parent, "FauxScrollFrameTemplate")
# The trap is a nil name: CreateFrame("ScrollFrame", nil, parent, "FauxScrollFrameTemplate")
# We flag any CreateFrame(...) line mentioning FauxScrollFrameTemplate whose 2nd arg is nil/""/''.
function SectionFaux {
    if ($LuaFileInfos.Count -eq 0) { return }
    $nilNamePattern = 'CreateFrame\s*\([^,]*,\s*(nil|""|' + "''" + ')\s*,'
    # -cmatch (case-sensitive) for the same reason TrapGrep uses -CaseSensitive above.
    $hits = @(
        Select-String -LiteralPath $LuaFileInfos.FullName -Pattern 'CreateFrame\s*\(' -CaseSensitive |
            Where-Object { $_.Line -cmatch 'FauxScrollFrameTemplate' } |
            Where-Object { $_.Line -cmatch $nilNamePattern } |
            ForEach-Object { "$(RelPath $_.Path):$($_.LineNumber):$($_.Line.Trim())" }
    )
    if ($hits.Count -gt 0) {
        Write-Host "unnamed FauxScrollFrameTemplate CreateFrame (must be NAMED):" -ForegroundColor Yellow
        $hits | ForEach-Object { Write-Host "    $_" }
        $script:WarnCount += $hits.Count
    } else {
        Ok "no unnamed FauxScrollFrameTemplate CreateFrame"
    }
}
SectionFaux
Write-Host ""

# =============================================================================
# 3b. C_* usage vs compat/COVERAGE.md
# =============================================================================
Section "3b. C_* symbols vs $Coverage"
if ($LuaFileInfos.Count -eq 0) {
    Warn "no .lua files to scan for C_* symbols"
} else {
    $symbols = @(
        Select-String -LiteralPath $LuaFileInfos.FullName -Pattern 'C_[A-Za-z]+\.' -AllMatches -CaseSensitive |
            ForEach-Object { $_.Matches } |
            ForEach-Object { $_.Value.TrimEnd('.') } |
            Sort-Object -Unique
    )
    if ($symbols.Count -eq 0) {
        Ok "no C_* usages found"
    } elseif (-not (Test-Path -LiteralPath $Coverage)) {
        Warn "$Coverage not present yet -- cannot cross-check. C_* namespaces in use:"
        $symbols | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-Host "cross-checking against $Coverage ..."
        $coverageText = Get-Content -LiteralPath $Coverage -Raw
        foreach ($sym in $symbols) {
            if ($coverageText.Contains($sym)) {
                Ok "$sym (covered)"
            } else {
                Warn "C_ symbol NOT in COVERAGE.md: $sym"
            }
        }
    }
}
Write-Host ""

# =============================================================================
# Final banner
# =============================================================================
Write-Host "------------------------------------------------------------"
if ($script:Fail) {
    Write-Host "#### STATIC CHECK: FAIL ####  (missing TOC file or luac error above)" -ForegroundColor Red
    if ($script:WarnCount -gt 0) {
        Write-Host "($($script:WarnCount) advisory warning(s) also reported)" -ForegroundColor Yellow
    }
    exit 1
} else {
    if ($script:WarnCount -gt 0) {
        Write-Host "#### STATIC CHECK: PASS ####  with $($script:WarnCount) advisory warning(s)" -ForegroundColor Green
    } else {
        Write-Host "#### STATIC CHECK: PASS ####  (clean)" -ForegroundColor Green
    }
    exit 0
}
