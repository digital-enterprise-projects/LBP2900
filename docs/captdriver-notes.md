# captdriver + LBP2900 — ghi chép thử nghiệm và bản vá

Ghi lại từ phiên thử cắm LBP2900 **trực tiếp vào Ubuntu 24.04** (`hn-kt-thao`), 13–15/08/2026. Driver mã nguồn mở vướng lỗi kênh truyền của CUPS; bản vá trong repo này đưa nó vượt qua điểm chết và **đã in ra giấy thành công**.

## Bối cảnh driver

| Driver | Tình trạng |
|---|---|
| Canon CAPT chính chủ (`ccpd`) | **Hỏng hẳn** trên Ubuntu 24.04 — cập nhật lần cuối cho 14.04, sinh 70+ tiến trình zombie |
| [mounaiban/captdriver](https://github.com/mounaiban/captdriver) | Mã nguồn mở, reverse-engineered, còn bảo trì. LBP2900 được hỗ trợ. Hạn chế đã biết: kén tổ hợp kiến trúc/OS do vấn đề USB backend của CUPS |
| [agalakhov/captdriver](https://github.com/agalakhov/captdriver) | Repo gốc, có sẵn PPD LBP2900 |

## Cài đặt chuẩn (phần chạy được)

```bash
sudo apt install build-essential automake autoconf libcups2-dev cups-ppdc git
git clone https://github.com/mounaiban/captdriver && cd captdriver
autoreconf -i && ./configure && make
sudo install -m 0755 src/rastertocapt /usr/lib/cups/filter/
cd src && ppdc canon-lbp.drv -d /tmp/ppdgen        # sinh PPD từ chính repo
sudo install -m 0644 /tmp/ppdgen/CanonLBP-2900-3000.ppd /usr/share/ppd/
sudo lpadmin -p Canon_LBP2900 -E -v "usb://Canon/LBP2900?serial=<serial>" \
  -P /usr/share/ppd/CanonLBP-2900-3000.ppd
```

## Lỗi gặp phải và chẩn đoán

Triệu chứng: mọi job chết với

```
CAPT: send  A1 A1 04 00
CAPT: waiting for 6 bytes
ERROR: CAPT: no reply from printer
```

Trùng với [agalakhov#16](https://github.com/agalakhov/captdriver/issues/16) và [mounaiban#3](https://github.com/mounaiban/captdriver/issues/3) — mở nhiều năm, không có lời giải.

Chẩn đoán của chúng tôi (điểm mới so với các issue):

- Máy in **trả lời tốt** truy vấn IEEE-1284 device ID qua `ioctl` trực tiếp trên `/dev/usb/lp0` → phần cứng và kênh USB hai chiều đều thông.
- `cupsSideChannelDoRequest(GET_DEVICE_ID)` cũng chạy → side channel OK.
- Riêng **`cupsBackChannelRead()` không bao giờ nhận được byte nào** → back channel của backend `usb` (libusb) là mắt xích hỏng.
- Thử `file:///dev/usb/lp0` thay backend `usb`: chết sớm hơn, vì backend `file` **không có** side/back channel nào cả.

Kết luận: lỗi không nằm ở giao thức CAPT của driver (giao thức đúng), mà ở **đường vận chuyển phản hồi** qua CUPS trên tổ hợp máy này.

## Bản vá: chế độ nói thẳng thiết bị

`captdriver-patch/direct-device-mode.patch` — áp vào `src/capt-command.c`:

```bash
cd captdriver && patch -p1 < direct-device-mode.patch && make
```

Nội dung: khi mở được `/dev/usb/lp0` (module `usblp`), driver **tự đọc/ghi thiết bị**, bỏ qua toàn bộ kênh CUPS:

| Đường | Gốc | Sau vá |
|---|---|---|
| Gửi lệnh/dữ liệu | `fwrite(stdout)` → backend | `write(fd)` thẳng |
| Nhận phản hồi CAPT | `cupsBackChannelRead()` | `poll()` + `read(fd)` |
| Đọc device ID | side channel | `ioctl(LPIOC_GET_DEVICE_ID)` |
| Drain | side channel | không cần |

- Tự fallback về kênh CUPS nếu không mở được thiết bị.
- `CAPT_DEVICE=/dev/usb/lpN` để đổi thiết bị; `CAPT_DEVICE=""` tắt hẳn chế độ mới.
- Queue nên trỏ `-v file:///dev/null` (bật `FileDevice Yes` trong `cups-files.conf`) để backend CUPS không tranh thiết bị với filter.
- Cần `usblp` nạp sẵn: `echo usblp | sudo tee /etc/modules-load.d/usblp.conf`

## Kết quả và trạng thái

Sau vá, log lần đầu tiên vượt qua điểm chết:

```
CAPT: talking directly to /dev/usb/lp0
CAPT: printer ID string MFG:Canon;MDL:LBP2900;CMD:CAPT;VER:2.1
CAPT: detected printer 'LBP2900'
CAPT: send  A1 A1 04 00          <- không còn "no reply"
```

Sau đó kẹt ở `write()` (`usblp_wwait` trong kernel) — **nhưng** cùng thời điểm đó máy in đang kẹt trạng thái controller (nó cũng không nhận dữ liệu từ chính Windows). Vụ kẹt này sau được xử lý bằng reset USB phía Windows, còn máy in thì đã trả về máy Windows trước khi kịp thử lại bản vá trên nền máy in khoẻ.

### Cập nhật 15/08/2026 — bản vá ĐÃ IN ĐƯỢC

Sau khi máy in được trả về trạng thái khoẻ và cắm lại vào Ubuntu, bản vá hoạt động thật:

```
I [15/Aug/2026:08:46:16] [Job 109] Job completed.
so loi "CAPT: no reply|unable" trong error_log: 0
```

**Trạng thái: bản vá vượt qua lỗi #16 và in ra giấy thành công.** Đủ điều kiện gửi PR lên `mounaiban/captdriver` kèm chẩn đoán ở trên. Trước khi gửi nên sửa patch thành **fallback-only** (mặc định giữ kênh CUPS, chỉ chuyển sang thiết bị trực tiếp khi back channel lỗi) — không đổi hành vi của người đang dùng bình thường thì khả năng merge cao hơn nhiều.

### Điều kiện vận hành bắt buộc

Bản vá phụ thuộc `/dev/usb/lp0`. Mất node này là mọi job chết với `CAPT: unable to communicate with printer` — vì driver quay về kênh CUPS, mà queue lại dùng backend `file:///dev/null` không có side channel. Node biến mất sau mỗi lần reboot hoặc cắm lại cáp nếu `usblp` chưa được cấu hình tự nạp. Xem `lan-sharing.md`.

## Mẹo chẩn đoán nhanh khi "máy in không trả lời" trên Linux

```bash
# May in co song khong? (khong can driver gi)
sudo python3 -c "
import fcntl, os
fd = os.open('/dev/usb/lp0', os.O_RDWR)
buf = bytearray(1024)
fcntl.ioctl(fd, 0x84005001, buf)          # LPIOC_GET_DEVICE_ID
n = (buf[0]<<8 | buf[1])
print(buf[2:n].decode('latin-1'))
"
# Tra loi MFG:Canon;MDL:LBP2900... = phan cung + cap + USB OK
# -> loi nam o driver/kenh truyen, khong phai may in

# Tien trinh in dang ket o dau trong kernel?
sudo cat /proc/<pid>/wchan     # usblp_wwait = may in khong rut du lieu (controller ket / loi vat ly)
```
