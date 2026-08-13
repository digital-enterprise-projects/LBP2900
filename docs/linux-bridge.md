# In từ Linux qua máy Windows — CUPS backend `winbridge`

LBP2900 là máy CAPT: Linux không có driver ổn định (xem `captdriver-notes.md`), còn driver Windows chính chủ thì chạy tốt. Bridge này để máy Linux in **xuyên qua** máy Windows đang cắm máy in.

Đang chạy thực tế: `hn-kt-thao` (Ubuntu 24.04) → `hn-kt-nam` (Windows 10, cắm máy in).

## Kiến trúc

```
Ứng dụng bất kỳ trên Linux (chọn máy in như bình thường)
  -> CUPS, queue dùng PPD "Generic PDF Printer"  (CUPS xuất ra PDF)
  -> backend winbridge:
       scp PDF sang máy Windows (SSH key, không mật khẩu)
       ssh chạy: SumatraPDF -print-to "<máy in>" -silent
       đợi 20s rồi tự xoá mục job đọng trên Windows
  -> driver Canon trên Windows dựng trang -> USB -> giấy
```

Vì sao từng khâu:

- **PDF làm định dạng trung gian** — SumatraPDF đọc PDF; nếu để CUPS xuất PostScript thì Windows không in được.
- **SumatraPDF** — công cụ duy nhất gọn nhẹ in PDF im lặng từ dòng lệnh trên Windows (`-print-to ... -silent`). `Out-Printer` chỉ in text; `Start-Process -Verb Print` bật cửa sổ.
- **Tự xoá mục job đọng** — job nộp từ phiên SSH không có desktop không bao giờ được spooler đánh dấu xong; mục `Printing, Retained` sẽ chặn job kế tiếp. Backend chờ 20 giây rồi xoá mục của chính nó (lọc theo tên file `winbridge-<jobid>.pdf`, mã hoá lệnh PowerShell bằng `-EncodedCommand` để khỏi vỡ quoting qua 3 tầng bash→ssh→powershell).

## Cài đặt

### Phía Windows (máy cắm máy in)

1. **OpenSSH Server** chạy và Automatic (Windows 10/11 có sẵn, bật trong Optional Features)
2. **SumatraPDF** bản portable, đặt tại `C:\Tools\SumatraPDF\SumatraPDF-3.5.2-64.exe`
3. Thêm public key của root máy Linux vào `C:\ProgramData\ssh\administrators_authorized_keys`:

```powershell
Add-Content C:\ProgramData\ssh\administrators_authorized_keys '<public key>'
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F'
```

### Phía Linux

```bash
# 1. Khoá SSH cho root (CUPS backend chạy bằng root)
sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519
# -> đem public key sang Windows (bước 3 ở trên)

# 2. Nạp sẵn host key để không phụ thuộc "tin lần đầu"
sudo ssh-keyscan <host-windows> | sudo tee -a /root/.ssh/known_hosts

# 3. Cài backend
sudo install -m 0700 -o root -g root scripts/linux/winbridge /usr/lib/cups/backend/winbridge

# 4. Tạo queue
sudo lpadmin -p Canon_LBP2900_Bridge -E \
  -v "winbridge://Admin@<host-windows>/Canon%20LBP2900" \
  -m lsb/usr/cupsfilters/Generic-PDF_Printer-PDF.ppd \
  -D "Canon LBP2900 (qua may Windows)"
```

Host trong URI: dùng **tên MagicDNS của Tailscale** (vd `hn-kt-nam`) — sống sót khi IP LAN đổi. Fallback: `<tên-máy>.local` (mDNS) hoặc IP tĩnh. Backend tự thêm `Admin@` nếu URI bị CUPS lược mất username.

## Kiểm tra không tốn giấy

Trước khi in thật, xác minh từng mắt xích:

```bash
K="-i /root/.ssh/id_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=yes"
sudo ssh $K Admin@<host> "hostname"                                       # 1. SSH
sudo ssh $K Admin@<host> 'if exist "C:\Tools\SumatraPDF\SumatraPDF-3.5.2-64.exe" (echo CO)'  # 2. Sumatra
sudo ssh $K Admin@<host> 'powershell -c "(Get-Printer -Name \"Canon LBP2900\").Name"'        # 3. máy in
echo test > /tmp/t && sudo scp $K /tmp/t Admin@<host>:C:/Windows/Temp/t.txt                  # 4. scp
```

## Vận hành

- **Máy Windows tắt = không in được**, và người in không được báo gì ngoài job đọng trong CUPS. Đây là đánh đổi cốt lõi của bridge.
- Log backend: `sudo grep winbridge /var/log/cups/error_log`
- File tạm hai phía đều tự dọn (`/tmp/winbridge-*` trên Linux, `C:\Windows\Temp\winbridge-*.pdf` trên Windows).
- Nếu đổi máy Windows hoặc cài lại: làm lại phần khoá SSH + SumatraPDF, queue giữ nguyên chỉ cần sửa URI.
