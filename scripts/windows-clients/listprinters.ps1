Write-Output ("HOST: " + $env:COMPUTERNAME)
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' }).IPAddress -join ','
Write-Output ("LAN : " + $ip)
Write-Output "PRINTERS:"
Get-Printer | ForEach-Object {
  Write-Output ("  " + $_.Name + "  |  port=" + $_.PortName + "  |  " + $_.PrinterStatus)
}
Write-Output "CANON/LBP hoac tro toi 192.168.1.36:"
$hit = Get-Printer | Where-Object { $_.Name -match 'LBP|Canon' -or $_.PortName -match '192.168.1.36|Canon|LBP' }
if ($hit) { $hit | ForEach-Object { Write-Output ("  CO: " + $_.Name + " -> " + $_.PortName) } }
else { Write-Output "  KHONG co" }
