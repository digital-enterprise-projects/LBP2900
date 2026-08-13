$name = 'Canon LBP2900'
$pdf  = 'C:\Windows\Temp\sample-verify.pdf'

Write-Output "===== BUOC 0: MOC TRUOC KHI IN ====="
$p = Get-CimInstance Win32_Printer -Filter "Name='$name'"
Write-Output ("  WorkOffline=" + $p.WorkOffline + "  PrinterStatus=" + $p.PrinterStatus + "  DetectedErrorState=" + $p.DetectedErrorState)
$jobsBefore = @(Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue)
Write-Output ("  job trong hang doi: " + $jobsBefore.Count)
$perf = Get-CimInstance Win32_PerfRawData_Spooler_PrintQueue -Filter "Name='$name'" -ErrorAction SilentlyContinue
if ($perf) {
  Write-Output ("  spooler counters: TotalJobsPrinted=" + $perf.TotalJobsPrinted + "  TotalPagesPrinted=" + $perf.TotalPagesPrinted + "  JobErrors=" + $perf.JobErrors)
}
$usb = Get-PnpDevice -FriendlyName "*LBP2900*" -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'USBPRINT*' }
Write-Output ("  USB device: " + ($usb.Status -join ','))

Write-Output ""
Write-Output "===== BUOC 1: GUI LENH IN ====="
$t0 = Get-Date
& 'C:\Tools\SumatraPDF\SumatraPDF-3.5.2-64.exe' -print-to $name -silent -exit-when-done $pdf
Write-Output ("  sumatra exit code: " + $LASTEXITCODE + "  (0 = thanh cong)")

Write-Output ""
Write-Output "===== BUOC 2: THEO DOI JOB TUNG GIAY ====="
$seen = $false
for ($i = 1; $i -le 15; $i++) {
  Start-Sleep -Seconds 4
  $j = @(Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue)
  if ($j.Count -gt 0) {
    $seen = $true
    $j | ForEach-Object { Write-Output ("  +" + ($i*4) + "s  job " + $_.Id + "  status=" + $_.JobStatus + "  pages=" + $_.PagesPrinted + "/" + $_.TotalPages + "  size=" + $_.Size) }
  } else {
    Write-Output ("  +" + ($i*4) + "s  hang doi trong" + $(if ($seen) { "  <- job da qua spooler va bien mat" } else { "" }))
    if ($seen) { break }
  }
}

Write-Output ""
Write-Output "===== BUOC 3: DOI CHIEU SAU KHI IN ====="
$perf2 = Get-CimInstance Win32_PerfRawData_Spooler_PrintQueue -Filter "Name='$name'" -ErrorAction SilentlyContinue
if ($perf -and $perf2) {
  Write-Output ("  TotalJobsPrinted : " + $perf.TotalJobsPrinted + " -> " + $perf2.TotalJobsPrinted + "  (tang " + ($perf2.TotalJobsPrinted - $perf.TotalJobsPrinted) + ")")
  Write-Output ("  TotalPagesPrinted: " + $perf.TotalPagesPrinted + " -> " + $perf2.TotalPagesPrinted + "  (tang " + ($perf2.TotalPagesPrinted - $perf.TotalPagesPrinted) + ")")
  Write-Output ("  JobErrors        : " + $perf.JobErrors + " -> " + $perf2.JobErrors)
}
$p2 = Get-CimInstance Win32_Printer -Filter "Name='$name'"
Write-Output ("  PrinterStatus sau: " + $p2.PrinterStatus + "  DetectedErrorState: " + $p2.DetectedErrorState)

Write-Output ""
Write-Output "===== BUOC 4: SU KIEN SPOOLER (EVENT LOG) ====="
$ev = Get-WinEvent -LogName 'Microsoft-Windows-PrintService/Operational' -MaxEvents 10 -ErrorAction SilentlyContinue |
      Where-Object { $_.TimeCreated -gt $t0.AddSeconds(-5) }
if ($ev) {
  $ev | Sort-Object TimeCreated | ForEach-Object {
    Write-Output ("  [" + $_.TimeCreated.ToString("HH:mm:ss") + "] id=" + $_.Id + "  " + ($_.Message -split "`n")[0])
  }
} else {
  Write-Output "  (log PrintService/Operational khong bat - khong co su kien)"
  $ev2 = Get-WinEvent -LogName 'Microsoft-Windows-PrintService/Admin' -MaxEvents 5 -ErrorAction SilentlyContinue |
         Where-Object { $_.TimeCreated -gt $t0.AddSeconds(-5) }
  if ($ev2) { $ev2 | ForEach-Object { Write-Output ("  [Admin] " + ($_.Message -split "`n")[0]) } }
}
