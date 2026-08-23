# Hướng dẫn cài đặt và sử dụng

Có hai cách lấy driver:

1. Dùng gói source đã áp patch từ GitHub Release — phù hợp để triển khai nhanh và tái lập đúng phiên bản.
2. Clone source upstream rồi tự áp patch — phù hợp khi cần kiểm tra thay đổi hoặc port patch sang phiên bản mới.

Cả hai cách đều build driver trực tiếp trên máy chủ Linux để liên kết đúng kiến trúc CPU và thư viện CUPS của máy đó.

## Yêu cầu hệ thống

- Ubuntu 22.04/24.04 hoặc Debian tương đương.
- Canon LBP2900/LBP3000 kết nối USB trực tiếp.
- Quyền `sudo`.
- Kết nối Internet ở bước tải source và package.
- IP tĩnh/DHCP reservation cho máy chủ nếu chia sẻ qua LAN.

## Cách A — cài từ GitHub Release

Đặt phiên bản release và thư mục làm việc:

```bash
RELEASE_TAG="captdriver-0.1.4.1-direct-device.1"
PACKAGE="captdriver-0.1.4.1-direct-device.1"
WORK_DIR="/tmp/lbp2900-install"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
```

Tải source và checksum:

```bash
curl -fLO "https://github.com/digital-enterprise-projects/LBP2900/releases/download/$RELEASE_TAG/$PACKAGE.tar.gz"
curl -fLO "https://github.com/digital-enterprise-projects/LBP2900/releases/download/$RELEASE_TAG/$PACKAGE.tar.gz.sha256"
sha256sum -c "$PACKAGE.tar.gz.sha256"
tar -xzf "$PACKAGE.tar.gz"
cd "$PACKAGE"
```

Nếu hệ thống không có `sha256sum`, dùng:

```bash
shasum -a 256 -c "$PACKAGE.tar.gz.sha256"
```

Kiểm tra `PATCH_INFO.md`, `COPYING` và `DIRECT_DEVICE_PATCH.patch` trước khi build.

## Cách B — clone và tự áp patch

```bash
REPO_DIR="/tmp/LBP2900"
WORK_DIR="/tmp/lbp2900-build"
UPSTREAM_COMMIT="62719249ac34633338be54bc74beddd0e7003d38"

git clone https://github.com/digital-enterprise-projects/LBP2900.git "$REPO_DIR"
git clone https://github.com/mounaiban/captdriver.git "$WORK_DIR"
git -C "$WORK_DIR" checkout "$UPSTREAM_COMMIT"
git -C "$WORK_DIR" apply --check "$REPO_DIR/captdriver-patch/direct-device-mode.patch"
git -C "$WORK_DIR" apply "$REPO_DIR/captdriver-patch/direct-device-mode.patch"
git -C "$WORK_DIR" diff --check
git -C "$WORK_DIR" diff -- src/capt-command.c
cd "$WORK_DIR"
```

`git apply --check` phải hoàn tất không có lỗi. Nếu upstream đã thay đổi và patch không còn áp dụng sạch, dừng lại để review; không dùng `--reject` rồi cài một bản source chưa xác định.

## Build và cài driver

Chạy trong thư mục source của Cách A hoặc Cách B:

```bash
sudo apt update
sudo apt install -y build-essential automake autoconf libcups2-dev cups cups-client cups-ppdc

autoreconf -i
./configure
make -j"$(nproc)"

sudo install -m 0755 src/rastertocapt /usr/lib/cups/filter/rastertocapt
mkdir -p /tmp/captdriver-ppd
(cd src && ppdc canon-lbp.drv -d /tmp/captdriver-ppd)
sudo install -m 0644 /tmp/captdriver-ppd/CanonLBP-2900-3000.ppd \
  /usr/share/ppd/CanonLBP-2900-3000.ppd
```

Xác nhận file đã cài:

```bash
ls -l /usr/lib/cups/filter/rastertocapt
ls -l /usr/share/ppd/CanonLBP-2900-3000.ppd
```

## Cấu hình USB

```bash
echo usblp | sudo tee /etc/modules-load.d/usblp.conf
sudo modprobe usblp
lsusb | grep -i canon
ls -l /dev/usb/lp0
```

Không tiếp tục nếu `/dev/usb/lp0` chưa tồn tại. Xem phần chẩn đoán trong [ghi chú captdriver](captdriver-notes.md).

## Tạo queue và bật chia sẻ

Thay các giá trị mẫu trước khi chạy:

```bash
QUEUE_NAME="Canon_LBP2900"
LAN_CIDR="192.168.10.0/24"

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
sudo ufw allow from "$LAN_CIDR" to any port 631 proto tcp
```

Nếu không dùng UFW, cấu hình firewall tương đương. Không mở cổng 631 ra Internet.

## In thử trên máy chủ

```bash
lpstat -t
lp -d "$QUEUE_NAME" /usr/share/cups/data/testprint
watch -n 1 lpstat -W not-completed -o
```

Đọc log:

```bash
sudo tail -n 200 /var/log/cups/error_log
sudo journalctl -u cups --since '10 minutes ago' --no-pager
```

Direct-device hoạt động khi log có dòng `CAPT: talking directly to /dev/usb/lp0` và không có lỗi giao tiếp CAPT.

## Thêm máy trạm Windows

Sao chép thư mục `scripts/windows-clients` sang máy trạm hoặc clone repository. Mở PowerShell Administrator:

```powershell
.\scripts\windows-clients\addipp.ps1 `
  -Server 192.168.10.20 `
  -QueueName Canon_LBP2900 `
  -PrinterName "Canon LBP2900 - Van phong"

.\scripts\windows-clients\checkconn.ps1 `
  -Server 192.168.10.20 `
  -QueueName Canon_LBP2900 `
  -PrinterName "Canon LBP2900 - Van phong"
```

Thay IP theo máy chủ thực tế. Script không đổi máy in mặc định.

## Thêm máy trạm Linux

```bash
PRINT_SERVER_IP="192.168.10.20"
QUEUE_NAME="Canon_LBP2900"

sudo apt install -y cups-client
sudo lpadmin -p "$QUEUE_NAME" -E \
  -v "ipp://$PRINT_SERVER_IP:631/printers/$QUEUE_NAME" \
  -m everywhere
lp -d "$QUEUE_NAME" /usr/share/cups/data/testprint
```

## Cập nhật patch hoặc upstream

1. Clone commit upstream mới vào một thư mục tạm.
2. Chạy `git apply --check` với patch hiện tại.
3. Nếu áp dụng sạch, build và test trên một máy không ảnh hưởng vận hành.
4. Nếu không sạch, chỉnh patch trên source mới và review toàn bộ `git diff`.
5. Ghim commit upstream mới trong script build release và `PATCH_INFO.md`.
6. Tạo phiên bản release mới; không thay asset của release cũ.

## Hoàn tác

```bash
sudo lpadmin -x Canon_LBP2900
sudo rm -f /usr/lib/cups/filter/rastertocapt
sudo rm -f /usr/share/ppd/CanonLBP-2900-3000.ppd
sudo systemctl restart cups
```

Các lệnh trên xóa queue và hai file đã cài, không xóa source. Chỉ chạy sau khi đã xử lý hoặc thông báo về mọi job còn trong queue.
