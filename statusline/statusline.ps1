#!/usr/bin/env pwsh
# Ripple HUD — fable-mode's statusline renderer — native Windows / PowerShell edition.
# Pure PowerShell (no bash, no python3) so the HUD works without Git Bash.
# Receives session JSON on stdin, prints the same two-line ANSI HUD as statusline.sh:
#   line 1: persona/level, model, branch (+dirty count), cost (+spend rate when high)
#   line 2: in-flight prompt (elapsed, estimate, current tool) + context meter,
#           cache hit rate, usage-limit meters (5h / 7d) with burn-out warning
# Segments past line 1's basics appear only when they cross a threshold.
# Installed to ~/.claude/fable-mode/statusline.ps1 by scripts/install-statusline.ps1.
# Windows PowerShell 5.1 compatible: no ?? / ?. / ternaries, no ConvertFrom-Json -AsHashtable.
# Every optional segment is guarded: a failure drops that segment, never the HUD.
$ErrorActionPreference = 'SilentlyContinue'

# UTF-8 out so the glyphs render (Windows PowerShell 5.1 defaults to cp1252 on stdout).
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}

$raw = [Console]::In.ReadToEnd()
try { $d = $raw | ConvertFrom-Json } catch { [Console]::Out.Write('fable'); exit 0 }
if ($null -eq $d) { [Console]::Out.Write('fable'); exit 0 }

# Glyphs by code point: keeps this source pure-ASCII so PS 5.1's ANSI-by-default
# script reader can't corrupt them and no UTF-8 BOM is required.
$E    = [char]27
$MARK = [char]0x25C8  # diamond (HUD mark)
$PEN  = [char]0x270E  # pencil (state)
$NUL  = [char]0x2205  # empty set
$DOT  = [char]0x00B7  # middle dot (separator)
$LINE = [char]0x2501  # heavy horizontal (meter)
$CYC  = [char]0x27F3  # clockwise arrow (/clear hint)
$RCY  = [char]0x21BB  # reset arrow
$GLAS = [char]0x23F3  # hourglass
$TRI  = [char]0x25B8  # small right triangle (tool)
$STAR = [char]0x273B  # thinking
$BUL  = [char]0x25CF  # dirty-count bullet
$WARN = [char]0x26A0  # warning sign
$ELL  = [char]0x2026  # ellipsis

$INV = [Globalization.CultureInfo]::InvariantCulture
function F([string]$fmt) { [string]::Format($INV, $fmt, $args) }

$DIM = "${E}[2m"
$RST = "${E}[0m"
function C([string]$code, [string]$s) { "${E}[${code}m${s}${RST}" }
$SEP = "  ${DIM}${DOT}${RST}  "

function Meter([double]$pct, [int]$width = 8, [int]$warn = 50, [int]$crit = 80) {
    $p = [int][Math]::Max(0, [Math]::Min(100, [Math]::Round($pct)))
    $color = if ($p -lt $warn) { '32' } elseif ($p -lt $crit) { '33' } else { '31' }
    $min = 0; if ($p) { $min = 1 }
    $filled = [int][Math]::Max($min, [Math]::Min($width, [Math]::Round($p * $width / 100.0)))
    $bar = (C $color ($LINE.ToString() * $filled)) + (C '2;90' ($LINE.ToString() * ($width - $filled)))
    return @($bar, (C $color "$p%"))
}

function K([double]$n) {
    if ($n -lt 1000000) { F '{0:0.0}k' ($n / 1000) } else { F '{0:0.00}M' ($n / 1000000) }
}

function Dur([double]$s) {
    $s = [long][Math]::Max(0, [Math]::Truncate($s))
    if ($s -lt 60) { return "${s}s" }
    if ($s -lt 3600) { return F '{0}m{1:00}s' ([Math]::Floor($s / 60)) ($s % 60) }
    return F '{0}h{1:00}m' ([Math]::Floor($s / 3600)) ([Math]::Floor(($s % 3600) / 60))
}

function UnixNow { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0 }

