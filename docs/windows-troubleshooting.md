# Chẩn đoán LBP2900 trên Windows — từng bước

Máy in cắm USB vào một máy Windows (hiện là `hn-kt-nam`). Quy trình dưới đây đi từ nhẹ tới nặng — dừng ngay khi in được.

## Bước 0 — Đọc trạng thái trước đã, đừng đoán

```powershell
powershell -ExecutionPolicy Bypass -File canonstatus.ps1
```

Ba trường quyết định:

| Trường | Giá trị xấu | Nghĩa |
|---|---|---|
| `WorkOffline` | `True` | Windows đang giữ job lại, không gửi xuống máy |
| `DetectedErrorState` | `4`=hết giấy, `6`=hết mực, `7`=mở nắp, `8`=kẹt giấy | Lỗi vật lý — ra máy xử lý, phần mềm vô can |
| `PrinterStatus` | `1`/`2` = mơ hồ | Thường đi kèm trạng thái kẹt |

`DetectedErrorState = 0` (Unknown) **không** có nghĩa là có lỗi — máy host-based nhiều khi không báo gì.

## Bước 1 — Bỏ cờ offline

```powershell
powershell -ExecutionPolicy Bypass -File fixoffline.ps1
```

Cờ này tự bật khi Windows mất thiết bị USB (rút cáp, mất điện) và **không tự tắt** khi thiết bị quay lại. Đây là lỗi phổ biến nhất và dễ sửa nhất.

## Bước 2 — Dọn hàng đợi

```powershell
powershell -ExecutionPolicy Bypass -File purgeandtest.ps1
```

Job đầu hàng đợi ở trạng thái `Printing, Retained` với `PagesPrinted` đứng yên nhiều phút = job zombie, chặn mọi thứ phía sau. Script xoá từng job; job nào lì thì dừng Spooler, xoá thẳng `C:\Windows\System32\spool\PRINTERS\*`, chạy lại.

Lưu ý: xoá là mất — báo người gửi in lại những job chưa ra giấy.

## Bước 3 — Reset thiết bị USB (chìa khoá của vụ 13/08)

```powershell
powershell -ExecutionPolicy Bypass -File resetprint.ps1
```

Tầng USBPRINT của Windows có thể hỏng trạng thái sau khi cáp bị rút/cắm: nhận job, đẩy được một ít dữ liệu, rồi nghẽn vĩnh viễn — không lỗi, không timeout. `Disable-PnpDevice` → đợi → `Enable-PnpDevice` buộc Windows dựng lại kênh từ đầu.

Script làm trọn gói: dọn queue → reset USB → restart Spooler → in thử → so bộ đếm.

## Bước 4 — Đọc kết quả cho đúng

Ba tín hiệu **phải cùng có** thì mới là in thành công:

1. Job **tự rời** hàng đợi (không phải mình xoá)
2. Bộ đếm `TotalPagesPrinted` của spooler **tăng**
3. Giấy ra thật

Những thứ **không** chứng minh gì (đã bị lừa trong vụ 13/08):

- Exit code 0 của SumatraPDF/ứng dụng — chỉ nghĩa là đã nộp job cho spooler
- `PagesPrinted=1` trên job — chỉ nghĩa là spooler đã đưa dữ liệu cho cổng
- Job biến mất sau khi **mình** xoá

`printverify.ps1` thu thập cả ba lớp bằng chứng tự động.

## Bước 5 — Vẫn không được

1. Tắt nguồn máy in, đợi 10 giây, bật lại, đợi đèn xanh ổn định, chạy lại Bước 3
2. Đổi cáp USB / đổi cổng (LBP2900 kén hub — cắm thẳng vào máy)
3. Nhìn đèn LED: cam hoặc nháy → mực/giấy/nắp/kẹt giấy
4. Hết cả 3 mục trên mới nghĩ tới hỏng phần cứng

## Ghi chú về job `Printing, Retained` không bao giờ kết thúc

Driver CAPT không báo ngược "đã in xong trang cuối" một cách đáng tin, nên spooler đôi khi giữ job ở `Printing` mãi dù giấy đã ra. Nếu giấy ra đều mà job cứ đọng: cứ xoá mục đọng đi, đó là vấn đề hiển thị. Chỉ lo lắng khi `TotalPagesPrinted` không tăng.
