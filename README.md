# Canon LBP2900 — Hồ sơ vận hành & khắc phục sự cố

Tài liệu nội bộ về chiếc **Canon LBP2900** (văn phòng Hà Nội, cắm USB vào máy `hn-kt-nam`), đúc kết từ một phiên chẩn đoán thực tế ngày 13/08/2026: máy "không in được", tưởng hỏng, cuối cùng **không hỏng gì cả** — toàn bộ là lỗi trạng thái phần mềm, và đã sửa xong từ xa.

Repo này gồm: chẩn đoán đầy đủ, script sửa lỗi dùng lại được, một CUPS backend để in từ Linux xuyên qua Windows, và một bản vá cho driver mã nguồn mở `captdriver`.

---

## TL;DR — máy không in, làm gì trước

Máy in vẫn sáng đèn, Windows vẫn thấy, nhưng job treo mãi không ra giấy:

```powershell
# chạy trên máy Windows cắm máy in, PowerShell với quyền admin
powershell -ExecutionPolicy Bypass -File scripts\windows\resetprint.ps1
```

Script sẽ: dọn hàng đợi → dừng Spooler → xoá spool → **disable/enable thiết bị USB** → chạy lại Spooler → bỏ cờ offline → in một trang thử → **tự chấm điểm** bằng bộ đếm của spooler.

Nếu sau đó vẫn không in: tắt nguồn máy in 10 giây, bật lại, chạy lại script. Vẫn không được nữa mới nghĩ tới phần cứng.

---

## Đặc điểm quan trọng của LBP2900

Hiểu ba điều này thì mọi triệu chứng kỳ quái đều có lời giải:

1. **Máy host-based (CAPT)** — không hiểu PCL/PostScript. Toàn bộ việc dựng trang do driver trên máy tính làm, máy in chỉ nhận bitmap nén qua giao thức CAPT độc quyền của Canon.

2. **Máy trạng thái CAPT rất dễ vỡ.** Rút cáp giữa chừng, job bị cắt ngang, driver lỗi — controller kẹt ở trạng thái lửng: vẫn trả lời truy vấn USB (device ID) nhưng **không nhận dữ liệu in**. Nhìn từ ngoài y hệt máy hỏng. Tắt bật nguồn hoặc reset thiết bị USB là sạch. Cộng đồng Linux ghi nhận mô hình này suốt ~15 năm, **không có báo cáo nào về hỏng vĩnh viễn**.

3. **Windows không biết khi nào máy in xong.** Driver CAPT không báo ngược tiến độ, nên job hay đọng ở `Printing, Retained` dù giấy đã ra. `PagesPrinted` trên job **không** chứng minh đã in — bộ đếm `TotalPagesPrinted` của spooler mới là thứ đáng tin (xem `printverify.ps1`).

---

## Vụ việc 13/08/2026 — chuỗi 4 lỗi chồng nhau

| # | Lỗi | Triệu chứng | Cách phát hiện |
|---|---|---|---|
| 1 | Cờ **`WorkOffline`** bật | Windows nhận job, không gửi xuống máy | `Win32_Printer.WorkOffline = True` |
| 2 | **Tầng USBPRINT hỏng trạng thái** sau khi cáp bị rút/cắm | Job đẩy được 1 trang đầu rồi nghẽn vĩnh viễn | Job treo `Printing`, `TotalPagesPrinted` không tăng |
| 3 | Job zombie chặn hàng đợi | Mọi job sau xếp hàng vô vọng | `Get-PrintJob` thấy job cũ `Retained` đứng đầu |
| 4 | (Trên Linux) kênh back-channel CUPS không truyền dữ liệu | captdriver chết ở lệnh CAPT đầu tiên | `CAPT: no reply from printer`; kernel kẹt `usblp_wwait` |

Nguyên nhân khởi phát: **rút cáp USB mang sang máy khác rồi cắm lại**. Windows tự đặt máy in offline khi thiết bị biến mất, và tầng USBPRINT không dựng lại kênh sạch sẽ khi thiết bị quay về.

Thứ tự sửa (đã kiểm chứng):

```
1. Bỏ cờ WorkOffline           (fixoffline.ps1)
2. Dọn job zombie              (purgeandtest.ps1)
3. Reset thiết bị USBPRINT     (resetprint.ps1 - bước quyết định)
4. Xác minh bằng bộ đếm        (printverify.ps1)
```