# pwsh 7 turns ISO strings into DateTime during ConvertFrom-Json; 5.1 leaves strings.
function Ts($rec) {
    try {
        $t = $rec.timestamp
        if ($null -eq $t) { return $null }
        if ($t -is [DateTime]) {
            if ($t.Kind -eq [DateTimeKind]::Unspecified) { $t = [DateTime]::SpecifyKind($t, [DateTimeKind]::Utc) }
            return [DateTimeOffset]::new($t.ToUniversalTime()).ToUnixTimeMilliseconds() / 1000.0
        }
        return [DateTimeOffset]::Parse([string]$t, $INV).ToUnixTimeMilliseconds() / 1000.0
    } catch { return $null }
}

function TailLines([string]$path, [long]$nbytes) {
    $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $len = $fs.Length
        $start = [long][Math]::Max(0, $len - $nbytes)
        [void]$fs.Seek($start, [IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] ($len - $start)
        $read = 0
        while ($read -lt $buf.Length) {
            $n = $fs.Read($buf, $read, $buf.Length - $read)
            if ($n -le 0) { break }
            $read += $n
        }
    } finally { $fs.Close() }
    $lines = [Text.Encoding]::UTF8.GetString($buf, 0, $read) -split "`r?`n"
    if ($len -gt $nbytes -and $lines.Count) { $lines = $lines[1..($lines.Count - 1)] }  # first line may be cut mid-record
    return , $lines
}

# Transcript records that matter: real user prompts, tool results, assistant messages.
# Shell (`!`) and local-command echoes are logged as user strings but start no turn.
$NOT_PROMPT = @('<bash-input>', '<bash-stdout>', '<bash-stderr>', '<local-command', '[Request interrupted')
function Classify($rec) {
    if ($rec.isSidechain -or $rec.isMeta) { return $null }
    $m = $rec.message
    if ($rec.type -eq 'assistant') {
        if ($m -and $m.stop_reason -eq 'end_turn') { return 'end' }
        return 'asst'
    }
    if ($rec.type -eq 'user' -and $m) {
        $cont = $m.content
        if ($cont -is [string]) {
            if ($cont.StartsWith('[Request interrupted')) { return 'end' }
            $t = $cont.TrimStart()
            foreach ($np in $NOT_PROMPT) { if ($t.StartsWith($np)) { return $null } }
            return 'prompt'
        }
        if ($null -ne $cont) {
            $anyType = $false; $interrupted = $false
            foreach ($b in @($cont)) {
                if (-not $b -or -not $b.type) { continue }
                if ($b.type -eq 'tool_result') { return 'result' }
                $anyType = $true
                if ($b.type -eq 'text' -and ([string]$b.text).StartsWith('[Request interrupted')) { $interrupted = $true }
            }
            if ($interrupted) { return 'end' }
            if ($anyType) { return 'prompt' }
        }
    }
    return $null
}

function Parse($lines) {
    $out = [System.Collections.Generic.List[object]]::new()
    # Cheap prefilter before the (slow) JSON parse: Claude Code writes compact JSON.
    $keep = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -and ($line.IndexOf('"type":"user"') -ge 0 -or $line.IndexOf('"type":"assistant"') -ge 0)) { $keep.Add($line) }
    }
    # One ConvertFrom-Json call over a synthetic array is several times faster than
    # one per line; fall back to per-line parsing if any record is malformed.
    $parsed = $null
    if ($keep.Count) {
        try { $parsed = ('[' + ($keep -join ',') + ']') | ConvertFrom-Json } catch { $parsed = $null }
        if ($null -eq $parsed) {
            $parsed = foreach ($line in $keep) { try { $line | ConvertFrom-Json } catch {} }
        }
    }
    foreach ($rec in @($parsed)) {
        if ($null -eq $rec) { continue }
        $kind = Classify $rec
        if ($kind) { $out.Add([pscustomobject]@{ K = $kind; R = $rec }) }
    }
    return , $out
}

