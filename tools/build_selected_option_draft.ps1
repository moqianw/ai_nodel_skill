param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$Title
)

# This compatibility helper reconstructs candidate selected-option text only for
# old-format Web Chat records whose confirmation echo is abbreviated, or for a
# specific evidence dispute. New native three-part records should not run it by
# default. Its output belongs in an evidence package, never in an effective record.

$lines = [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $InputPath), [System.Text.Encoding]::UTF8)

function Match-Question([string]$line) {
    $nested = [regex]::Match($line, '^\s*\d+[\.．、]\s*(?:\*{0,2})(\d{1,4})[\.．、]\s*(.+?)(?:\*{0,2})?\s*$')
    if ($nested.Success) { return $nested }
    return [regex]::Match($line, '^\s*(?:#{1,6}\s*)?(?:\*{0,2})(\d{1,4})[\.．、]\s*(.+?)(?:\*{0,2})?\s*$')
}

function Match-Option([string]$line) {
    return [regex]::Match($line, '^\s*(?:[-*]\s*)?(?:\*{0,2})([A-F])[\.．、]\s*(.*)$')
}

function Test-ConfirmationStart([string]$line) {
    return $line -match '^(已确认|确认|继续。从|继续，|按你|根据你|依照你|对，|明白|收到|至此|这一组|这组|这里需要|这里新增|现在程砚|这样一来)'
}

function Test-OptionStop([string]$line) {
    return $line -match '^\s*---\s*$' -or
           $line -match '^\s*(?:我)?(?:更)?(?:推荐|倾向)' -or
           $line -match '^\s*(?:你)?(?:可以|可|请|直接|请直接).{0,28}(?:答|回复)' -or
           $line -match '^\s*`[^`]*(?:\d+[A-F])[^`]*`\s*$'
}

$questions = [System.Collections.Generic.List[object]]::new()
$currentQuestion = $null
$currentOption = $null

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $questionMatch = Match-Question $line
    if ($questionMatch.Success) {
        $currentQuestion = [pscustomobject]@{
            Id = [int]$questionMatch.Groups[1].Value
            Prompt = $questionMatch.Groups[2].Value.Trim()
            StartLine = $i + 1
            Options = @{}
            Recommendation = $null
        }
        $questions.Add($currentQuestion)
        $currentOption = $null
        continue
    }

    if ($null -eq $currentQuestion) { continue }

    $optionMatch = Match-Option $line
    if ($optionMatch.Success) {
        $currentOption = $optionMatch.Groups[1].Value.ToUpperInvariant()
        $currentQuestion.Options[$currentOption] = [System.Collections.Generic.List[string]]::new()
        $currentQuestion.Options[$currentOption].Add($optionMatch.Groups[2].Value)
        continue
    }

    if ($line -match '(?:我)?(?:更)?(?:推荐|倾向)\s*\*{0,2}([A-F])(?:\s*[+→偏]\s*([A-F]))?') {
        $letters = $matches[1]
        if ($matches[2]) { $letters += '+' + $matches[2] }
        $currentQuestion.Recommendation = $letters
        $currentOption = $null
        continue
    }

    if ($null -ne $currentOption) {
        if (Test-OptionStop $line) {
            $currentOption = $null
        }
        elseif (-not [string]::IsNullOrWhiteSpace($line)) {
            $currentQuestion.Options[$currentOption].Add($line)
        }
    }
}

$selections = @{}
$voided = @{}
$inConfirmation = $false

