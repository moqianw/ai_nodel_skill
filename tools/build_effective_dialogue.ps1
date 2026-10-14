param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$ScopeNote,
    [string]$ProcessingEvidencePath
)

# This helper produces a lossless segmentation draft. It never decides what the
# author confirmed, whether an inference is reliable, which conclusion covers
# another, or what belongs in formal project files. A project Agent must review
# the complete draft semantically before creating an evidence package and an
# effective record.

$resolvedInput = Resolve-Path -LiteralPath $InputPath
$sourceLines = [System.IO.File]::ReadAllLines($resolvedInput, [System.Text.Encoding]::UTF8)
$result = [System.Collections.Generic.List[string]]::new()

function Test-OptionLine([string]$line) {
    return $line -match '^\s*(?:[-*]\s*)?(?:\*{0,2})?[A-Fa-f][\.．、]\s+'
}

function Test-QuestionHeader([int]$index) {
    $line = $sourceLines[$index]
    if ($line -notmatch '^\s*(?:#{1,6}\s*)?(?:\*{0,2})?\d+(?:\.\d+)?(?:[（(][^）)]+[）)])?[\.．、]\s+') {
        return $false
    }

    if ($line -match '[？?]' -or $line -match '(是否|什么|怎么|如何|哪一|哪个|能不能|可不可以|要不要|选择|到什么程度|具体采用)') {
        return $true
    }

    for ($lookAhead = $index + 1; $lookAhead -lt [Math]::Min($sourceLines.Count, $index + 5); $lookAhead++) {
        if ([string]::IsNullOrWhiteSpace($sourceLines[$lookAhead])) { continue }
        return Test-OptionLine $sourceLines[$lookAhead]
    }

    return $false
}

function Test-ResponseStart([string]$line) {
    return $line -match '^(确认|明白|收到|好[，,。]|对[，,。]|已按|已采用|按这一轮|你这轮|这一轮|这轮|至此|正式进入|先校正|可以确定|经过.+(?:确认|修订|调整))' -or
           ($line -match '^(按你|根据你|依照你)' -and $line -notmatch '(推荐|倾向)')
}

$header = @(
    "# $Title",
    '',
    '> 本文件只是自动分段初稿，不是有效记录，也不能证明语义无损。脚本保留原文全部行，只标出疑似“上一轮处理区 / 下一轮问题区”和来源行号。最终决定、模型推导、建议、覆盖关系、例外、去重和正式落点必须由项目 Agent 完整阅读后判断。',
    "> $ScopeNote",
    "> 原始来源：$($resolvedInput.Path)",
    '',
    '## 无损分段初稿',
    ''
)
foreach ($line in $header) { $result.Add($line) }

$zone = '处理区候选'
$result.Add('<!-- segment: processing-candidate; source-line: 1; confidence: heuristic -->')

for ($i = 0; $i -lt $sourceLines.Count; $i++) {
    $line = $sourceLines[$i]
    $lineNumber = $i + 1

    if ((Test-QuestionHeader $i) -and $zone -ne '问题区候选') {
        $zone = '问题区候选'
        $result.Add('')
        $result.Add("<!-- segment: question-candidate; source-line: $lineNumber; confidence: heuristic; review-required: true -->")
    }
    elseif ((Test-ResponseStart $line) -and $zone -ne '处理区候选') {
        $zone = '处理区候选'
        $result.Add('')
        $result.Add("<!-- segment: processing-candidate; source-line: $lineNumber; confidence: heuristic; review-required: true -->")
    }

    if (Test-OptionLine $line) {
        $result.Add("<!-- candidate-option-at-source-line: $lineNumber -->")
    }

    $result.Add($line)
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($OutputPath, $result, $utf8NoBom)

if ($ProcessingEvidencePath) {
    # Optional second artifact: a reviewable verbatim preservation draft for the
    # previous-answer processing portions. It keeps question titles for location,
    # removes the unselected option menus/recommendations/answer formats, and does
    # not decide whether an old statement remains current. Selected option bodies
    # must be recovered separately and merged only after semantic review.
    $evidence = [System.Collections.Generic.List[string]]::new()
    $evidence.Add("# $Title · 逐轮处理区原文保真稿")
    $evidence.Add('')
    $evidence.Add('> 本稿直接由原始记录生成，逐字保留每轮“上一轮回答处理区”，并保留下一轮题干作为定位。它删除下一轮未选择选项、推荐理由与答题格式，但不判断后文覆盖、信息身份或正式落点，因此只能作为证据包输入。项目 Agent 仍须语义审计，并把其中当前有效、执行相关的语义另行编译进有效记录与正式资料。')
    $evidence.Add("> 原始来源：$($resolvedInput.Path)")
    $evidence.Add('')
    $evidence.Add('## 逐轮处理区与题干定位')
    $evidence.Add('')

    $inQuestionZone = $false
    $expectNextOutput = $false
    $processingBlock = 1
    $evidence.Add("<!-- processing-block: $processingBlock; source-line: 1 -->")

    for ($i = 0; $i -lt $sourceLines.Count; $i++) {
        $line = $sourceLines[$i]
        $lineNumber = $i + 1

        if ($inQuestionZone) {
            if ($expectNextOutput -and -not [string]::IsNullOrWhiteSpace($line)) {
                $inQuestionZone = $false
                $expectNextOutput = $false
                $processingBlock++
                $evidence.Add('')
                $evidence.Add("<!-- processing-block: $processingBlock; source-line: $lineNumber -->")
            }
            elseif (Test-ResponseStart $line) {
                $inQuestionZone = $false
                $expectNextOutput = $false
                $processingBlock++
                $evidence.Add('')
                $evidence.Add("<!-- processing-block: $processingBlock; source-line: $lineNumber -->")
            }
        }

        if (-not $inQuestionZone -and (Test-QuestionHeader $i)) {
            $inQuestionZone = $true
            $evidence.Add('')
            $evidence.Add("<!-- question-title; source-line: $lineNumber -->")
            $evidence.Add($line)
            continue
        }

        if ($inQuestionZone) {
            if (Test-QuestionHeader $i) {
                $evidence.Add('')
                $evidence.Add("<!-- question-title; source-line: $lineNumber -->")
                $evidence.Add($line)
            }

            if ($line -match '^\s*(?:你)?(?:可以|可|请)?\s*直接(?:答|回答|回复)' -or
                $line -match '^\s*(?:你)?可以(?:按|用|只|回复).{0,30}(?:答|回答|回复)' -or
                $line -match '^\s*`[^`]*(?:\d+[A-F])[^`]*`\s*$') {
                $expectNextOutput = $true
            }
            continue
        }

        $evidence.Add($line)
    }

    $evidenceDirectory = Split-Path -Parent $ProcessingEvidencePath
    if ($evidenceDirectory -and -not (Test-Path -LiteralPath $evidenceDirectory)) {
        New-Item -ItemType Directory -Path $evidenceDirectory | Out-Null
    }
    [System.IO.File]::WriteAllLines($ProcessingEvidencePath, $evidence, $utf8NoBom)
}
