# Canon LBP2900 — hướng dẫn triển khai máy chủ in dùng chung

Repository này cung cấp quy trình triển khai Canon LBP2900 theo mô hình:

```text
Canon LBP2900 (USB)
  → máy chủ Linux + CUPS + captdriver đã vá
  → IPP qua mạng LAN
  → máy trạm Windows/Linux
```

Mục tiêu là tạo một hàng đợi in tập trung, không cần cài driver Canon trên từng máy trạm. Tất cả tên máy, địa chỉ IP và tên hàng đợi trong tài liệu đều là giá trị mẫu; đơn vị triển khai thay bằng thông tin của mình.

Driver phát hành kèm repository là source `captdriver 0.1.4.1` đã áp patch direct-device, có source đầy đủ, patch rời, giấy phép GPL-3.0 và checksum SHA-256. Xem [hướng dẫn cài đặt và sử dụng](docs/installation.md).

## Phạm vi hỗ trợ

- Máy in: Canon LBP2900/LBP3000 sử dụng giao thức CAPT.
- Máy chủ in: Ubuntu 22.04/24.04 hoặc hệ Debian tương đương.
- Máy trạm: Windows 10/11 và Linux có IPP.
- Kết nối: máy in cắm USB trực tiếp vào máy chủ Linux, máy trạm truy cập TCP 631 trong LAN.

Không dùng hướng dẫn này nếu máy in đang được quản lý bởi một print server khác hoặc chính sách mạng không cho phép mở IPP.

## Chuẩn bị thông số

Chọn trước các giá trị sau và dùng nhất quán trong toàn bộ quá trình:

| Biến | Ví dụ | Ý nghĩa |
|---|---|---|
| `PRINT_SERVER_IP` | `192.168.10.20` | IP tĩnh hoặc DHCP reservation của máy chủ |
| `LAN_CIDR` | `192.168.10.0/24` | Dải mạng được phép dùng IPP |
| `QUEUE_NAME` | `Canon_LBP2900` | Tên queue trong CUPS, không dùng dấu cách |
| `DISPLAY_NAME` | `Canon LBP2900 - Van phong` | Tên hiển thị trên máy trạm |

Các lệnh dưới đây giả định repository đã được clone và terminal đang đứng tại thư mục repository:

```bash
REPO_DIR="$PWD"
PRINT_SERVER_IP="192.168.10.20"
LAN_CIDR="192.168.10.0/24"
QUEUE_NAME="Canon_LBP2900"
```

Hãy sửa ba giá trị mẫu trước khi chạy.

## Triển khai nhanh trên máy chủ Linux

### 1. Cài CUPS và biên dịch driver

```bash
sudo apt update
sudo apt install -y build-essential automake autoconf libcups2-dev cups cups-client cups-ppdc git patch

git clone https://github.com/mounaiban/captdriver.git /tmp/captdriver
cd /tmp/captdriver
patch -p1 < "$REPO_DIR/captdriver-patch/direct-device-mode.patch"
autoreconf -i
./configure
make

sudo install -m 0755 src/rastertocapt /usr/lib/cups/filter/rastertocapt
mkdir -p /tmp/captdriver-ppd
(cd src && ppdc canon-lbp.drv -d /tmp/captdriver-ppd)
sudo install -m 0644 /tmp/captdriver-ppd/CanonLBP-2900-3000.ppd /usr/share/ppd/CanonLBP-2900-3000.ppd
```

### 2. Bật thiết bị USB `usblp`

```bash
echo usblp | sudo tee /etc/modules-load.d/usblp.conf
sudo modprobe usblp
ls -l /dev/usb/lp0
```

Chỉ tiếp tục khi `/dev/usb/lp0` tồn tại. Nếu máy chủ có nhiều máy in USB, xác định đúng node và đặt biến môi trường `CAPT_DEVICE` cho dịch vụ CUPS; xem [ghi chú captdriver](docs/captdriver-notes.md).

### 3. Tạo và chia sẻ queue

