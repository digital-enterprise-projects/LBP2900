param(
  [Parameter(Mandatory = $true)]
  [string]$Server,
  [string]$QueueName = 'Canon_LBP2900',
  [string]$PrinterName = 'Canon LBP2900 (LAN)',
  [ValidateRange(1, 65535)]
  [int]$Port = 631,
  [string]$DriverName
)

$printerName = $PrinterName
$uri = "http://$Server`:$Port/printers/$QueueName"

Write-Output ("HOST: " + $env:COMPUTERNAME)

if (Get-Printer -Name $printerName -ErrorAction SilentlyContinue) {
  Write-Output "  da co tu truoc, bo qua"
  exit 0
}

# Cong IPP: Windows chap nhan URI http:// lam ten cong
if (-not (Get-PrinterPort -Name $uri -ErrorAction SilentlyContinue)) {
  try {
    Add-PrinterPort -Name $uri -ErrorAction Stop
    Write-Output "  da tao cong IPP"
  } catch {
    Write-Output ("  loi tao cong: " + $_.Exception.Message)
  }
}

# Driver PostScript co san cua Windows - KHONG dung driver Canon
$driver = $null
$candidates = if ($DriverName) { @($DriverName) } else { @('Microsoft PS Class Driver', 'MS Publisher Imagesetter') }
foreach ($d in $candidates) {
  if (Get-PrinterDriver -Name $d -ErrorAction SilentlyContinue) { $driver = $d; break }
  try { Add-PrinterDriver -Name $d -ErrorAction Stop; $driver = $d; break } catch { }
}
if (-not $driver) {
  Write-Output "  KHONG tim duoc driver PostScript. Cai driver hoac truyen -DriverName."
  exit 1
}
Write-Output ("  driver: " + $driver)

try {
  Add-Printer -Name $printerName -DriverName $driver -PortName $uri -ErrorAction Stop
  Write-Output "  DA THEM MAY IN"
} catch {
  Write-Output ("  loi them may in: " + $_.Exception.Message)
  exit 1
}

$p = Get-Printer -Name $printerName -ErrorAction SilentlyContinue
if ($p) { Write-Output ("  xac nhan: " + $p.Name + " -> " + $p.PortName + "  [" + $p.PrinterStatus + "]") }

# KHONG dat lam mac dinh - giu nguyen thoi quen nguoi dung
Write-Output ("  may in mac dinh van la: " + (Get-CimInstance Win32_Printer -Filter 'Default=True').Name)
