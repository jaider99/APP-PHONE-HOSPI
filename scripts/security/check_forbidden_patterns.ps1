$ErrorActionPreference = 'Stop'

$checks = @(
  @{
    Label = 'Flutter OpenRouter API key'
    Pattern = 'OPENROUTER_API_KEY'
    Path = 'lib'
  },
  @{
    Label = 'Flutter direct OpenRouter call'
    Pattern = 'openrouter\.ai/api'
    Path = 'lib'
  },
  @{
    Label = 'Flutter service-role key'
    Pattern = 'SUPABASE_SERVICE_ROLE_KEY'
    Path = 'lib'
  },
  @{
    Label = 'Flutter public document URL fallback'
    Pattern = 'getPublicUrl\('
    Path = 'lib'
  },
  @{
    Label = 'Long-lived document signed URL'
    Pattern = 'expiresIn\s*[:=]\s*(31536000|[0-9]{6,})'
    Path = 'lib'
  }
)

$failureCount = 0

foreach ($check in $checks) {
  if (-not (Test-Path $check.Path)) {
    Write-Error "Scan path not found: $($check.Path)"
  }

  $matches = Get-ChildItem -Path $check.Path -Recurse -File |
    Where-Object {
      $_.FullName -notmatch '[\\/](\.dart_tool|build|\.git)[\\/]'
    } |
    Select-String -Pattern $check.Pattern

  if ($matches) {
    foreach ($match in $matches) {
      $relativePath = Resolve-Path -Path $match.Path -Relative
      Write-Output "${relativePath}:$($match.LineNumber): $($match.Line.Trim())"
    }

    Write-Output "::error title=$($check.Label)::Forbidden pattern found in $($check.Path)"
    $failureCount++
  }
}

if ($failureCount -gt 0) {
  Write-Output "Security grep gates failed with $failureCount finding group(s)."
  exit 1
}

Write-Output 'Security grep gates passed.'