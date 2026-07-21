#!/usr/bin/env pwsh
# Fable statusline renderer — native Windows / PowerShell edition.
# Pure PowerShell (no bash, no python3) so the HUD works without Git Bash.
# Receives session JSON on stdin, prints the same two-line ANSI HUD as
# statusline.sh:
#   line 1: persona/level, model, branch, cost, duration, lines changed
#   line 2: context-window meter + usage-limit meters (5h / 7d, Pro/Max plans)
# Installed to ~/.claude/fable-mode/statusline.ps1 by scripts/install-statusline.ps1.
$ErrorActionPreference = 'SilentlyContinue'

# UTF-8 out so the emoji/box glyphs render (Windows PowerShell 5.1 defaults to
# cp1252 on stdout, which would mangle them).
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$raw = [Console]::In.ReadToEnd()
try { $d = $raw | ConvertFrom-Json } catch { [Console]::Out.Write('fable'); exit 0 }
if ($null -eq $d) { [Console]::Out.Write('fable'); exit 0 }

# Glyphs by code point: keeps this source pure-ASCII so PS 5.1's ANSI-by-default
# script reader can't corrupt them and no UTF-8 BOM is required.
$E    = [char]27
$BOLT = [char]0x26A1  # lightning
$BAR  = [char]0x2502  # box vertical (separator)
$PEN  = [char]0x270E  # pencil (state)
$NUL  = [char]0x2205  # empty set
$WYE  = [char]0x2387  # branch mark
$DOT  = [char]0x00B7  # middle dot
$FULL = [char]0x2588  # full block (meter fill)
$SHAD = [char]0x2591  # light shade (meter empty)
$CYC  = [char]0x27F3  # clockwise arrow (clear-worthy)
$RCY  = [char]0x21BB  # reset arrow
$MIN  = [char]0x2212  # minus sign

$DIM = "${E}[2m"
$RST = "${E}[0m"
function C([string]$code, [string]$s) { "${E}[${code}m${s}${RST}" }
$SEP = " ${DIM}${BAR}${RST} "

function Meter([double]$pct, [int]$width = 10, [int]$warn = 50, [int]$crit = 80) {
    $p = [int][Math]::Max(0, [Math]::Min(100, [Math]::Round($pct)))
    $color = if ($p -lt $warn) { '32' } elseif ($p -lt $crit) { '33' } else { '31' }
    $filled = [int][Math]::Min($width, [Math]::Floor($p * $width / 100))
    $bar = (C $color ($FULL.ToString() * $filled)) + (C '2' ($SHAD.ToString() * ($width - $filled)))
    return @($bar, (C $color "$p%"))
}

function K([double]$n) {
    if ($n -lt 1000000) { '{0:0.0}k' -f ($n / 1000) } else { '{0:0.00}M' -f ($n / 1000000) }
}

$DATA  = Join-Path $HOME '.claude/fable-mode'
$model = if ($d.model -and $d.model.display_name) { [string]$d.model.display_name } else { '?' }
$cost  = $d.cost
$cwd   = if ($d.workspace -and $d.workspace.current_dir) { [string]$d.workspace.current_dir } else { '.' }
$sid   = [string]$d.session_id
$tp    = $d.transcript_path
$cw    = $d.context_window
$rl    = $d.rate_limits

# level pin
$level = 'auto'
$lvPath = Join-Path $DATA 'level'
if (Test-Path $lvPath) {
    $lv = (Get-Content $lvPath -Raw).Trim()
    if ($lv -in @('lite', 'full', 'deep')) { $level = $lv }
}

# git branch (skip silently if git absent or cwd not a repo)
$branch = ''
if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
        $branch = (git -C $cwd branch --show-current 2>$null | Select-Object -First 1)
        if ($branch) { $branch = $branch.Trim() }
    } catch {}
}

# session cumulative output tokens (from the fable-mode stats log)
$out_tok = $null
$stats = Join-Path $DATA 'stats.jsonl'
if (Test-Path $stats) {
    foreach ($line in [IO.File]::ReadLines($stats)) {
        if (-not $line) { continue }
        try { $r = $line | ConvertFrom-Json } catch { continue }
        if ([string]$r.session -eq $sid) { $out_tok = $r.out }
    }
}