function Set-Selection([int]$id, [string]$letters, [int]$lineNumber, [string]$evidence) {
    if ($letters) {
        $script:selections[$id] = [pscustomobject]@{
            Letters = ($letters.ToUpperInvariant() -replace '[^A-F+]', '')
            Line = $lineNumber
            Evidence = $evidence.Trim()
        }
    }
}

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if (Test-ConfirmationStart $line) { $inConfirmation = $true }
    if ((Match-Question $line).Success) { $inConfirmation = $false }
    if (-not $inConfirmation) { continue }

    if ($line -match '(\d{1,4})\s*[—–-]\s*(\d{1,4}).{0,24}(?:全部)?(?:按|选择)\s*\*{0,2}([A-F])') {
        $start = [int]$matches[1]
        $end = [int]$matches[2]
        $letter = $matches[3]
        for ($id = $start; $id -le $end; $id++) { Set-Selection $id $letter ($i + 1) $line }
    }
    elseif ($line -match '(\d{1,4})\s*[—–-]\s*(\d{1,4}).{0,24}推荐项') {
        $start = [int]$matches[1]
        $end = [int]$matches[2]
        for ($id = $start; $id -le $end; $id++) {
            $q = $questions | Where-Object { $_.Id -eq $id -and $_.StartLine -lt ($i + 1) } | Sort-Object StartLine -Descending | Select-Object -First 1
            if ($q -and $q.Recommendation) { Set-Selection $id $q.Recommendation ($i + 1) $line }
        }
    }

    if ($line -match '(\d{1,4})\s*[—–-]\s*(\d{1,4}).{0,20}作废') {
        for ($id = [int]$matches[1]; $id -le [int]$matches[2]; $id++) { $voided[$id] = $i + 1 }
    }

    $tokenMatches = [System.Collections.Generic.List[System.Text.RegularExpressions.Match]]::new()
    foreach ($token in [regex]::Matches($line, '\*{2}(\d{1,4})(?:自定义|修正|追加|改成|改为|按)?\s*([A-F])(?:\s*[+＋]\s*([A-F]))?')) { $tokenMatches.Add($token) }
    $startToken = [regex]::Match($line, '^\s*(?:[-*]\s*)?(\d{1,4})(?:自定义|修正|追加|改成|改为|按)?\s*([A-F])(?:\s*[+＋]\s*([A-F]))?(?=[:：，,。\s])')
    if ($startToken.Success) { $tokenMatches.Add($startToken) }
    foreach ($token in $tokenMatches) {
        $id = [int]$token.Groups[1].Value
        $letters = $token.Groups[2].Value
        if ($token.Groups[3].Success) { $letters += '+' + $token.Groups[3].Value }
        Set-Selection $id $letters ($i + 1) $line
    }
}

$output = [System.Collections.Generic.List[string]]::new()
$output.Add("# $Title")
$output.Add('')
$output.Add('> 旧格式兼容用的自动恢复草稿，只能进入证据包，不能直接作为当前有效记录或正式事实。它只根据确认区中的题号/字母与上一轮选项匹配，可能漏掉自然语言自定义、复合选择、按推荐项、跨题覆盖或后文推翻。项目 Agent 必须逐条审核。新版三段式确认语义完整时默认不运行本工具。')
$output.Add('')
$output.Add("- 原始来源：$((Resolve-Path -LiteralPath $InputPath).Path)")
$output.Add("- 解析到的问题定义：$($questions.Count)")
$output.Add("- 解析到的题号选择：$($selections.Count)")
$output.Add("- 显式作废题号：$($voided.Count)")
$output.Add('')
$output.Add('## 被选方案全文候选')

foreach ($id in ($selections.Keys | Sort-Object {[int]$_})) {
    $selection = $selections[$id]
    $question = $questions | Where-Object { $_.Id -eq [int]$id -and $_.StartLine -lt $selection.Line } | Sort-Object StartLine -Descending | Select-Object -First 1
    $output.Add('')
    if (-not $question) {
        $output.Add("### Q$id：未找到此前问题定义")
        $output.Add('')
        $output.Add("- 解析选择：$($selection.Letters)")
        $output.Add("- 确认定位：原始第 $($selection.Line) 行：$($selection.Evidence)")
        continue
    }

    $status = if ($voided.ContainsKey([int]$id) -and $voided[[int]$id] -ge $selection.Line) { '显式作废，禁止并入当前事实' } else { '待 Agent 审核并入' }
    $output.Add("### Q$id：$($question.Prompt)")
    $output.Add('')
    $output.Add("- 解析选择：$($selection.Letters)")
    $output.Add("- 状态：$status")
    $output.Add("- 问题定位：原始第 $($question.StartLine) 行")
    $output.Add("- 确认定位：原始第 $($selection.Line) 行：$($selection.Evidence)")

    foreach ($letter in ($selection.Letters -split '\+')) {
        $output.Add('')
        $output.Add("#### 选项 $letter 原文")
        $output.Add('')
        if ($question.Options.ContainsKey($letter)) {
            foreach ($optionLine in $question.Options[$letter]) { $output.Add($optionLine) }
        }
        else {
            $output.Add('〔未解析到该选项正文，必须回查原始记录。〕')
        }
    }
}

$unresolved = $questions | Where-Object { -not $selections.ContainsKey($_.Id) } | Sort-Object StartLine
$output.Add('')
$output.Add('## 未自动恢复的问题')
$output.Add('')
foreach ($question in $unresolved) {
    $output.Add("- Q$($question.Id)（原始第 $($question.StartLine) 行）：$($question.Prompt)")
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($OutputPath, $output, $utf8NoBom)
