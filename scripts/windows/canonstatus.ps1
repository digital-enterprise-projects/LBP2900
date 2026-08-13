$name = 'Canon LBP2900'

$err = @{
  0='Unknown'; 1='Other'; 2='Khong loi'; 3='Sap het giay'; 4='HET GIAY';
  5='Sap het muc'; 6='HET MUC'; 7='MO NAP'; 8='KET GIAY'; 9='Can bao tri';
  10='Khay ra day'; 11='Su co giay'; 12='Khong in duoc trang'; 13='Can nguoi xu ly';
  14='Het bo nho'; 15='May chu khong ro'
}
$state = @{
  1='Khac'; 2='Khong ro'; 3='San sang'; 4='Dang in'; 5='Dang khoi dong';
  6='Dung - dang cho'; 7='Dang in ra'; 8='Offline'
}

Write-Output "=== Get-Printer ==="
Get-Printer -Name $name | Format-List Name,PrinterStatus,PortName,Shared,Published | Out-String -Width 80

Write-Output "=== WMI Win32_Printer (chi tiet nhat) ==="
$p = Get-CimInstance Win32_Printer -Filter "Name='$name'"
if ($p) {
  Write-Output ("  PrinterStatus       : " + $p.PrinterStatus + "  (" + $state[[int]$p.PrinterStatus] + ")")
  Write-Output ("  DetectedErrorState  : " + $p.DetectedErrorState + "  (" + $err[[int]$p.DetectedErrorState] + ")")
  Write-Output ("  ExtendedPrinterStat : " + $p.ExtendedPrinterStatus)
  Write-Output ("  WorkOffline         : " + $p.WorkOffline)
  Write-Output ("  PrinterState        : " + $p.PrinterState)
  Write-Output ("  Jobs trong queue    : " + $p.JobCountSinceLastReset)
  if ($p.ErrorDescription) { Write-Output ("  ErrorDescription    : " + $p.ErrorDescription) }
  if ($p.Status)           { Write-Output ("  Status              : " + $p.Status) }
} else {
  Write-Output "  KHONG TIM THAY may in"
}

Write-Output ""
Write-Output "=== Job dang cho ==="
$jobs = Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue
if ($jobs) {
  $jobs | Format-Table Id,DocumentName,JobStatus,SubmittedTime -AutoSize | Out-String -Width 100
} else {
  Write-Output "  (khong co job nao)"
}

Write-Output "=== Dich vu Spooler ==="
Get-Service Spooler | Format-Table Name,Status,StartType -AutoSize | Out-String -Width 50
