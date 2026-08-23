param(
  [string]$Server,
  [string]$QueueName = 'Canon_LBP2900'
)

Write-Output ("HOST: " + $env:COMPUTERNAME)
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { -not $_.IPAddress.StartsWith('127.') }).IPAddress -join ','
Write-Output ("LAN : " + $ip)
Write-Output "PRINTERS:"
Get-Printer | ForEach-Object {
  Write-Output ("  " + $_.Name + "  |  port=" + $_.PortName + "  |  " + $_.PrinterStatus)
}
$target = @('Canon', 'LBP', $QueueName)
if ($Server) { $target += $Server }
$pattern = ($target | ForEach-Object { [regex]::Escape($_) }) -join '|'
Write-Output ("MAY IN PHU HOP: " + ($target -join ', '))
$hit = Get-Printer | Where-Object { $_.Name -match $pattern -or $_.PortName -match $pattern }
if ($hit) { $hit | ForEach-Object { Write-Output ("  CO: " + $_.Name + " -> " + $_.PortName) } }
else { Write-Output "  KHONG co" }
