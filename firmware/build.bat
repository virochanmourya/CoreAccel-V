@echo off
echo ============================================
echo  CoreAccel-V Firmware V2 Build
echo ============================================

echo [1/4] Compiling...
riscv-none-elf-gcc -march=rv32i -mabi=ilp32 -O1 -ffreestanding -nostartfiles -T coreaccel_v.ld -o firmware.elf crt0.S main.c uart_driver.c seg_driver.c ads1115_driver.c -lgcc
if errorlevel 1 (echo COMPILE FAILED & pause & exit /b 1)

echo [2/4] Extracting hex from ELF...
riscv-none-elf-objcopy -O verilog --only-section=.text firmware.elf firmware_bytes.hex
riscv-none-elf-objcopy -O verilog --only-section=.data --change-addresses=-0x80000000 firmware.elf tcm_bytes.hex

echo [3/4] Converting to 32-bit word format...

powershell -NoProfile -Command ^
    "$c = Get-Content 'firmware_bytes.hex' -Raw; " ^
    "$c = $c -replace '@[0-9A-Fa-f]+\r?\n', ''; " ^
    "$b = $c -split '\s+' | Where-Object { $_ -match '^[0-9A-Fa-f]{2}$' }; " ^
    "$w = @(); " ^
    "for ($i=0; $i -lt $b.Count; $i+=4) { " ^
    "  if ($i+3 -lt $b.Count) { $w += \"$($b[$i+3])$($b[$i+2])$($b[$i+1])$($b[$i])\" } " ^
    "  elseif ($i+2 -lt $b.Count) { $w += \"00$($b[$i+2])$($b[$i+1])$($b[$i])\" } " ^
    "  elseif ($i+1 -lt $b.Count) { $w += \"0000$($b[$i+1])$($b[$i])\" } " ^
    "  else { $w += \"000000$($b[$i])\" } " ^
    "}; " ^
    "$w -join \"`n\" | Set-Content 'firmware.hex' -NoNewline; " ^
    "Write-Host \"  IMEM: $($b.Count) bytes -> $($w.Count) words\""

powershell -NoProfile -Command ^
    "$c = Get-Content 'tcm_bytes.hex' -Raw; " ^
    "$c = $c -replace '@[0-9A-Fa-f]+\r?\n', ''; " ^
    "$b = $c -split '\s+' | Where-Object { $_ -match '^[0-9A-Fa-f]{2}$' }; " ^
    "if ($b.Count -eq 0) { " ^
    "  Set-Content 'tcm_init.hex' '' -NoNewline; " ^
    "  Write-Host '  TCM:  0 bytes (empty .data section)'; " ^
    "} else { " ^
    "  $w = @(); " ^
    "  for ($i=0; $i -lt $b.Count; $i+=4) { " ^
    "    if ($i+3 -lt $b.Count) { $w += \"$($b[$i+3])$($b[$i+2])$($b[$i+1])$($b[$i])\" } " ^
    "    elseif ($i+2 -lt $b.Count) { $w += \"00$($b[$i+2])$($b[$i+1])$($b[$i])\" } " ^
    "    elseif ($i+1 -lt $b.Count) { $w += \"0000$($b[$i+1])$($b[$i])\" } " ^
    "    else { $w += \"000000$($b[$i])\" } " ^
    "  }; " ^
    "  $w -join \"`n\" | Set-Content 'tcm_init.hex' -NoNewline; " ^
    "  Write-Host \"  TCM:  $($b.Count) bytes -> $($w.Count) words. First: $($w[0])\" " ^
    "}"

echo [4/4] Memory usage:
riscv-none-elf-size -A firmware.elf

echo.
echo Build Complete!
pause
