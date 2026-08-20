# Limited Travel Card — Prototype

แอป Flutter (มือถือ + เว็บ) + backend Node.js/SQLite ที่สร้างจากเอกสารออกแบบ `273edit.docx`
(แพลตฟอร์มการท่องเที่ยวเชิงสะสม "Limited Travel Card")

> **หมายเหตุตำแหน่งไฟล์:** โปรเจกต์นี้อยู่ที่ `C:\Users\NITRO\Travel_Project_dev` ไม่ใช่ `D:\Travel_Project`
> เพราะโฟลเดอร์ `D:\Travel_Project` ไม่มีสิทธิ์เขียนไฟล์ในเซสชันนี้ (Users มีแค่ Read/Execute)
> ถ้าจะย้ายไป D: ให้แก้สิทธิ์โฟลเดอร์ก่อน (คลิกขวา > Properties > Security > แก้สิทธิ์ผู้ใช้ให้เป็น Modify/Full control) แล้วค่อย copy ทั้งโฟลเดอร์ไป

## โครงสร้าง

```
backend/   Node.js + Express + SQLite (better-sqlite3) — REST API ตาม ER Diagram ในเอกสาร
mobile/    Flutter app (Dart) — ใช้ Provider, flutter_map, qr_flutter, http
```

## วิธีรัน

**1) Backend** (ต้องรันก่อนเสมอ ฟังที่ port 4000)
```
cd backend
npm install     # ครั้งแรกเท่านั้น
npm start
```
ครั้งแรกที่รันจะสร้างฐานข้อมูล SQLite ที่ `backend/data/app.db` และ seed ข้อมูลตัวอย่างให้อัตโนมัติ
(สถานที่ท่องเที่ยว 6 แห่ง, ภารกิจ, การ์ด, ร้านค้าพันธมิตร, บัญชีตัวอย่าง `demo_traveler` / `demo1234`)

**2) Flutter app**
```
cd mobile
flutter pub get   # ครั้งแรกเท่านั้น
flutter run -d chrome        # รันบนเว็บ (เห็นผลไวสุด)
# หรือ
flutter run                  # รันบน Android emulator/device ที่เปิดไว้
```

> **สำคัญสำหรับ Android emulator:** API base URL ถูก hardcode ไว้ที่ `http://localhost:4000/api`
> ใน `mobile/lib/services/api_client.dart` ซึ่งใช้ได้กับเว็บ/iOS simulator เท่านั้น
> ถ้ารันบน Android emulator ต้องเปลี่ยนเป็น `http://10.0.2.2:4000/api` ก่อน (emulator ใช้ IP นี้แทน localhost ของเครื่อง)

## บัญชีตัวอย่าง

- Username: `demo_traveler`
- Password: `demo1234`

หรือกด "สมัครสมาชิก" เพื่อสร้างบัญชีใหม่ (มีขั้นตอนสแกนใบหน้าจำลอง ไม่ใช่ AI จริงตามที่ระบุไว้ในเอกสารว่านอกขอบเขต prototype)

## ขอบเขตที่ทำ (ตาม flow หลักในเอกสาร)

- สมัครสมาชิก + สแกนใบหน้า (จำลอง)
- ล็อกอิน
- แผนที่ท่องเที่ยว: หมุดสถานที่, ภารกิจ, ร้านค้าพันธมิตร, Booking services (mock)
- เช็คอิน: QR code แบบ dynamic + นับถอยหลัง + สถานะยืนยัน (Device/GPS/Bluetooth — จำลองผลเป็นสำเร็จเสมอ ตามที่เอกสารระบุว่า anti-spoofing จริงอยู่นอกขอบเขต prototype)
- ระบบภารกิจ → ปลดล็อกการ์ดอัตโนมัติเมื่อเช็คอินสำเร็จ
- คลังการ์ด (grid), โอนการ์ดให้ผู้ใช้อื่น, สั่งพิมพ์การ์ดจริง (order)
- คอมมูนิตี้: โพสต์ข้อความ+อีโมจิ, ไลก์, คอมเมนต์
- โปรไฟล์: สถิติ, ระดับนักสะสม, ประวัติการเดินทาง

**ไม่ได้ทำ** (นอกขอบเขต prototype ตามที่เอกสารระบุไว้เอง): NFC/BLE จริง, AI liveness detection จริง,
ระบบชำระเงินจริง, การเชื่อมต่อ Booking.com API จริง, เว็บพอร์ทัล Admin/Partner แบบเต็ม (ข้อมูล mock อยู่ใน backend แล้ว
แต่ยังไม่มีหน้าเว็บจัดการ)

## ทดสอบแล้ว

ทดสอบ flow เต็มรูปแบบผ่าน browser จริงแล้ว: สมัครสมาชิก → ล็อกอิน → เช็คอิน → ได้การ์ดจากภารกิจ →
ดูคลังการ์ด → โอนการ์ดให้ผู้ใช้อื่น → โพสต์คอมมูนิตี้ → ดูโปรไฟล์/ประวัติ ทำงานถูกต้องทั้งหมด
