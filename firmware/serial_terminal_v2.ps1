# serial_terminal_v2.ps1 — Text-only serial terminal with file logging
# Usage: .\serial_terminal_v2.ps1 [COM7]
# Output is also saved to serial_log.txt

param(
    [string]$Port = "COM7",
    [int]$Baud = 115200
)

Write-Host "=== CoreAccel-V Serial Terminal V2 ===" -ForegroundColor Cyan
Write-Host "Port: $Port @ $Baud baud"
Write-Host "Log:  serial_log.txt"
Write-Host "Press Ctrl+C to exit"
Write-Host "=======================================" -ForegroundColor Cyan

$logFile = "serial_log.txt"
"" | Set-Content $logFile

try {
    $serial = New-Object System.IO.Ports.SerialPort
    $serial.PortName = $Port
    $serial.BaudRate = $Baud
    $serial.DataBits = 8
    $serial.Parity = [System.IO.Ports.Parity]::None
    $serial.StopBits = [System.IO.Ports.StopBits]::One
    $serial.ReadTimeout = 1000
    $serial.NewLine = "`n"
    $serial.Open()

    Write-Host "[Connected to $Port]" -ForegroundColor Green

    # Read line-by-line (ReadLine uses NewLine delimiter)
    while ($true) {
        try {
            $line = $serial.ReadLine()
            $line = $line.TrimEnd("`r")
            Write-Host $line
            Add-Content $logFile $line
        } catch [System.TimeoutException] {
            # No data yet, keep waiting
        }
    }
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
} finally {
    if ($serial -and $serial.IsOpen) {
        $serial.Close()
        Write-Host "`n[Disconnected]" -ForegroundColor Yellow
    }
    Write-Host "Log saved to: $logFile" -ForegroundColor Green
}
