$name = 'Canon LBP2900'
$pdf  = 'C:\Windows\Temp\sample-verify.pdf'

Write-Output "===== RESET DAY DU ====="
Write-Output "--- 1. don hang doi + dung Spooler ---"
Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue | ForEach-Object {
  Remove-PrintJob -PrinterName $name -ID $_.Id -ErrorAction SilentlyContinue
}
Stop-Service Spooler -Force
Start-Sleep -Seconds 3
Remove-Item 'C:\Windows\System32\spool\PRINTERS\*' -Force -ErrorAction SilentlyContinue
Write-Output "  spool sach"

Write-Output "--- 2. reset thiet bi USB (disable/enable) ---"
$usb = Get-PnpDevice -FriendlyName "*LBP2900*" -ErrorAction SilentlyContinue |
       Where-Object { $_.InstanceId -like 'USBPRINT*' } | Select-Object -First 1
if ($usb) {
  Disable-PnpDevice -InstanceId $usb.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 6
  Enable-PnpDevice -InstanceId $usb.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 6
  Write-Output ("  da reset: " + $usb.InstanceId)
} else {
  Write-Output "  KHONG tim thay thiet bi USBPRINT"
}

Write-Output "--- 3. chay lai Spooler ---"
Start-Service Spooler
Start-Sleep -Seconds 8
$p = Get-CimInstance Win32_Printer -Filter "Name='$name'"
Write-Output ("  WorkOffline=" + $p.WorkOffline + "  PrinterStatus=" + $p.PrinterStatus)
if ($p.WorkOffline) {
  $p.WorkOffline = $false
  $p | Set-CimInstance
  Write-Output "  (da bo co offline)"
}

Write-Output ""
Write-Output "===== MOC TRUOC KHI IN ====="
$perf = Get-CimInstance Win32_PerfRawData_Spooler_PrintQueue -Filter "Name='$name'" -ErrorAction SilentlyContinue
Write-Output ("  TotalJobsPrinted=" + $perf.TotalJobsPrinted + "  TotalPagesPrinted=" + $perf.TotalPagesPrinted)

Write-Output ""
Write-Output "===== IN PDF ====="
& 'C:\Tools\SumatraPDF\SumatraPDF-3.5.2-64.exe' -print-to $name -silent -exit-when-done $pdf 2>$null
Write-Output "  da gui lenh in"

Write-Output ""
Write-Output "===== THEO DOI 80 GIAY ====="
$gone = $false
for ($i = 1; $i -le 20; $i++) {
  Start-Sleep -Seconds 4
  $j = @(Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue)
  if ($j.Count -gt 0) {
    $j | ForEach-Object { Write-Output ("  +" + ($i*4) + "s  job " + $_.Id + "  " + $_.JobStatus + "  pages=" + $_.PagesPrinted) }
  } else {
    Write-Output ("  +" + ($i*4) + "s  HANG DOI TRONG")
    $gone = $true
    break
  }
}

Write-Output ""
Write-Output "===== DOI CHIEU ====="
$perf2 = Get-CimInstance Win32_PerfRawData_Spooler_PrintQueue -Filter "Name='$name'" -ErrorAction SilentlyContinue
Write-Output ("  TotalJobsPrinted : " + $perf.TotalJobsPrinted + " -> " + $perf2.TotalJobsPrinted)
Write-Output ("  TotalPagesPrinted: " + $perf.TotalPagesPrinted + " -> " + $perf2.TotalPagesPrinted + "   <- TANG = trang da duoc xac nhan in")
if ($gone -and ($perf2.TotalPagesPrinted -gt $perf.TotalPagesPrinted)) {
  Write-Output ""
  Write-Output "  KET LUAN: MOI DAU HIEU PHAN MEM DEU BAO IN THANH CONG"
} elseif ($gone) {
  Write-Output ""
  Write-Output "  KET LUAN: job roi hang doi nhung trang khong duoc xac nhan - mo ho"
} else {
  Write-Output ""
  Write-Output "  KET LUAN: job van treo - du lieu khong xuong duoc may in"
}
