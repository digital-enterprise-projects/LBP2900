$name = 'Canon LBP2900 (LAN)'
$srv  = '192.168.1.36'

Write-Output ("HOST: " + $env:COMPUTERNAME)

$p = Get-Printer -Name $name -ErrorAction SilentlyContinue
if ($p) {
  Write-Output ("  may in   : CO  [" + $p.PrinterStatus + "]  port=" + $p.PortName)
} else {
  Write-Output "  may in   : KHONG CO"
}

$tcp = Test-NetConnection -ComputerName $srv -Port 631 -WarningAction SilentlyContinue
Write-Output ("  toi " + $srv + ":631 : " + $(if ($tcp.TcpTestSucceeded) { "KET NOI DUOC" } else { "KHONG TOI DUOC" }))

try {
  $r = Invoke-WebRequest -Uri "http://$srv`:631/printers/Canon_LBP2900" -UseBasicParsing -TimeoutSec 10
  Write-Output ("  HTTP IPP  : " + $r.StatusCode + " OK")
} catch {
  Write-Output ("  HTTP IPP  : loi - " + $_.Exception.Message.Split([Environment]::NewLine)[0])
}

$jobs = @(Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue)
Write-Output ("  hang doi  : " + $jobs.Count + " job")
