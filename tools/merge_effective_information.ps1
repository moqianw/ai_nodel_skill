param(
    [Parameter(Mandatory = $true)][string]$EvidencePackagePath,
    [Parameter(Mandatory = $true)][string]$EvidenceTitle,
    [string]$CurrentRecordPath,
    [string]$CompilationMode = '未指定（项目 Agent 必须判定）',
    [string[]]$RawSourcePaths = @(),
    [string[]]$RawSourceTitles = @(),
    [switch]$MigrateEmbeddedEvidence,
    [string[]]$ProcessingEvidencePaths = @(),
    [string[]]$ProcessingEvidenceTitles = @(),
    [string[]]$SelectedOptionDraftPaths = @(),
    [string[]]$SelectedOptionDraftTitles = @(),
    [string[]]$LegacyAuditPaths = @(),
    [string[]]$LegacyAuditTitles = @()
)

# This helper writes historical and compilation evidence to a separate evidence
# package. It must never append evidence material to the current effective record.
# Semantic identity, coverage and formal-file placement remain Agent decisions.

if ($RawSourcePaths.Count -ne $RawSourceTitles.Count) {
    throw 'RawSourcePaths and RawSourceTitles must have the same number of entries.'
}
if ($ProcessingEvidencePaths.Count -ne $ProcessingEvidenceTitles.Count) {
    throw 'ProcessingEvidencePaths and ProcessingEvidenceTitles must have the same number of entries.'
}
if ($SelectedOptionDraftPaths.Count -ne $SelectedOptionDraftTitles.Count) {
    throw 'SelectedOptionDraftPaths and SelectedOptionDraftTitles must have the same number of entries.'
}
if ($LegacyAuditPaths.Count -ne $LegacyAuditTitles.Count) {
    throw 'LegacyAuditPaths and LegacyAuditTitles must have the same number of entries.'
}
if ($MigrateEmbeddedEvidence -and -not $CurrentRecordPath) {
    throw 'CurrentRecordPath is required when MigrateEmbeddedEvidence is used.'
}

$evidencePath = [System.IO.Path]::GetFullPath($EvidencePackagePath)
if (Test-Path -LiteralPath $evidencePath) {
    throw "Evidence package already exists: $evidencePath"
}

$builder = [System.Text.StringBuilder]::new()
[void]$builder.Append("# $EvidenceTitle`r`n`r`n")
[void]$builder.Append("> 用途：编译与审计证据。本文件不是当前小说知识接口；正常设计、单卷展开和正文生成不得默认读取。只有发生遗漏怀疑、身份争议、覆盖冲突或重新编译时才按需读取。`r`n`r`n")

if ($CurrentRecordPath) {
    $currentPath = (Resolve-Path -LiteralPath $CurrentRecordPath).Path
    $relativeCurrent = [System.IO.Path]::GetRelativePath((Split-Path -Parent $evidencePath), $currentPath).Replace('\', '/')
    [void]$builder.Append("- 当前有效记录：[$([System.IO.Path]::GetFileNameWithoutExtension($currentPath))]($relativeCurrent)`r`n")
}
[void]$builder.Append("- 编译模式：$CompilationMode`r`n")
if ($RawSourcePaths.Count -gt 0) {
    $rawLinks = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $RawSourcePaths.Count; $i++) {
        $rawPath = (Resolve-Path -LiteralPath $RawSourcePaths[$i]).Path
        $relativeRaw = [System.IO.Path]::GetRelativePath((Split-Path -Parent $evidencePath), $rawPath).Replace('\', '/')
        $rawLinks.Add("[$($RawSourceTitles[$i])]($relativeRaw)")
    }
    [void]$builder.Append("- 原始来源：$($rawLinks -join '、')`r`n")
}
[void]$builder.Append("- 生成方式：项目 Agent 语义审计的辅助证据；脚本不决定作者确认、推导可靠性、覆盖关系或正式落点。`r`n")

if ($MigrateEmbeddedEvidence) {
    $currentPath = (Resolve-Path -LiteralPath $CurrentRecordPath).Path
    $current = [System.IO.File]::ReadAllText($currentPath, [System.Text.Encoding]::UTF8)
    $markers = @(
        '## 旧筛选稿交叉校验层（非保真来源）',
        '## 完整信息单元层（不作摘要）',
        '## 原始处理区语义保全层（逐字）',
        '## 被选方案完整语义层'
    )
    $markerIndex = -1
    foreach ($marker in $markers) {
        $candidate = $current.IndexOf($marker)
        if ($candidate -ge 0 -and ($markerIndex -lt 0 -or $candidate -lt $markerIndex)) {
            $markerIndex = $candidate
        }
    }
    if ($markerIndex -lt 0) {
        throw "No embedded evidence marker found in current record: $CurrentRecordPath"
    }

    $knowledge = $current.Substring(0, $markerIndex).TrimEnd()
    $embeddedEvidence = $current.Substring($markerIndex).Trim()
    [void]$builder.Append("`r`n## 一、从旧有效记录迁出的编译证据`r`n`r`n")
    [void]$builder.Append($embeddedEvidence)
    [void]$builder.Append("`r`n")

    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($currentPath, $knowledge + "`r`n", $utf8NoBom)
}

function Append-EvidenceFiles(
    [System.Text.StringBuilder]$Target,
    [string]$Heading,
    [string[]]$Paths,
    [string[]]$Titles
) {
    if ($Paths.Count -eq 0) { return }
    [void]$Target.Append("`r`n## $Heading`r`n")
    for ($i = 0; $i -lt $Paths.Count; $i++) {
        $sourcePath = (Resolve-Path -LiteralPath $Paths[$i]).Path
        $source = [System.IO.File]::ReadAllText($sourcePath, [System.Text.Encoding]::UTF8).Trim()
        [void]$Target.Append("`r`n### $($Titles[$i])`r`n`r`n")
        [void]$Target.Append($source)
        [void]$Target.Append("`r`n")
    }
}

Append-EvidenceFiles $builder '二、原始处理区分段证据' $ProcessingEvidencePaths $ProcessingEvidenceTitles
Append-EvidenceFiles $builder '三、旧格式被选方案恢复证据' $SelectedOptionDraftPaths $SelectedOptionDraftTitles
Append-EvidenceFiles $builder '四、迁移与旧筛选稿比对证据' $LegacyAuditPaths $LegacyAuditTitles

$evidenceDirectory = Split-Path -Parent $evidencePath
if ($evidenceDirectory -and -not (Test-Path -LiteralPath $evidenceDirectory)) {
    New-Item -ItemType Directory -Path $evidenceDirectory | Out-Null
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($evidencePath, $builder.ToString().TrimEnd() + "`r`n", $utf8NoBom)
