# Old proven script — byte by byte, shows everything
param([string]$Port = "COM7", [int]$Baud = 115200)
Write-Host "=== Terminal ===" -ForegroundColor Cyan
try {
    $s = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
    $s.ReadTimeout = 500; $s.DtrEnable = $true; $s.RtsEnable = $true; $s.Open()
    Write-Host "[Connected]" -ForegroundColor Green
    while ($true) {
        try {
            $byte = $s.ReadByte()
            if ($byte -eq 10) { Write-Host "" }
            elseif ($byte -ge 32 -and $byte -le 126) { Write-Host ([char]$byte) -NoNewline }
        } catch [System.TimeoutException] { }
    }
} catch { Write-Host "ERROR: $_" -ForegroundColor Red
} finally { if ($s -and $s.IsOpen) { $s.Close() } }
