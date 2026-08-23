# captdriver direct-device cho Canon LBP2900

Canon LBP2900 là máy in host-based: máy tính phải chuyển trang in sang giao thức CAPT trước khi gửi qua USB. Repository này dùng `captdriver` mã nguồn mở và bổ sung chế độ truy cập trực tiếp thiết bị `usblp` để tránh lỗi back-channel trên một số tổ hợp CUPS/libusb.

## Khi nào cần bản vá

Bản vá phù hợp khi có đủ các dấu hiệu sau:

- `lsusb` nhìn thấy máy in Canon.
- `/dev/usb/lp0` tồn tại và đọc được IEEE-1284 device ID.
- `captdriver` chưa vá dừng ở lệnh CAPT đầu tiên với `CAPT: no reply from printer`.
- Backend USB của CUPS không chuyển phản hồi từ máy in về filter qua `cupsBackChannelRead()`.

Nếu không có `/dev/usb/lp0`, hãy xử lý module `usblp`, cáp và cổng USB trước. Bản vá không sửa lỗi phần cứng hoặc lỗi kết nối vật lý.

## Cơ chế

File [direct-device-mode.patch](../captdriver-patch/direct-device-mode.patch) thay đổi `src/capt-command.c`:

| Chức năng | captdriver mặc định | Chế độ direct-device |
|---|---|---|
| Gửi lệnh/dữ liệu | ghi ra `stdout` cho backend CUPS | `write()` trực tiếp vào `/dev/usb/lpN` |
| Nhận phản hồi CAPT | `cupsBackChannelRead()` | `poll()` và `read()` trực tiếp |
| Đọc device ID | CUPS side-channel | `ioctl(LPIOC_GET_DEVICE_ID)` |
| Khi không mở được thiết bị | không áp dụng | fallback về CUPS channel |

Thiết bị mặc định là `/dev/usb/lp0`.

- Đặt `CAPT_DEVICE=/dev/usb/lp1` để chọn node khác.
- Đặt `CAPT_DEVICE=` để tắt direct-device và dùng hành vi gốc.

## Build và cài đặt

```bash
REPO_DIR="$PWD"

sudo apt update
sudo apt install -y build-essential automake autoconf libcups2-dev cups-ppdc git patch
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

Sau mỗi lần cập nhật source `captdriver`, chạy lại patch và build. Nếu `patch` báo hunk failed, không tiếp tục cài binary cũ; cần kiểm tra thay đổi upstream và cập nhật patch.

## Cấu hình `usblp`

```bash
echo usblp | sudo tee /etc/modules-load.d/usblp.conf
sudo modprobe usblp
ls -l /dev/usb/lp*
```

Kiểm tra device ID:

```bash
sudo python3 - <<'PY'
import fcntl
import os

path = os.environ.get("CAPT_DEVICE", "/dev/usb/lp0")
fd = os.open(path, os.O_RDWR)
try:
    data = bytearray(1024)
    fcntl.ioctl(fd, 0x84005001, data)
    size = (data[0] << 8) | data[1]
    print(data[2:size].decode("latin-1"))
finally:
    os.close(fd)
PY
```

Chuỗi trả về phải nhận diện đúng nhà sản xuất, model và `CMD:CAPT`.

## Cấu hình CUPS bắt buộc

Direct-device tự giữ `/dev/usb/lpN`, vì vậy backend của queue không được giữ cùng thiết bị:

```bash
grep -q '^FileDevice Yes$' /etc/cups/cups-files.conf || \
  echo 'FileDevice Yes' | sudo tee -a /etc/cups/cups-files.conf

sudo lpadmin -p Canon_LBP2900 -E \
  -v file:///dev/null \
  -P /usr/share/ppd/CanonLBP-2900-3000.ppd
sudo systemctl restart cups
```

Không dùng `usb://Canon/...` cho queue này khi direct-device đang bật.

## Máy chủ có nhiều thiết bị `/dev/usb/lpN`

Số thứ tự `lpN` có thể đổi sau reboot. Với môi trường nhiều máy in USB, tạo symlink ổn định bằng udev và truyền đường dẫn đó qua `CAPT_DEVICE` cho CUPS.

Ví dụ quy tắc `/etc/udev/rules.d/70-canon-lbp2900.rules`:

```udev
SUBSYSTEM=="usb", ATTR{idVendor}=="04a9", ATTR{idProduct}=="2676", SYMLINK+="canon-lbp2900"
```

Mã `idProduct` phải lấy từ `lsusb` trên thiết bị thực tế, không sao chép máy móc từ ví dụ. Sau đó cấu hình biến môi trường của service CUPS theo cơ chế của bản phân phối để `CAPT_DEVICE=/dev/canon-lbp2900`, rồi restart CUPS.

## Đọc log

```bash
sudo grep -E 'CAPT:|Unable|Error' /var/log/cups/error_log | tail -n 100
sudo journalctl -u cups --since '10 minutes ago' --no-pager
```

Các thông báo chính:

| Log | Ý nghĩa | Hành động |
|---|---|---|
| `CAPT: talking directly to ...` | direct-device đã mở thành công | tiếp tục theo dõi job |
| `CAPT: no direct device ... falling back` | không mở được node đã cấu hình | kiểm tra `CAPT_DEVICE`, `usblp`, permission |
| `CAPT: no reply from printer` | không nhận được phản hồi CAPT | kiểm tra patch đang chạy, USB và trạng thái máy in |
| `CAPT: cannot write to printer` | ghi xuống thiết bị thất bại | kiểm tra cáp, nguồn, kernel log |
| `CAPT: unable to communicate` | cả direct-device và channel dự phòng đều không dùng được | khôi phục device node rồi restart CUPS |

Kiểm tra kernel khi tiến trình bị treo:

```bash
sudo dmesg --ctime | tail -n 100
sudo cat /proc/<PID>/wchan
```

`usblp_wwait` kéo dài cho thấy tiến trình đang chờ thiết bị nhận dữ liệu; cần kiểm tra trạng thái máy in, USB và nguồn trước khi thay đổi driver.

## Hoàn tác

Để quay về captdriver nguyên bản:

1. Build lại source sạch không áp patch.
2. Cài lại `rastertocapt`.
3. Đổi URI queue sang backend USB phù hợp.
4. Đặt `CAPT_DEVICE=` hoặc bỏ cấu hình biến môi trường.
5. Restart CUPS và in trang thử.