# ---- line 1: identity ----
$state_loop = Test-Path (Join-Path $DATA 'state-loop')
$has_state  = $state_loop -and (Test-Path (Join-Path $cwd '.fable-state.md'))
$l1 = [System.Collections.Generic.List[string]]::new()
$l1.Add((C '35;1' "$BOLT Fable") + ' ' + (C '36' $level))
$l1.Add((C '35' $model))
if ($state_loop) {
    if ($has_state) { $l1.Add((C '32' "$PEN state")) } else { $l1.Add("${DIM}${PEN} state ${NUL}${RST}") }
}
if ($branch) { $l1.Add((C '34' "$WYE $branch")) }
if ($null -ne $out_tok) { $l1.Add("${DIM}out${RST} " + (C '36' (K ([double]$out_tok)))) }
$usd = $cost.total_cost_usd
$mins = [int][Math]::Floor(([double]$cost.total_duration_ms) / 60000)
if ($null -ne $usd) {
    $l1.Add((C '33' ('${0:0.00}' -f [double]$usd)) + " ${DIM}${DOT} ${mins}m${RST}")
} elseif ($mins) {
    $l1.Add("${DIM}${mins}m${RST}")
}
$la = $cost.total_lines_added; $lr = $cost.total_lines_removed
if ($la -or $lr) {
    $l1.Add((C '32' ("+{0}" -f [int]$la)) + (C '31' ("/${MIN}{0}" -f [int]$lr)))
}

# ---- line 2: context + usage limits ----
$l2 = [System.Collections.Generic.List[string]]::new()

$ctx_pct = if ($cw) { $cw.used_percentage } else { $null }
$size = 0
if ($env:FABLE_CTX_LIMIT) { $size = [int]$env:FABLE_CTX_LIMIT }
if (-not $size) { $size = if ($cw -and $cw.context_window_size) { [int]$cw.context_window_size } else { 200000 } }

# transcript-tail fallback for CLI builds that don't report context_window
if (($null -eq $ctx_pct) -and $tp -and (Test-Path $tp)) {
    try {
        $fs = [IO.File]::Open($tp, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $len = $fs.Length
            $start = [long][Math]::Max(0, $len - 131072)
            [void]$fs.Seek($start, [IO.SeekOrigin]::Begin)
            $buf = New-Object byte[] ($len - $start)
            [void]$fs.Read($buf, 0, $buf.Length)
        } finally { $fs.Close() }
        $tlines = [Text.Encoding]::UTF8.GetString($buf) -split "`n"
        for ($i = $tlines.Count - 1; $i -ge 0; $i--) {
            $ln = $tlines[$i]
            if (-not $ln) { continue }
            try { $rec = $ln | ConvertFrom-Json } catch { continue }
            if ($rec.type -eq 'assistant') {
                $u = $rec.message.usage
                if ($u) {
                    $used = [double]$u.input_tokens + [double]$u.cache_read_input_tokens + [double]$u.cache_creation_input_tokens
                    $ctx_pct = 100.0 * $used / $size
                    break
                }
            }
        }
    } catch {}
}

if ($null -ne $ctx_pct) {
    $ctx_left = K ([Math]::Max(0, [Math]::Round($size * (1 - $ctx_pct / 100))))
    $m = Meter ([double]$ctx_pct) 10 60 85
    $seg = "${DIM}ctx${RST} $($m[0]) $($m[1]) ${DIM}${DOT} ${ctx_left} left${RST}"
    if ($has_state -and $ctx_pct -ge 40) { $seg += ' ' + (C '33' "$CYC clear-worthy") }
    $l2.Add($seg)
}

function Window($wname, $label) {
    $w = $rl.$wname
    if (-not $w) { return $null }
    $pct = $w.used_percentage
    if ($null -eq $pct) { return $null }
    $m = Meter ([double]$pct) 6 50 80
    $seg = "${DIM}${label}${RST} $($m[0]) $($m[1])"
    $resets = $w.resets_at
    if ($resets) {
        $t = ([DateTimeOffset]::FromUnixTimeSeconds([long]$resets)).LocalDateTime.ToString('HH:mm')
        $seg += " ${DIM}${RCY} ${t}${RST}"
    }
    return $seg
}
foreach ($pair in (, @('five_hour', '5h')), (, @('seven_day', '7d'))) {
    $p = $pair[0]
    $seg = Window $p[0] $p[1]
    if ($seg) { $l2.Add($seg) }
}

[Console]::Out.WriteLine($l1 -join $SEP)
if ($l2.Count) { [Console]::Out.WriteLine($l2 -join $SEP) }
