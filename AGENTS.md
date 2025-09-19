# PSAsk Agent Guidelines

## Build/Lint/Test Commands
- **Lint**: `Invoke-ScriptAnalyzer -Path .\ask.ps1 -Recurse -ReportSummary`
- **Test**: `Invoke-Pester -Path .\tests\ -Output Detailed`
- **Single test**: `Invoke-Pester -Path .\tests\MyTest.tests.ps1 -TestName "Test-Name"`
- **Format**: `Invoke-Formatter -ScriptDefinition (Get-Content .\ask.ps1 -Raw)`

## Code Style Guidelines

### Naming Conventions
- Functions: PascalCase with approved verbs (Get-, Set-, New-, etc.)
- Parameters: camelCase
- Variables: PascalCase for globals, camelCase for locals

### Structure & Best Practices
- Use `param()` blocks for function parameters
- Add `[Parameter()]` attributes for validation
- Use `[CmdletBinding()]` for advanced functions
- Implement comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`

### Error Handling
- Use `try/catch` blocks for error-prone operations
- Use `Write-Error` for non-terminating errors
- Use `throw` for terminating errors
- Validate parameters with `[ValidateNotNullOrEmpty()]`, `[ValidateRange()]`

### Output & Logging
- Use `Write-Verbose` for debug information
- Use `Write-Warning` for warnings
- Use `Write-Error` for errors
- Return objects, not formatted strings

### Imports & Dependencies
- Use full cmdlet names (avoid aliases in scripts)
- Import modules explicitly with `Import-Module`
- Use `#Requires` for PowerShell version requirements