function TurnDurations($recs) {
    # Prompt -> last end_turn before the next prompt, in seconds.
    $durs = [System.Collections.Generic.List[double]]::new()
    $start = $null; $lastEnd = $null; $open = $false
    foreach ($r in $recs) {
        if ($r.K -eq 'prompt') {
            if ($open -and $null -ne $start -and $null -ne $lastEnd -and ($lastEnd - $start) -gt 0) { $durs.Add($lastEnd - $start) }
            $start = Ts $r.R; $lastEnd = $null; $open = $true
        } elseif ($r.K -eq 'end' -and $open) {
            $lastEnd = Ts $r.R
        }
    }
    if ($open -and $null -ne $start -and $null -ne $lastEnd -and ($lastEnd - $start) -gt 0) { $durs.Add($lastEnd - $start) }
    return , $durs
}

function LastN($list, [int]$n) {
    $out = [System.Collections.Generic.List[double]]::new()
    $from = [Math]::Max(0, $list.Count - $n)
    for ($i = $from; $i -lt $list.Count; $i++) { $out.Add([double]$list[$i]) }
    return , $out
}

function Median($xs) {
    if (-not $xs -or $xs.Count -eq 0) { return $null }
    $s = [double[]]($xs | Sort-Object)
    $n = $s.Count
    if ($n % 2) { return $s[[Math]::Floor($n / 2)] }
    return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

$DATA  = Join-Path $HOME '.claude/fable-mode'
$model = if ($d.model -and $d.model.display_name) { [string]$d.model.display_name } else { '?' }
$cost  = $d.cost
$cwd   = if ($d.workspace -and $d.workspace.current_dir) { [string]$d.workspace.current_dir } else { '.' }
$tp    = [string]$d.transcript_path
$cw    = $d.context_window
$rl    = $d.rate_limits
$pc    = $d.prompt_cache
$now   = UnixNow

# level pin
$level = 'auto'
$lvPath = Join-Path $DATA 'level'
if (Test-Path $lvPath) {
    $lv = (Get-Content $lvPath -Raw).Trim()
    if ($lv -in @('lite', 'full', 'deep')) { $level = $lv }
}

# git branch + dirty count in one call (skip silently if git absent or cwd not a repo)
$branch = ''; $dirty = 0
# (no Get-Command probe: it costs more than just trying git and catching the failure)
try {
    $st = @(git -C $cwd status --porcelain=v1 -b 2>$null)
    if ($LASTEXITCODE -eq 0 -and $st.Count) {
        $rest = $st
        if ($st[0].StartsWith('## ')) {
            $head = $st[0].Substring(3).Replace('No commits yet on ', '')
            if (-not $head.StartsWith('HEAD (no branch)')) { $branch = ($head -split '\.\.\.')[0].Split(' ')[0] }
            $rest = if ($st.Count -gt 1) { $st[1..($st.Count - 1)] } else { @() }
        }
        foreach ($l in $rest) { if ($l -and $l.Trim()) { $dirty++ } }
    }
} catch {}

# transcript tail: shared by the in-flight detector, activity, cache fallback, context fallback
$recs = [System.Collections.Generic.List[object]]::new()
try {
    if ($tp -and (Test-Path -LiteralPath $tp)) { $recs = Parse (TailLines $tp 1500000) }
} catch { $recs = [System.Collections.Generic.List[object]]::new() }

# ---- in-flight prompt: elapsed, estimate, current activity ----
$flight = $null
try {
    $lastPrompt = -1
    for ($i = $recs.Count - 1; $i -ge 0; $i--) { if ($recs[$i].K -eq 'prompt') { $lastPrompt = $i; break } }
    if ($lastPrompt -ge 0) {
        $after = [System.Collections.Generic.List[object]]::new()
        for ($i = $lastPrompt + 1; $i -lt $recs.Count; $i++) { $after.Add($recs[$i]) }
        $started = Ts $recs[$lastPrompt].R
        $lastSeen = Ts $recs[$recs.Count - 1].R
        if ($null -eq $lastSeen) { $lastSeen = $started }
        # A turn is live until an end_turn/interrupt follows the prompt; ignore a
        # transcript that's gone quiet for an hour (crashed or abandoned session).
        $ended = $false
        foreach ($r in $after) { if ($r.K -eq 'end') { $ended = $true; break } }
        if ($started -and -not $ended -and ($now - $lastSeen) -lt 3600) {
            $flight = @{ elapsed = $now - $started; after = $after }
        }
    }
} catch { $flight = $null }

function Estimate {
    # Median prompt duration: this session first, then recent sessions in the same project.
    $durs = LastN (TurnDurations $recs) 20
    if ($durs.Count -lt 3 -and $tp) {
        $cacheF = Join-Path $DATA 'eta-cache.json'
        $proj = Split-Path -Parent $tp
        $cached = $null
        try { $cached = Get-Content -LiteralPath $cacheF -Raw | ConvertFrom-Json } catch { $cached = $null }
        $hit = $null
        if ($cached) { $prop = $cached.PSObject.Properties[$proj]; if ($prop) { $hit = $prop.Value } }
        if ($hit -and ($now - [double]$hit.at) -lt 600) {
            foreach ($x in @($hit.durs)) { if ($null -ne $x) { $durs.Add([double]$x) } }
        } else {
            $pool = [System.Collections.Generic.List[double]]::new()
            $tpFull = [IO.Path]::GetFullPath($tp)
            $others = @(Get-ChildItem -LiteralPath $proj -Filter '*.jsonl' -File |
                        Where-Object { $_.FullName -ne $tpFull } |
                        Sort-Object LastWriteTime -Descending | Select-Object -First 5)
            foreach ($f in $others) {
                try { foreach ($x in (LastN (TurnDurations (Parse (TailLines $f.FullName 1000000))) 20)) { $pool.Add($x) } } catch {}
            }
            $pool = LastN $pool 40
            try {
                # Rebuild as a hashtable so the bash renderer's entries survive the rewrite.
                $table = @{}
                if ($cached) { foreach ($p in $cached.PSObject.Properties) { $table[$p.Name] = $p.Value } }
                $table[$proj] = @{ at = $now; durs = [object[]]$pool.ToArray() }
                $tmp = "$cacheF.tmp"
                [IO.File]::WriteAllText($tmp, ($table | ConvertTo-Json -Depth 5 -Compress))
                Move-Item -LiteralPath $tmp -Destination $cacheF -Force
            } catch {}
            foreach ($x in $pool) { $durs.Add($x) }
        }
    }
    $m = Median $durs
    if ($null -eq $m) { return $null }
    # fable: crude multiplier — a pinned level shifts the typical turn length
    $mult = 1.0
    if ($level -eq 'lite') { $mult = 0.6 } elseif ($level -eq 'deep') { $mult = 1.6 }
    return $m * $mult
}

function ShortTool($block) {
    $name = [string]$block.name
    if (-not $name) { $name = 'tool' }
    $inp = $block.input
    if ($name.StartsWith('mcp__')) { $parts = $name -split '__'; $name = $parts[$parts.Count - 1] }
    $detail = ''
    if ($inp) {
        switch -Exact ($name) {
            'Bash' { if ($inp.command) { $detail = ([string]$inp.command).Trim().Split("`n")[0].TrimEnd("`r") } }
            { $_ -in @('Read', 'Edit', 'Write', 'NotebookEdit') } {
                $fp = [string]$inp.file_path; if (-not $fp) { $fp = [string]$inp.notebook_path }
                if ($fp) { $detail = ($fp -split '[\\/]')[-1] }
            }
            { $_ -in @('Grep', 'Glob') } { $detail = [string]$inp.pattern }
            'WebFetch' { $u = [string]$inp.url; $detail = (($u -split '//')[-1] -split '/')[0] }
            'WebSearch' { $detail = [string]$inp.query }
            { $_ -in @('Agent', 'Task') } { $detail = [string]$inp.description }
            'Skill' { $detail = [string]$inp.skill }
        }
    }
    if ($name -eq 'Bash' -and $detail) {
        $first = ($detail.Trim() -split '\s+')[0]
        $detail = ($first -split '/')[-1]  # just the program: git, npm, pytest
    }
    if ($detail.Length -gt 18) { $detail = $detail.Substring(0, 17) + $ELL }
    if ($detail) { return "$name " + (C '2' $detail) }
    return $name
}

function Activity($after) {
    # Parallel tool calls arrive as separate assistant records sharing one message id.
    $calls = [System.Collections.Generic.List[object]]::new()
    $results = [System.Collections.Generic.HashSet[string]]::new()
    $lastId = $null
    foreach ($r in $after) {
        $m = $r.R.message
        if (-not $m) { continue }
        if ($r.K -eq 'asst') {
            $blocks = @(@($m.content) | Where-Object { $_ -and $_.type -eq 'tool_use' })
            if ($blocks.Count) {
                if ($m.id -ne $lastId) { $calls = [System.Collections.Generic.List[object]]::new(); $lastId = $m.id }
                foreach ($b in $blocks) { $calls.Add($b) }
            }
        } elseif ($r.K -eq 'result') {
            foreach ($b in @($m.content)) { if ($b -and $b.tool_use_id) { [void]$results.Add([string]$b.tool_use_id) } }
        }
    }
    $pending = @($calls | Where-Object { -not $results.Contains([string]$_.id) })
    if (-not $pending.Count) { return (C '2' "$STAR thinking") }
    $seg = (C '36' "$TRI ") + (ShortTool $pending[$pending.Count - 1])
    if ($pending.Count -gt 1) { $seg += C '2' (" +{0}" -f ($pending.Count - 1)) }
    return $seg
}

$flightSeg = $null
if ($flight) {
    try {
        $el = $flight.elapsed
        $seg = C '33' "$GLAS $(Dur $el)"
        try {
            $est = Estimate
            if ($est) {
                $left = $est - $el
                if ($left -gt 0) { $seg += ' ' + (C '2' "~$(Dur $left) left") } else { $seg += ' ' + (C '33' 'running long') }
            }
        } catch {}
        try { $seg += '   ' + (Activity $flight.after) } catch {}
        $flightSeg = $seg
    } catch { $flightSeg = $null }
}

# ---- line 1: identity (calm: only what you glance at) ----
$state_loop = Test-Path (Join-Path $DATA 'state-loop')
$has_state  = $state_loop -and (Test-Path (Join-Path $cwd '.fable-state.md'))
$l1 = [System.Collections.Generic.List[string]]::new()
$first = C '35;1' "$MARK Ripple HUD"
if ($level -eq 'deep') { $first += ' ' + (C '1;97;41' ' deep ') }
elseif ($level -ne 'auto') { $first += ' ' + (C '2' $level) }
$l1.Add($first)
$l1.Add($model)
if ($state_loop) {
    if ($has_state) { $l1.Add((C '32' "$PEN state")) } else { $l1.Add("${DIM}${PEN} state ${NUL}${RST}") }
}
if ($branch) {
    $seg = C '34' $branch
    if ($dirty) { $seg += ' ' + (C '33' "$BUL$dirty") }
    $l1.Add($seg)
}
$usd = $null; $mins = 0
if ($cost) {
    $usd = $cost.total_cost_usd
    $mins = [long][Math]::Floor(([double]$cost.total_duration_ms) / 60000)
}
if ($null -ne $usd) {
    $seg = C '33' (F '${0:0.00}' ([double]$usd))
    if ($mins -ge 1 -and ([double]$usd / $mins) -ge 0.25) {  # spend rate only when it's worth noticing
        $rate = [double]$usd / $mins
        $rc = if ($rate -ge 1) { '31' } else { '33' }
        $seg += ' ' + (C $rc (F '${0:0.00}/m' $rate))
    }
    $l1.Add($seg)
}

# ---- line 2: live prompt, then meters (each appears only when it says something) ----
$l2 = [System.Collections.Generic.List[string]]::new()
if ($flightSeg) { $l2.Add($flightSeg) }

# context: official fields first, transcript-tail fallback for older versions
$ctx_pct = if ($cw) { $cw.used_percentage } else { $null }
$size = 0
if ($env:FABLE_CTX_LIMIT) { $size = [int]$env:FABLE_CTX_LIMIT }
if (-not $size) { $size = if ($cw -and $cw.context_window_size) { [double]$cw.context_window_size } else { 200000 } }
if ($null -eq $ctx_pct) {
    for ($i = $recs.Count - 1; $i -ge 0; $i--) {
        $r = $recs[$i]
        $u = $null; if ($r.R.message) { $u = $r.R.message.usage }
        if (($r.K -eq 'asst' -or $r.K -eq 'end') -and $u) {
            $used = [double]$u.input_tokens + [double]$u.cache_read_input_tokens + [double]$u.cache_creation_input_tokens
            $ctx_pct = 100.0 * $used / $size
            break
        }
    }
}
if ($null -ne $ctx_pct) {
    $m = Meter ([double]$ctx_pct) 8 60 85
    $seg = "${DIM}ctx${RST} $($m[0]) $($m[1])"
    if ($ctx_pct -ge 60) { $seg += " ${DIM}$(K ([Math]::Max(0, [Math]::Round($size * (1 - $ctx_pct / 100))))) left${RST}" }
    if ($has_state -and $ctx_pct -ge 40) { $seg += ' ' + (C '33' "$CYC /clear") }
    $l2.Add($seg)
}

# cache hit rate: hidden while healthy (>=80% and warm)
try {
    $hr = $null
    if ($pc) { $hr = $pc.hit_ratio }
    if ($null -eq $hr) {
        $rd = 0.0; $wr = 0.0; $fresh = 0.0
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        $from = [Math]::Max(0, $recs.Count - 200)
        for ($i = $from; $i -lt $recs.Count; $i++) {
            $r = $recs[$i]; $m = $r.R.message
            if (-not $m) { continue }
            $u = $m.usage
            if (($r.K -eq 'asst' -or $r.K -eq 'end') -and $u -and $seen.Add([string]$m.id)) {
                $rd += [double]$u.cache_read_input_tokens
                $wr += [double]$u.cache_creation_input_tokens
                $fresh += [double]$u.input_tokens
            }
        }
        if (($rd + $wr + $fresh) -gt 0) { $hr = $rd / ($rd + $wr + $fresh) }
    }
    $cold = $false
    if ($pc -and $pc.caching_observed -and ($pc.warm -is [bool]) -and -not $pc.warm) { $cold = $true }
    if ($null -ne $hr -and ([double]$hr -lt 0.8 -or $cold)) {
        $p = [int][Math]::Round([double]$hr * 100)
        $cc = if ($p -ge 50) { '33' } else { '31' }
        $seg = "${DIM}cache${RST} " + (C $cc "$p%")
        if ($cold) { $seg += ' ' + (C '33' 'cold') }
        $l2.Add($seg)
    }
} catch {}

# usage limits (Pro/Max): 5h always, 7d from 50%; reset time from 50%;
# warn when the current burn rate would exhaust the window before it resets
$WINDOW_SECS = @{ five_hour = 5 * 3600; seven_day = 7 * 86400 }
function Window([string]$wname, [string]$label) {
    if (-not $rl) { return $null }
    $w = $rl.$wname
    if (-not $w) { return $null }
    $pct = $w.used_percentage
    if ($null -eq $pct) { return $null }
    $pct = [double]$pct
    if ($wname -eq 'seven_day' -and $pct -lt 50) { return $null }
    $m = Meter $pct 6 50 80
    $seg = "${DIM}${label}${RST} $($m[0]) $($m[1])"
    $resets = $w.resets_at
    if ($resets) {
        $resets = [double]$resets
        if ($pct -ge 50) {
            $t = ([DateTimeOffset]::FromUnixTimeSeconds([long]$resets)).LocalDateTime.ToString('HH:mm', $INV)
            $seg += " ${DIM}${RCY}${t}${RST}"
        }
        try {
            $spent = $now - ($resets - $WINDOW_SECS[$wname])
            if ($pct -ge 10 -and $spent -gt 600 -and $pct -lt 100) {
                $toFull = (100 - $pct) * $spent / $pct
                if (($now + $toFull) -lt $resets) { $seg += ' ' + (C '31' "$WARN full ~$(Dur $toFull)") }
            }
        } catch {}
    }
    return $seg
}
foreach ($pair in @(@('five_hour', '5h'), @('seven_day', '7d'))) {
    $seg = Window $pair[0] $pair[1]
    if ($seg) { $l2.Add($seg) }
}

[Console]::Out.WriteLine($l1 -join $SEP)
if ($l2.Count) { [Console]::Out.WriteLine($l2 -join $SEP) }
