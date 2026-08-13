$name = 'Canon LBP2900'
$PRINTER_ATTRIBUTE_WORK_OFFLINE = 0x400

function Show-State($tag) {
  $p = Get-CimInstance Win32_Printer -Filter "Name='$name'"
  Write-Output ("[" + $tag + "] WorkOffline=" + $p.WorkOffline + "  PrinterStatus=" + $p.PrinterStatus + "  DetectedErrorState=" + $p.DetectedErrorState)
}

Write-Output "=== USB co nhan may in khong ==="
$dev = Get-PnpDevice -FriendlyName "*LBP2900*" -ErrorAction SilentlyContinue
if ($dev) { $dev | ForEach-Object { Write-Output ("  " + $_.FriendlyName + " -> " + $_.Status) } }
else { Write-Output "  KHONG thay thiet bi USB nao ten LBP2900" }

Write-Output ""
Show-State "truoc"

Write-Output ""
Write-Output "=== buoc 1: bo co WorkOffline qua WMI ==="
try {
  $p = Get-CimInstance Win32_Printer -Filter "Name='$name'"
  $p.WorkOffline = $false
  $p | Set-CimInstance -ErrorAction Stop
  Write-Output "  WMI: da gui lenh"
} catch {
  Write-Output ("  WMI khong doi duoc: " + $_.Exception.Message)
}
Start-Sleep -Seconds 3
Show-State "sau WMI"

$p = Get-CimInstance Win32_Printer -Filter "Name='$name'"
if ($p.WorkOffline) {
  Write-Output ""
  Write-Output "=== buoc 2: xoa bit offline trong registry roi khoi dong lai Spooler ==="
  $key = "HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers\$name"
  if (Test-Path $key) {
    $attr = (Get-ItemProperty -Path $key -Name Attributes -ErrorAction SilentlyContinue).Attributes
    Write-Output ("  Attributes hien tai: " + $attr)
    if ($attr -band $PRINTER_ATTRIBUTE_WORK_OFFLINE) {
      $new = $attr -band (-bnot $PRINTER_ATTRIBUTE_WORK_OFFLINE)
      Set-ItemProperty -Path $key -Name Attributes -Value $new
      Write-Output ("  da doi thanh: " + $new)
    } else {
      Write-Output "  bit offline khong bat trong registry"
    }
  } else {
    Write-Output "  khong tim thay khoa registry"
  }
  Restart-Service Spooler -Force
  Start-Sleep -Seconds 6
  Show-State "sau restart Spooler"
}

Write-Output ""
Write-Output "=== hang doi hien tai ==="
$jobs = Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue
if ($jobs) { $jobs | Format-Table Id,DocumentName,JobStatus -AutoSize | Out-String -Width 90 }
else { Write-Output "  (trong)" }
