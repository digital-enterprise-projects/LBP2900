# Script PowerShell — chạy trên máy Windows cắm máy in

Tất cả chạy bằng PowerShell quyền admin:

    powershell -ExecutionPolicy Bypass -File <script>.ps1

| Script | Việc | Có tác dụng phụ? |
|---|---|---|
| `canonstatus.ps1` | Đọc trạng thái chi tiết (WorkOffline, DetectedErrorState, hàng đợi) | Không — chỉ đọc |
| `fixoffline.ps1` | Bỏ cờ "Use Printer Offline" qua WMI, fallback registry | Có |
| `purgeandtest.ps1` | Xoá toàn bộ job; job lì thì dọn thẳng thư mục spool | Có — job bị xoá là mất |
| `resetprint.ps1` | Reset trọn gói: queue + spool + thiết bị USB + Spooler, rồi in thử và tự chấm điểm bằng bộ đếm | Có — in 1 trang thử (cần `C:\Windows\Temp\sample-verify.pdf`) |
| `printverify.ps1` | In 1 trang kèm thu thập đủ 4 lớp bằng chứng | Có — in 1 trang |

Tên máy in mặc định là `Canon LBP2900` — sửa biến `$name` ở đầu file nếu khác.
