# Chia sẻ LBP2900 ra LAN từ máy Linux

Cấu hình đang chạy (15/08/2026): máy in cắm USB vào **`hn-kt-thao`** (Ubuntu 24.04, `192.168.1.36`), dùng `captdriver` đã vá, chia sẻ ra LAN qua CUPS. Các máy Windows và Linux khác in vào đó qua IPP.

```
Canon LBP2900 (USB)
  -> hn-kt-thao: usblp -> /dev/usb/lp0 -> captdriver (da va) -> CUPS
  -> chia se IPP tren 0.0.0.0:631
  -> may Windows / Linux khac trong LAN
```

## Phía server (`hn-kt-thao`)

### Bắt buộc: `/dev/usb/lp0` phải tồn tại

Bản vá captdriver nói **thẳng** với thiết bị này. Không có nó, driver quay về kênh CUPS, mà queue dùng backend `file:///dev/null` (không có side channel) nên mọi job chết với:

```
CAPT: unable to communicate with printer
```

Đây là lỗi số một sau mỗi lần khởi động lại hoặc cắm lại cáp. Cách xử lý:

```bash
sudo modprobe usblp
ls -l /dev/usb/lp0          # phai co
echo usblp | sudo tee /etc/modules-load.d/usblp.conf    # tu nap sau reboot
```

Nếu `modprobe` xong vẫn chưa có node, reset cổng USB:

```bash
P=$(for d in /sys/bus/usb/devices/*/; do [ "$(cat $d/idVendor 2>/dev/null)" = "04a9" ] && basename $d; done | head -1)
sudo bash -c "echo 0 > /sys/bus/usb/devices/$P/authorized"; sleep 3
sudo bash -c "echo 1 > /sys/bus/usb/devices/$P/authorized"
```

Kiểm tra máy in còn sống mà **không in gì**:

```bash
sudo python3 -c "
import fcntl, os
fd = os.open('/dev/usb/lp0', os.O_RDWR); buf = bytearray(1024)
fcntl.ioctl(fd, 0x84005001, buf); n = (buf[0]<<8)|buf[1]
print(buf[2:n].decode('latin-1'))"
# -> MFG:Canon;MDL:LBP2900;CMD:CAPT;VER:2.1;...
```

### Tạo queue và bật chia sẻ

```bash
# FileDevice can thiet cho URI file://
grep -q "^FileDevice Yes" /etc/cups/cups-files.conf || echo "FileDevice Yes" | sudo tee -a /etc/cups/cups-files.conf

sudo lpadmin -p Canon_LBP2900 -E \
  -v file:///dev/null \
  -P /usr/share/ppd/CanonLBP-2900-3000.ppd \
  -D "Canon LBP2900 (captdriver, direct USB)"

sudo cupsctl --share-printers --remote-any
sudo lpadmin -p Canon_LBP2900 -o printer-is-shared=true
sudo systemctl restart cups
```

`-v file:///dev/null` là cố ý: filter đã tự ghi thẳng `/dev/usb/lp0`, nên backend CUPS không được tranh thiết bị. Kiểm tra `sudo ss -lntp | grep 631` phải thấy `0.0.0.0:631`, không phải `127.0.0.1`.

## Phía client Windows

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows-clients\addipp.ps1
```

Script tự tạo cổng IPP, chọn driver PostScript có sẵn (`Microsoft PS Class Driver`), thêm máy in tên `Canon LBP2900 (LAN)`, và **không** đổi máy in mặc định.

Quan trọng: máy Windows dùng **driver PostScript chung**, tuyệt đối không cài driver Canon. CUPS phía Linux nhận PostScript rồi mới chuyển sang CAPT.

Làm tay: Settings → Printers → Add printer → *"The printer that I want isn't listed"* → Select a shared printer by name:

```
http://192.168.1.36:631/printers/Canon_LBP2900
```

Kiểm tra sau khi cài:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\windows-clients\checkconn.ps1
```

In ra trạng thái máy in, kết quả TCP tới cổng 631, và mã HTTP của endpoint IPP.

**Chạy qua SSH có làm phiền người dùng không?** Không. `Add-Printer` không bật cửa sổ nào, không cần khởi động lại, không đổi máy in mặc định. Ứng dụng đang mở sẵn hộp thoại In có thể phải đóng/mở lại hộp thoại mới thấy máy in mới.

## Phía client Linux

```bash
sudo systemctl enable --now cups
sudo lpadmin -p Canon_LBP2900 -E \
  -v ipp://192.168.1.36:631/printers/Canon_LBP2900 -m everywhere
```

### Bẫy: kho apt offline nội bộ

Trên `hn-02` (máy có phần mềm Flygo), CUPS **không cài được** vì kho offline `/usr/local/share/flygo/assets/offline/apt` giữ vài thư viện ở bản **cao hơn** kho Ubuntu, phá vỡ mọi phụ thuộc gắn chính xác phiên bản:

| Gói | Kho offline | Kho Ubuntu |
|---|---|---|
| `libcups2t64` | `2.4.7-1.2ubuntu7.14` | `2.4.7-1.2ubuntu7.4` |
| `libpoppler134` | `24.02.0-1ubuntu9.9` | `24.02.0-1ubuntu9.7` |

Cách xử lý (hạ hai gói này về bản Ubuntu, rồi cài CUPS bình thường):

```bash
sudo apt-get install -y --allow-downgrades libcups2t64=2.4.7-1.2ubuntu7.4
sudo apt-get install -y --allow-downgrades libpoppler134=24.02.0-1ubuntu9.7
sudo apt-get install -y cups cups-client
```

Lỗi dẫn đường khá vòng vo: đầu tiên báo `cups-client` xung đột `libcups2t64`, hạ xong lại báo `libcupsfilters2t64 không thể cài được`, đào tiếp mới lộ `libpoppler-cpp0t64` cần `libpoppler134 = .7`. Cứ cài thẳng gói bị kêu là lộ nguyên nhân thật.

## Dọn dẹp khi đổi chỗ máy in

Khi chuyển cáp USB sang máy khác, **nhớ xoá queue cũ** trỏ vào cổng không còn thiết bị — nếu không, ai in vào đó sẽ treo vô thời hạn:

```powershell
Remove-Printer -Name "Canon LBP2900"       # queue tro vao USB001 cu
```

Và trên máy Windows từng cắm máy in, kiểm tra cờ `WorkOffline` (xem `windows-troubleshooting.md`).

## Hiện trạng triển khai

| Máy | Vai trò | Trạng thái |
|---|---|---|
| `hn-kt-thao` (192.168.1.36) | Server, cắm USB | CUPS chia sẻ `0.0.0.0:631` |
| `hn-kt-duyen` (.17) | Client Windows | Đã thêm, IPP `200 OK` |
| `hn-kt-hue` (.20) | Client Windows | Đã thêm, IPP `200 OK` |
| `hn-kt-my` (.15) | Client Windows | Đã thêm, IPP `200 OK` |
| `hn-kt-nam` (.19) | Client Windows | Đã thêm, IPP `200 OK` |
| `hn-02` (.29) | Client Linux | Đã thêm qua IPP |

Client nhìn thấy **hàng đợi dùng chung** của server, nên job lỗi trên server sẽ hiện trong danh sách in của mọi máy — dọn hàng đợi khi có job hỏng để tránh gây bối rối.
