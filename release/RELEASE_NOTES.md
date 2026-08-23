# captdriver 0.1.4.1 + direct-device patch 1

Release này cung cấp source driver `captdriver` đã áp patch direct-device để triển khai Canon LBP2900/LBP3000 trên máy chủ Linux dùng CUPS.

## Nội dung

- `captdriver-0.1.4.1-direct-device.1.tar.gz`: source đầy đủ đã áp patch.
- `captdriver-0.1.4.1-direct-device.1.tar.gz.sha256`: checksum kiểm tra gói source.
- `direct-device-mode.patch`: patch rời để áp lên upstream commit đã ghim.

## Nguồn và giấy phép

- Upstream: <https://github.com/mounaiban/captdriver>
- Upstream commit: `62719249ac34633338be54bc74beddd0e7003d38`
- Upstream version: `0.1.4.1`
- License: GNU GPL v3.0; file `COPYING` nằm trong gói source.

Đây là phần mềm không chính thức, không được Canon Inc. bảo trợ hoặc ủy quyền. Source đã sửa đổi được đánh dấu bằng `PATCH_INFO.md` và kèm nguyên patch trong gói.

## Cài đặt

Build trực tiếp trên máy chủ đích để dùng đúng kiến trúc và thư viện CUPS. Xem [hướng dẫn cài đặt, sử dụng và patch](https://github.com/digital-enterprise-projects/LBP2900/blob/main/docs/installation.md).

Không dùng asset release như một binary cài sẵn; đây là gói source có thể kiểm tra và tái build.