```bash
grep -q '^FileDevice Yes$' /etc/cups/cups-files.conf || \
  echo 'FileDevice Yes' | sudo tee -a /etc/cups/cups-files.conf

sudo lpadmin -p "$QUEUE_NAME" -E \
  -v file:///dev/null \
  -P /usr/share/ppd/CanonLBP-2900-3000.ppd \
  -D "Canon LBP2900"

sudo lpadmin -p "$QUEUE_NAME" -o printer-is-shared=true
sudo cupsctl --share-printers --remote-any
sudo systemctl enable --now cups
sudo systemctl restart cups
```

Nếu máy chủ dùng UFW, chỉ mở IPP cho LAN:

```bash
sudo ufw allow from "$LAN_CIDR" to any port 631 proto tcp
```

### 4. Xác minh máy chủ

```bash
lpstat -t
sudo ss -lntp | grep ':631'
lp -d "$QUEUE_NAME" /usr/share/cups/data/testprint
sudo journalctl -u cups --since '5 minutes ago' --no-pager
```

Kết quả đạt yêu cầu:

- `/dev/usb/lp0` tồn tại.
- CUPS lắng nghe cổng 631 trên địa chỉ LAN.
- Job chuyển sang trạng thái hoàn tất và máy in xuất trang thử.
- Log không có `CAPT: no reply from printer` hoặc `CAPT: unable to communicate with printer`.

## Cài máy trạm

### Windows 10/11

Mở PowerShell với quyền Administrator từ thư mục repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows-clients\addipp.ps1 `
  -Server 192.168.10.20 `
  -QueueName Canon_LBP2900 `
  -PrinterName "Canon LBP2900 - Van phong"

powershell -ExecutionPolicy Bypass -File .\scripts\windows-clients\checkconn.ps1 `
  -Server 192.168.10.20 `
  -QueueName Canon_LBP2900 `
  -PrinterName "Canon LBP2900 - Van phong"
```

Script không thay đổi máy in mặc định. Máy trạm dùng driver PostScript có sẵn của Windows; việc chuyển sang CAPT được thực hiện trên máy chủ Linux.

### Linux

```bash
sudo apt install -y cups-client
sudo lpadmin -p "$QUEUE_NAME" -E \
  -v "ipp://$PRINT_SERVER_IP:631/printers/$QUEUE_NAME" \
  -m everywhere
lpstat -p "$QUEUE_NAME" -l
```

## Vận hành và khắc phục sự cố

Thực hiện kiểm tra theo thứ tự:

1. Kiểm tra nguồn, giấy, mực, nắp máy và đèn báo.
2. Trên máy chủ, kiểm tra `ls -l /dev/usb/lp0`.
3. Kiểm tra queue bằng `lpstat -t` và xóa job lỗi nếu cần bằng `cancel -a "$QUEUE_NAME"`.
4. Kiểm tra log bằng `journalctl -u cups` và `/var/log/cups/error_log`.
5. Nếu mất node USB, chạy `sudo modprobe usblp`, rút/cắm lại cáp rồi kiểm tra lại.
6. Chỉ reset nguồn máy in sau khi đã xác nhận không còn job đang xử lý.

Chi tiết:

- [Cài đặt, sử dụng và tự áp patch](docs/installation.md)
- [Triển khai và bảo mật chia sẻ LAN](docs/lan-sharing.md)
- [Cơ chế bản vá captdriver](docs/captdriver-notes.md)

## Cấu trúc repository

```text
captdriver-patch/
  direct-device-mode.patch       Bổ sung chế độ truy cập trực tiếp /dev/usb/lpN
docs/
  installation.md                Cài từ release hoặc tự áp patch rồi build
  lan-sharing.md                 Quy trình triển khai CUPS/IPP chi tiết
  captdriver-notes.md            Giải thích kỹ thuật và cách chẩn đoán
scripts/windows-clients/         Cài đặt và kiểm tra máy trạm Windows qua IPP
scripts/release/                 Tạo lại gói source driver đã patch
```

## Lưu ý an toàn

- Chỉ mở TCP 631 cho mạng tin cậy; không công khai CUPS ra Internet.
- `file:///dev/null` là cấu hình có chủ đích: filter đã vá ghi trực tiếp vào thiết bị, backend CUPS không được giữ cổng USB lần thứ hai.
- Sau khi đổi cổng USB, reboot hoặc cập nhật kernel, luôn kiểm tra lại `/dev/usb/lp0` trước khi nhận yêu cầu in.
