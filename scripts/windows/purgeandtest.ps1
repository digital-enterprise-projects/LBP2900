$name = 'Canon LBP2900'

Write-Output "=== job truoc khi xoa ==="
$jobs = Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue
if ($jobs) { $jobs | Format-Table Id, DocumentName, JobStatus -AutoSize | Out-String -Width 90 }
else { Write-Output "  (trong)" }

Write-Output "=== xoa toan bo job ==="
foreach ($j in @($jobs)) {
  try {
    Remove-PrintJob -PrinterName $name -ID $j.Id -ErrorAction Stop
    Write-Output ("  da xoa job " + $j.Id + " - " + $j.DocumentName)
  } catch {
    Write-Output ("  KHONG xoa duoc job " + $j.Id + ": " + $_.Exception.Message)
  }
}
Start-Sleep -Seconds 4

$left = @(Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue)
Write-Output ("  con lai: " + $left.Count + " job")

if ($left.Count -gt 0) {
  Write-Output ""
  Write-Output "=== van con job li: dung Spooler, xoa file spool, chay lai ==="
  Stop-Service Spooler -Force
  Start-Sleep -Seconds 3
  Remove-Item 'C:\Windows\System32\spool\PRINTERS\*' -Force -ErrorAction SilentlyContinue
  Start-Service Spooler
  Start-Sleep -Seconds 8
  $left = @(Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue)
  Write-Output ("  sau khi don spool, con lai: " + $left.Count + " job")
}

Write-Output ""
$p = Get-CimInstance Win32_Printer -Filter "Name='$name'"
Write-Output ("May in: WorkOffline=" + $p.WorkOffline + "  PrinterStatus=" + $p.PrinterStatus + "  DetectedErrorState=" + $p.DetectedErrorState)
