param(
  [Parameter(Mandatory = $true)]
  [string]$Server,
  [string]$QueueName = 'Canon_LBP2900',
  [string]$PrinterName = 'Canon LBP2900 (LAN)',
  [ValidateRange(1, 65535)]
  [int]$Port = 631
)

$name = $PrinterName
$srv = $Server
$uri = "http://$srv`:$Port/printers/$QueueName"

Write-Output ("HOST: " + $env:COMPUTERNAME)

$p = Get-Printer -Name $name -ErrorAction SilentlyContinue
if ($p) {
  Write-Output ("  may in   : CO  [" + $p.PrinterStatus + "]  port=" + $p.PortName)
} else {
  Write-Output "  may in   : KHONG CO"
}

$tcp = Test-NetConnection -ComputerName $srv -Port $Port -WarningAction SilentlyContinue
Write-Output ("  toi " + $srv + ":" + $Port + " : " + $(if ($tcp.TcpTestSucceeded) { "KET NOI DUOC" } else { "KHONG TOI DUOC" }))

try {
  $r = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 10
  Write-Output ("  HTTP IPP  : " + $r.StatusCode + " OK")
} catch {
  Write-Output ("  HTTP IPP  : loi - " + $_.Exception.Message.Split([Environment]::NewLine)[0])
}

$jobs = @(Get-PrintJob -PrinterName $name -ErrorAction SilentlyContinue)
Write-Output ("  hang doi  : " + $jobs.Count + " job")
