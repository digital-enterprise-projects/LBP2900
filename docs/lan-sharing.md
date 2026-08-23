# Triển khai Canon LBP2900 dùng chung qua CUPS/IPP

Tài liệu này mô tả cấu hình triển khai chuẩn cho một đơn vị: máy in kết nối USB với máy chủ Linux, còn máy trạm sử dụng IPP qua LAN.

## Kiến trúc

```text
[Canon LBP2900]
        │ USB
        ▼
[Linux print server]
  usblp → /dev/usb/lp0
  captdriver direct-device patch
  CUPS queue: Canon_LBP2900
        │ IPP/TCP 631
        ├──────────────► [Windows clients]
        └──────────────► [Linux clients]
```

Luồng dữ liệu trên máy chủ có một điểm đặc biệt: filter `rastertocapt` tự ghi vào `/dev/usb/lp0`. Vì vậy URI của queue là `file:///dev/null`; backend CUPS chỉ đóng vai trò nhận job và chạy filter, không được mở thiết bị USB thêm lần nữa.

## Yêu cầu

- Máy chủ Linux có IP tĩnh hoặc DHCP reservation.
- Máy in cắm trực tiếp vào USB của máy chủ, không qua hub nếu có thể.
- Máy trạm truy cập được TCP 631 trên máy chủ.
- Người triển khai có quyền `sudo` trên máy chủ và Administrator trên Windows.
- Đã cài filter/PPD theo phần triển khai nhanh trong [README](../README.md).

Ví dụ trong tài liệu dùng:

```bash
PRINT_SERVER_IP="192.168.10.20"
LAN_CIDR="192.168.10.0/24"
QUEUE_NAME="Canon_LBP2900"
PPD_PATH="/usr/share/ppd/CanonLBP-2900-3000.ppd"
```

Thay các giá trị này theo mạng của đơn vị.

## 1. Xác nhận thiết bị USB

```bash
lsusb | grep -i canon
sudo modprobe usblp
ls -l /dev/usb/lp*
```

Để tự nạp `usblp` sau khi khởi động:

```bash
echo usblp | sudo tee /etc/modules-load.d/usblp.conf
```

Kiểm tra IEEE-1284 device ID mà không gửi job in:

```bash
sudo python3 - <<'PY'
import fcntl
import os

path = os.environ.get("CAPT_DEVICE", "/dev/usb/lp0")
fd = os.open(path, os.O_RDWR)
try:
    buf = bytearray(1024)
    fcntl.ioctl(fd, 0x84005001, buf)  # LPIOC_GET_DEVICE_ID
    size = (buf[0] << 8) | buf[1]
    print(buf[2:size].decode("latin-1"))
finally:
    os.close(fd)
PY
```

Kết quả hợp lệ có `MFG:Canon`, `MDL:LBP2900` và `CMD:CAPT`. Nếu lệnh không mở được thiết bị, xử lý USB/permission trước khi cấu hình CUPS.

## 2. Cấu hình queue CUPS

Cho phép backend `file://`:

```bash
grep -q '^FileDevice Yes$' /etc/cups/cups-files.conf || \
  echo 'FileDevice Yes' | sudo tee -a /etc/cups/cups-files.conf
```

Tạo queue:

```bash
sudo lpadmin -p "$QUEUE_NAME" -E \
  -v file:///dev/null \
  -P "$PPD_PATH" \
  -D "Canon LBP2900"
sudo lpadmin -p "$QUEUE_NAME" -o printer-is-shared=true
```

Không thay `file:///dev/null` bằng `usb://...` khi đang dùng bản vá direct-device. Hai tiến trình cùng giữ cổng USB có thể làm job bị treo.

## 3. Chia sẻ trong LAN

```bash
sudo cupsctl --share-printers --remote-any
sudo systemctl enable --now cups
sudo systemctl restart cups
sudo ss -lntp | grep ':631'
```

Nếu dùng UFW:

```bash
sudo ufw allow from "$LAN_CIDR" to any port 631 proto tcp
```

Nếu dùng firewall khác, tạo quy tắc tương đương: chỉ cho phép nguồn thuộc LAN truy cập TCP 631. Không NAT/port-forward cổng này ra Internet.

Kiểm tra từ một máy khác:

```bash
curl -I "http://$PRINT_SERVER_IP:631/printers/$QUEUE_NAME"
```

HTTP `200`, `401` hoặc `403` đều chứng minh đã tới được CUPS; `Connection refused` hoặc timeout là lỗi service, firewall hoặc định tuyến.

