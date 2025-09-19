# ask.ps1 - Simple OpenRouter API CLI tool
# Usage: .\ask.ps1 [OPTIONS] [PROMPT]

param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string]$Prompt,

    [switch]$c,  # Use inception/mercury-coder (default)
    [switch]$g,  # Use google/gemini-2.5-flash
    [switch]$s,  # Use anthropic/claude-sonnet-4
    [switch]$k,  # Use moonshotai/kimi-k2
    [switch]$q,  # Use qwen/qwen3-235b-a22b-2507

    [string]$m,  # Use custom model
    [switch]$r,  # Disable system prompt (raw model behavior)
    [switch]$stream,  # Enable streaming output
    [string]$system,  # Set system prompt for the conversation
    [string]$provider,  # Comma-separated list of providers for routing
    [switch]$h,  # Show help message
    [switch]$help  # Show help message
)

# Function to show help
function Show-Help {
    Write-Host @"
ask - Query AI models via OpenRouter API

Usage: .\ask.ps1 [OPTIONS] [PROMPT]

Options:
  -c          Use inception/mercury-coder (default)
  -g          Use google/gemini-2.5-flash
  -s          Use anthropic/claude-sonnet-4
  -k          Use moonshotai/kimi-k2
  -q          Use qwen/qwen3-235b-a22b-2507
  -m MODEL    Use custom model
  -r          Disable system prompt (raw model behavior)
  -stream     Enable streaming output
  -system     Set system prompt for the conversation
  -provider   Comma-separated list of providers for routing
  -h, -help   Show this help message

Examples:
  .\ask.ps1 "Write a hello world in Python"
  .\ask.ps1 -g "Explain quantum computing"
  .\ask.ps1 -m openai/gpt-4o "What is 2+2?"
  "Fix this code" | .\ask.ps1
  .\ask.ps1 -system "You are a pirate" "Tell me about sailing"

"@
    exit 0
}

# Process help first before other checks
if ($h -or $help) {
    Show-Help
}

# Check for API key
if (-not $env:OPENROUTER_API_KEY) {
    Write-Error "Error: OPENROUTER_API_KEY environment variable is not set"
    exit 1
}

# Model shortcuts function
function Get-Model {
    param([string]$shortcut)
    switch ($shortcut) {
        'c' { return "inception/mercury-coder:nitro" }
        'g' { return "google/gemini-2.5-flash:nitro" }
        's' { return "anthropic/claude-sonnet-4:nitro" }
        'k' { return "moonshotai/kimi-k2:nitro" }
        'q' { return "qwen/qwen3-235b-a22b-2507:nitro" }
    }
}

# Default values
$MODEL = "inception/mercury-coder:nitro"
$SYSTEM_PROMPT = ""
$STREAMING = $false
$NO_SYSTEM = $false
$PROVIDER_ORDER = ""

# Default system prompt (direct answers)
$DEFAULT_PROMPT = @"
You are a direct answer engine. Output ONLY the requested information.

For commands: Output executable syntax only. No explanations, no comments.
For questions: Output the answer only. No context, no elaboration.

Rules:
- If asked for a command, provide ONLY the command
- If asked a question, provide ONLY the answer
- Never include markdown formatting or code blocks
- Never add explanatory text before or after
- Assume output will be piped or executed directly
- For multi-step commands, use && or ; to chain them
- Make commands robust and handle edge cases silently
"@

# Process command line switches
if ($c) { $MODEL = Get-Model 'c' }
if ($g) { $MODEL = Get-Model 'g' }
if ($s) { $MODEL = Get-Model 's' }
if ($k) { $MODEL = Get-Model 'k' }
if ($q) { $MODEL = Get-Model 'q' }

if ($m) { $MODEL = $m }
if ($r) { $NO_SYSTEM = $true }
if ($stream) { $STREAMING = $true }
if ($system) { $SYSTEM_PROMPT = $system }
if ($provider) { $PROVIDER_ORDER = $provider }

# If no prompt provided as argument, read from stdin
if (-not $Prompt) {
    if ($MyInvocation.ExpectingInput) {
        Write-Error "Error: No prompt provided. Use -h for help."
        exit 1
    }
    # Read all stdin
    $Prompt = $input | Out-String
    $Prompt = $Prompt.Trim()
}

# Apply default system prompt unless disabled or custom prompt provided
if (-not $NO_SYSTEM -and -not $SYSTEM_PROMPT) {
    $SYSTEM_PROMPT = $DEFAULT_PROMPT
}

# Build messages array
$messages = @()
if ($SYSTEM_PROMPT) {
    $messages += @{
        role = "system"
        content = $SYSTEM_PROMPT
    }
}
$messages += @{
    role = "user"
    content = $Prompt
}

# Record start time
$startTime = Get-Date

# Build JSON payload
$jsonPayload = @{
    model = $MODEL
    messages = $messages
    stream = $STREAMING
}

if ($PROVIDER_ORDER) {
    $providerArray = $PROVIDER_ORDER -split ',' | ForEach-Object { $_.Trim() }
    $jsonPayload.provider = @{
        order = $providerArray
    }
}

$apiUrl = "https://openrouter.ai/api/v1/chat/completions"
$headers = @{
    "Content-Type" = "application/json"
    "Authorization" = "Bearer $env:OPENROUTER_API_KEY"
}

# Add newline before answer
Write-Host

# Make API request
if ($STREAMING) {
    # Streaming mode - use HttpClient for better streaming support
    try {
        $httpClient = New-Object System.Net.Http.HttpClient
        $httpClient.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $env:OPENROUTER_API_KEY)
        $httpClient.DefaultRequestHeaders.Add("Content-Type", "application/json")

        $jsonString = $jsonPayload | ConvertTo-Json -Depth 10
        $content = New-Object System.Net.Http.StringContent($jsonString, [System.Text.Encoding]::UTF8, "application/json")

        $response = $httpClient.PostAsync($apiUrl, $content).Result
        $response.EnsureSuccessStatusCode()

        $stream = $response.Content.ReadAsStreamAsync().Result
        $reader = New-Object System.IO.StreamReader($stream)

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ($line -match '^data: (.+)$') {
                $json = $matches[1]
                if ($json -and $json -ne '[DONE]') {
                    try {
                        $data = $json | ConvertFrom-Json
                        $content = $data.choices[0].delta.content
                        if ($content) {
                            Write-Host -NoNewline $content
                        }
                    } catch {
                        # Skip invalid JSON lines
                    }
                }
            }
        }

        Write-Host
    } catch {
        Write-Error "Error: $($_.Exception.Message)"
        exit 1
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($httpClient) { $httpClient.Dispose() }
    }

    # Show metadata
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
    Write-Host
    Write-Host "[$MODEL - ${elapsed}s]" -ForegroundColor Gray
} else {
    # Non-streaming mode
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body ($jsonPayload | ConvertTo-Json -Depth 10)

        # Check for errors
        if ($response.error) {
            Write-Error "Error: $($response.error.message)"
            exit 1
        }

        # Extract and print content
        $content = $response.choices[0].message.content
        if ($content) {
            Write-Host $content
        }

        # Show metadata
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 2)
        $tokens = $response.usage.completion_tokens
        $provider = $response.provider
        $tps = if ($elapsed -gt 0) { [math]::Round($tokens / $elapsed, 1) } else { 0.0 }

        Write-Host
        Write-Host "[$MODEL via $provider - ${elapsed}s - ${tps} tok/s]" -ForegroundColor Gray
    } catch {
        Write-Error "Error: $($_.Exception.Message)"
        exit 1
    }
}