Kết quả cuối: job rời hàng đợi trong 4 giây, `TotalPagesPrinted 0 → 1`, giấy ra.

**Bài học đắt nhất:** đừng tin `PagesPrinted=1` trên job, và đừng tin exit code của ứng dụng in. Trong vụ này cả hai đều báo "thành công" trong khi trang chưa hề được xác nhận. Ba dấu hiệu phải cùng xuất hiện: job **tự rời** hàng đợi + `TotalPagesPrinted` **tăng** + giấy ra thật.

---

## Thư mục repo

```
scripts/windows/          Bộ script PowerShell chạy trên máy cắm máy in
  resetprint.ps1            Reset đầy đủ + in thử + tự chấm điểm  <- dùng cái này trước
  printverify.ps1           In kèm thu thập mọi bằng chứng (bộ đếm, event log)
  fixoffline.ps1            Bỏ cờ WorkOffline (WMI, fallback registry)
  purgeandtest.ps1          Dọn sạch hàng đợi, kể cả job lì
  canonstatus.ps1           Đọc trạng thái chi tiết (WMI DetectedErrorState...)

scripts/linux/            In từ Linux khi máy in cắm ở máy Windows
  winbridge                 CUPS backend: CUPS -> scp -> SumatraPDF -> driver Canon

captdriver-patch/         Cho trường hợp cắm máy in trực tiếp vào Linux
  direct-device-mode.patch  Vá captdriver nói thẳng /dev/usb/lp0

docs/
  windows-troubleshooting.md   Quy trình chẩn đoán từng bước trên Windows
  linux-bridge.md              Cài đặt bridge in từ Ubuntu qua Windows
  captdriver-notes.md          Ghi chép về driver Linux + bản vá
```

---

## In từ Linux — hai con đường

### Đường 1: bridge qua Windows (đang dùng, ổn định)

Máy in giữ nguyên ở máy Windows. Máy Linux in qua CUPS backend `winbridge`:

```
CUPS (queue Canon_LBP2900_Bridge, PPD Generic PDF)
  -> scp file PDF sang máy Windows (SSH key)
  -> SumatraPDF -print-to "Canon LBP2900" -silent
  -> driver Canon chính chủ dựng trang -> USB
```

Ưu: driver Windows chính chủ, ổn định. Nhược: máy Windows phải bật.
Chi tiết cài đặt: [`docs/linux-bridge.md`](docs/linux-bridge.md)

### Đường 2: cắm thẳng vào Linux + captdriver (thử nghiệm)

Driver mã nguồn mở [captdriver](https://github.com/mounaiban/captdriver) chạy được trên Ubuntu 24.04, **nhưng** trên máy chúng tôi kênh side/back-channel của CUPS không truyền dữ liệu, driver chết ở lệnh CAPT đầu tiên — đúng [Issue #16](https://github.com/agalakhov/captdriver/issues/16) tồn tại nhiều năm.

Bản vá trong `captdriver-patch/` thêm **chế độ nói thẳng `/dev/usb/lp0`** (bỏ qua kênh CUPS), đã đưa driver vượt qua điểm chết đó. Chưa in ra giấy thành công trọn vẹn vì đúng lúc test thì máy in đang kẹt trạng thái (lỗi #2 ở trên) — cần thử lại khi có dịp. Chi tiết: [`docs/captdriver-notes.md`](docs/captdriver-notes.md)

---

## Quy tắc vận hành rút ra

- **Đừng rút cáp USB máy in đang chia sẻ** trừ khi thật cần. Nếu rút, khi cắm lại hãy chạy `resetprint.ps1` luôn cho chắc.
- Máy in "đơ" ≠ máy in hỏng. Với LBP2900, 99% là trạng thái kẹt — reset USB + tắt bật nguồn giải quyết.
- Xoá job của người khác thì phải báo cho họ in lại — job `Retained` có thể đã in xong, nhưng job `Normal` phía sau thì chưa.
- Đèn LED trên máy là nguồn chân lý duy nhất về phần cứng: xanh đứng yên = khoẻ, cam/nháy = xem mực/giấy/nắp.
