function Save-ReviewReceipt {
    param([string]$Path, $Value)
    $receiptTemporary = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $receiptJson = $Value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($receiptTemporary, $receiptJson, (New-Object Text.UTF8Encoding($false)))
    # Replacement is atomic on the same volume. Readers see either complete
    # version; retry briefly if Windows still has the previous file open.
    for ($receiptAttempt = 0; $receiptAttempt -lt 40; $receiptAttempt++) {
        try {
            if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($receiptTemporary, $Path, [System.Management.Automation.Language.NullString]::Value) }
            else { [IO.File]::Move($receiptTemporary, $Path) }
            return
        } catch [IO.IOException] {
            if ($receiptAttempt -eq 39) { throw }
            Start-Sleep -Milliseconds 50
        }
    }
}