## 4. Thêm máy trạm Windows

Từ PowerShell Administrator tại thư mục repository:

```powershell
.\scripts\windows-clients\addipp.ps1 `
  -Server 192.168.10.20 `
  -QueueName Canon_LBP2900 `
  -PrinterName "Canon LBP2900 - Van phong"
```

Kiểm tra:

```powershell
.\scripts\windows-clients\checkconn.ps1 `
  -Server 192.168.10.20 `
  -QueueName Canon_LBP2900 `
  -PrinterName "Canon LBP2900 - Van phong"
```

Máy trạm Windows dùng driver PostScript chung. Không cài driver CAPT của Canon trên client IPP; driver CAPT chỉ chạy trên máy chủ.

Nếu chính sách Windows không cho phép script tạo cổng, thêm thủ công bằng URI:

```text
http://192.168.10.20:631/printers/Canon_LBP2900
```

Thay IP và tên queue theo môi trường thực tế.

## 5. Thêm máy trạm Linux

```bash
sudo apt install -y cups-client
sudo lpadmin -p "$QUEUE_NAME" -E \
  -v "ipp://$PRINT_SERVER_IP:631/printers/$QUEUE_NAME" \
  -m everywhere
lpstat -p "$QUEUE_NAME" -l
```

## 6. Kiểm thử nghiệm thu

Trên máy chủ:

```bash
lpstat -t
lp -d "$QUEUE_NAME" /usr/share/cups/data/testprint
watch -n 1 lpstat -W not-completed -o
```

Sau đó in một trang thử từ mỗi loại máy trạm. Ghi nhận:

- Tên máy trạm và hệ điều hành.
- Có truy cập được IPP hay không.
- Job có xuất hiện và rời queue hay không.
- Máy in có ra đúng nội dung hay không.
- Log CUPS có lỗi CAPT hay không.

Lệnh đọc log:

```bash
sudo tail -n 200 /var/log/cups/error_log
sudo journalctl -u cups --since '10 minutes ago' --no-pager
```

## 7. Vận hành định kỳ

### Sau reboot hoặc cắm lại USB

```bash
sudo modprobe usblp
ls -l /dev/usb/lp0
lpstat -p "$QUEUE_NAME" -l
```

### Xóa job lỗi

```bash
lpstat -W not-completed -o
cancel <JOB_ID>
# Chỉ khi đã thông báo người dùng và cần xóa toàn bộ queue:
cancel -a "$QUEUE_NAME"
```

### Đổi máy chủ hoặc địa chỉ IP

1. Gán IP/DNS ổn định cho máy chủ mới.
2. Cài lại driver, patch và queue theo tài liệu này.
3. Cập nhật URI trên các máy trạm bằng script client.
4. Xóa queue cũ sau khi xác nhận không còn job cần xử lý.

## 8. Bảng chẩn đoán nhanh

| Triệu chứng | Kiểm tra | Xử lý |
|---|---|---|
| Không có `/dev/usb/lp0` | `lsusb`, `lsmod \| grep usblp` | `modprobe usblp`, kiểm tra cáp/cổng, cắm lại USB |
| `CAPT: unable to communicate` | quyền truy cập và `CAPT_DEVICE` | khôi phục đúng device node, restart CUPS |
| `CAPT: no reply from printer` | patch/filter đang dùng | build lại filter đã vá, kiểm tra queue dùng `file:///dev/null` |
| Client không mở được cổng 631 | `Test-NetConnection`/`curl` | kiểm tra CUPS listen, firewall và VLAN ACL |
| Job đọng nhưng máy đã in | `lpstat`, log CUPS | xác nhận giấy đã ra rồi mới xóa job |
| Tất cả client cùng lỗi | test trực tiếp trên server | xử lý server/USB trước, không cài lại từng client |

## 9. Checklist bàn giao

- [ ] Máy chủ có IP/DNS ổn định.
- [ ] `usblp` tự nạp và `/dev/usb/lp0` xuất hiện sau reboot.
- [ ] Queue dùng đúng PPD và URI `file:///dev/null`.
- [ ] TCP 631 chỉ mở trong LAN cần thiết.
- [ ] Windows và Linux client đều in được trang thử.
- [ ] Đã lưu tên queue, IP/DNS máy chủ và người/nhóm chịu trách nhiệm vận hành trong hệ thống quản trị nội bộ của đơn vị.
- [ ] Người vận hành biết cách xem log và xóa job lỗi an toàn.
