# DroneCam + DroneControl

Dua aplikasi Swift/SwiftUI native untuk akuisisi foto udara dan ground station lokal. Implementasi tahap pertama berbasis riset; **belum lulus validasi kamera fisik/penerbangan dan belum layak dinyatakan sistem survei produksi**.

- Target Xcode `DroneMapping` → DroneCam (iOS 17+).
- Target Xcode `ControlDroneMapping` → DroneControl (macOS 14+).
- Proyek dibuat dengan Xcode 27; format project mengikuti workspace yang sudah ada.
- Capture, kontrol, dan transfer tidak memerlukan backend, akun, atau internet. Pengolahan orthomosaic lokal memakai engine OpenSfM yang disertakan dalam aplikasi Mac.

## Yang tersedia

Kontrol ISO, shutter, WB temperature/tint atau gain gray card, fokus manual, interval, dan target jumlah foto. Kamera wide fisik; kemampuan RAW dan rentang parameter dideteksi dari perangkat. JPEG atau Bayer DNG+JPEG pada dimensi maksimum format aktif, metadata asli EXIF, sidecar waktu/GNSS/akurasi, checksum SHA-256. Penjadwal lokal tetap berjalan saat Mac terputus. Capture terinterupsi dijeda; slot yang terlambat dicatat. UI telemetry baterai, suhu, disk, foto tersimpan/terlewat, dan status koneksi. Transfer dataset lokal terenkripsi, checksum diverifikasi di Mac, serta folder yang bisa dibuka melalui Finder. Referensi pre/post dan WB gray card tersedia; pembuatan profil warna otomatis belum tersedia.

## Menjalankan

Untuk clone baru atau komputer teman, ikuti **[Setup developer dan kolaborasi GitHub](docs/DEVELOPMENT_SETUP.md)** terlebih dahulu: konfigurasi akun lokal → pasang engine dengan versi terkunci → kemas dengan identitas Apple sendiri → build. Runtime besar tidak disimpan di Git; script mengambil dependensi yang diperlukan.

1. Buka `DroneMapping.xcodeproj` di Xcode. Isi Team ID dan prefix bundle pribadi melalui `Config/Developer.local.xcconfig` sesuai panduan setup; file ini tidak ikut Git.
2. Pilih scheme `DroneMapping`, pilih iPhone fisik, Build & Run. Izinkan Kamera, Local Network, dan Location (opsional untuk geotag perkiraan).
3. Jalankan scheme `ControlDroneMapping` pada Mac. Aktifkan Wi-Fi kedua perangkat; jaringan lokal tidak membutuhkan internet. Peer-to-peer harus diuji pada perangkat aktual.
4. Pada iPhone kamera disiapkan otomatis saat aplikasi dibuka; berikan izin jika diminta. Pada Mac buka panel **Perangkat**, pilih peer DroneCam, lalu setujui undangan pada iPhone. Setup dan koneksi drone dibuka melalui **QGroundControl** di panel Perangkat.
5. Pilih **Buat misi**, isi nama, lalu misi muncul di kartu **Misi terbaru** pada Ringkasan. **Lihat misi** atau menu **Misi** membuka daftar seluruh misi tersimpan; menu **⋯** pada setiap misi menyediakan **Ubah nama** dan **Hapus misi**.
6. Pilih **Buka misi** untuk mengatur **Area scan misi ini**: pilih kebun tersimpan, impor batas GeoJSON, atau aktifkan **Gambar batas** dan klik minimal tiga titik pada peta. Titik dapat digeser, ditambah melalui koordinat manual, atau dihapus. Area, pengaturan survei/kamera, dan rute waypoint disimpan terpisah untuk setiap misi. Daftar misi tersimpan otomatis di Mac, termasuk setelah diterima iPhone dan aplikasi ditutup. Panel Misi berisi area dan rencana survei, indikator kesiapan iPhone, serta tombol **Mulai capture**. Setup perangkat berada di panel **Perangkat**: pilih **Misi untuk persiapan**, lalu **Siapkan misi di iPhone**. Membuat misi atau menghubungkan perangkat saja tidak mengirim misi.
7. Di **Misi**, isi tinggi AGL, kecepatan, target GSD dan overlap, lalu periksa rencana terbang. Di **Perangkat**, lakukan persiapan kamera otomatis atau isi rekomendasi dari survei, sesuaikan ISO/fokus/format, lalu **Terapkan kamera**. Kamera, white balance, kalibrasi, foto uji, dan pemeriksaan hasil berada di panel Perangkat.
8. Di **Perangkat**, bila gray card dipilih: **Kunci WB → Simpan referensi → keluarkan kartu → Ambil foto uji**. Checklist terbuka setelah foto uji tersimpan. Unduh asli untuk inspeksi ketajaman; lakukan uji cadence dan lengkapi pemeriksaan lapangan.
9. Kembali ke **Misi**. Tombol **Mulai capture • 3–2–1** tersedia di bawah layar dan aktif ketika indikator iPhone siap capture. Satu alasan penghalang tampil; daftar lengkap dapat dibuka bila perlu. Selama misi, layar yang sama menampilkan progres, baterai, suhu, disk serta Jeda/Lanjut/Selesai. iPhone harus tetap di foreground; capture tidak bergantung koneksi Mac.
10. Setelah selesai, layar **Hasil** menyediakan **Transfer ke Mac**, **Olah foto** per misi, dan **Impor dari Finder** untuk foto/folder lokal. Transfer menyertakan gray card beserta foto asli. Pada pengolah misi, gray card bersifat opsional. Tanpa gray card, langsung pilih **Buat orthomosaic** tanpa normalisasi; jika gray card diunggah, tandai area kartu dan konfirmasi untuk menerapkan normalisasi. Engine lokal merekonstruksi kamera/permukaan, dan menulis TIFF atau GeoTIFF sesuai referensi koordinat yang tersedia. Riwayat hasil, progres, Hentikan, dan Simpan TIFF tersedia per misi. [Pemasangan engine dan batas pengolahan](ControlDroneMapping/Resources/ORTHOMOSAIC_ENGINE.md). Ekspor WebODM tetap tersedia di **Lainnya**; [workflow ekspor](docs/WEBODM_COLOR_WORKFLOW.md).

## Pembagian kontrol dan tampilan

Mac adalah pusat pengaturan kamera, kalibrasi, jeda/lanjut, penyelesaian misi dan dataset. iPhone menampilkan preview, informasi kamera/misi dan indikator koneksi tanpa tombol kontrol misi. Pengambilan dimulai dari Mac dan tetap berjalan mandiri ketika koneksi terputus. DroneCam memakai dark mode tetap. Krops pada Mac mendukung tema terang, gelap, atau mengikuti sistem. Countdown bersumber dari iPhone, tidak bergantung koneksi setelah diterima; background/interupsi kamera menjeda countdown. Inactive sementara tidak meminta jeda misi. Resume juga melalui countdown tiga detik.

## Mode panduan untuk tim lapangan

Mode panduan aktif secara default. Buat misi bernama, isi tinggi AGL, kecepatan, target GSD, overlap dan durasi pengambilan. Tinjau rencana, lalu:

1. **Siapkan kamera otomatis**: menghitung shutter/jeda dan jumlah foto sesuai durasi. Rencana yang terlalu cepat/tinggi ditolak dengan arahan penyesuaian.
2. **Ukur cahaya & warna kartu**: kartu gray 18% menutupi sebagian besar frame termasuk pusat, dalam cahaya survei tanpa bayangan/silau. Metering iPhone menentukan ISO dan, bila terlalu terang, shutter yang lebih cepat; kemudian exposure/WB/fokus dikunci dan foto referensi disimpan.
3. Singkirkan kartu, arahkan ke objek bertekstur pada jarak kerja, lalu **Cari fokus & ambil foto uji**. Autofocus dijalankan sekali dan posisi terukur dikunci. Pemeriksaan exposure dasar membaca preview, lalu operator memeriksa asli, cadence berulang dan kesiapan lapangan. Mulai hanya bila seluruh pemeriksaan selesai.

Nilai teknis dapat dilihat tanpa mengubahnya. Matikan Mode panduan untuk kontrol manual. Kebijakan ISO maksimum 800 (atau batas perangkat yang lebih rendah), shutter serta margin interval adalah baseline yang masih perlu uji fisik. Jika metering membutuhkan exposure di luar batas, aplikasi meminta mengurangi kecepatan/menunggu cahaya, bukan diam-diam melampaui batas blur.

Exposure tidak berubah otomatis selama terbang. Gray card pra/pasca terbang menyiapkan referensi; normalisasi radiometrik selama misi belum tersedia. Foto asli/metadata tetap tersimpan lokal saat Mac terputus. Perbarui kedua aplikasi untuk mode ini.

## Drone keluar jangkauan dan kembali

Setelah update kedua aplikasi, hubungkan dan setujui pairing sekali sebelum terbang. Identitas lokal dan peer yang disetujui disimpan untuk koneksi berikutnya. Mac hanya mencoba reconnect otomatis ke peer tersebut; undangan dari Mac yang sudah dipasangkan diterima iPhone tanpa konfirmasi ulang.

Saat radio terputus, timer dan penyimpanan iPhone tetap berjalan. Mac memeriksa koneksi setiap dua detik, mengundang kembali jika peer sudah ditemukan, dan memakai timeout 10 detik dengan jeda bertahap 2–15 detik antar percobaan. Discovery disegarkan setiap 20 detik saat offline dan tidak sedang mencoba koneksi. Waktu koneksi aktual bergantung discovery, radio dan OS.

Saat drone kembali dalam jangkauan, koneksi dipulihkan otomatis dan iPhone mengirim status serta daftar dataset terbaru. Perintah Mulai tidak diputar ulang. ACK yang hilang dapat diminta dari cache tanpa menjalankan ulang perintah. Jika cache hilang akibat restart aplikasi, hasil perintah tetap dianggap belum pasti dan perlu diperiksa operator. Download yang terputus belum otomatis dilanjutkan.

Kedua aplikasi harus tetap berjalan; iPhone harus di foreground dan Mac tetap bangun. Restart iPhone mempertahankan identitas pairing tetapi tidak otomatis melanjutkan capture misi lama. Pairing MCPeerID memberikan kontinuitas koneksi, belum certificate pinning.

## Struktur dataset

Dataset baru memakai struktur berikut pada iPhone dan setelah transfer ke Mac:

```text
Documents/DroneMapping/Nama Misi_2026-10-10T..._UUID/
  IMG_000001_UUID.jpg          # hanya JPEG mapping di folder utama
  IMG_000002_UUID.jpg
  RAW/                        # DNG asli bila dipilih
  Calibration/                # JPEG referensi sebelum/sesudah dan quality-test
  Metadata/                   # indeks capture JSON dan EXIF plist asli
  mission.json                # rencana kamera, survei, status, jumlah foto
```

Untuk ekspor dari Mac, gunakan **Siapkan WebODM** lalu upload JPEG dan `geo.txt` (jika tersedia) dari folder `Images`. Untuk import manual tanpa koreksi, pilih semua `IMG_*.jpg` di folder utama. RAW perlu dikembangkan konsisten menjadi JPEG/TIFF bila dipakai sebagai input pengolahan alternatif; jangan mengunggah JPEG dan DNG dari exposure yang sama sebagai dua foto. Referensi/quality-test tidak masuk flight block. Foto asli tidak dikompresi ulang saat penataan folder atau transfer.

Tombol **Transfer ke Mac** ada pada setiap misi di **Ambil hasil**; **Buka folder misi** menuju folder lokal tersebut. Transfer mengirim manifest terakhir; Mac memeriksa checksum foto dan jumlah mapping sebelum menyatakan dataset selesai. Transfer yang terputus dapat diulang, belum byte-range resume. Dataset lama dirapikan saat startup/ekspor: nama misi menggantikan UUID-only, satu capture disalin dan diverifikasi sebelum folder lamanya dihapus. Migrasi memerlukan ruang sementara satu capture; jika gagal sumber lama dipertahankan.

`Metadata/<capture UUID>.json` memakai `layoutVersion: 2`, path foto relatif ke folder misi, waktu request/host, GNSS/akurasi dan checksum. EXIF plist disimpan sebagai `Metadata/<nama foto>.metadata.plist`. Parameter yang diminta tidak dilabeli sebagai pengukuran aktual; exposure aktual ada pada EXIF asli. Tanggal Codable JSON memakai detik sejak 2001-01-01 UTC. Staging `.pending` menyimpan journal sebelum publikasi; indeks JSON atomik menjadi tanda commit. Recovery menyelesaikan transaksi yang punya journal, merekonsiliasi counter dan tidak menyalakan shutter otomatis.

GNSS hanya posisi perkiraan ponsel; sampel lebih tua dari 10 detik tidak disertakan. Geotag belum ditanam ulang ke EXIF, dan belum ada file pose RTK/PPK. Jangan menyamakan altitude MSL dengan tinggi terbang AGL. Mac dapat memiliki dataset parsial saat transfer belum selesai: gunakan auditor, bukan sekadar keberadaan `mission.json`, untuk menilai kelengkapan.

## Verifikasi

Jalankan `Scripts/test-core.sh` untuk tes matematika, readiness, scheduler, penyimpanan dan checksum. `Scripts/test-control-flow.sh` menguji urutan controller dengan perangkat sintetis; mode `--demo` tidak membuka discovery atau mengirim perintah ke iPhone. Lihat [pressure test workflow](docs/PRESSURE_TEST.md). Jalankan `python3 Scripts/audit-dataset.py /path/ke/mission-uuid` setelah transfer untuk mengecek capture dan checksum.

Build generik tanpa signing memvalidasi kompilasi, bukan kamera/transport nyata. Lihat [hasil validasi](docs/VALIDATION.md) dan [prosedur perangkat fisik](docs/DEVICE_TEST_PLAN.md).

## Batas tahap pertama dan pekerjaan berikutnya

- Belum ada kontrol navigasi/autopilot drone, telemetry flight controller, atau terrain following.
- Mac menampilkan preview foto uji/referensi setelah tersimpan (hingga 1200 pixel), bukan live video. Belum ada histogram/zebra, blur detector, atau clipping detector otomatis.
- Panel Hasil mengintegrasikan pengolahan orthomosaic lokal melalui OpenSfM komunitas 1.x. Engine dan helper Python bertanda tangan disertakan dalam aplikasi Mac; pemeriksaan engine/GPU berhasil melalui aplikasi Apple Development dengan App Sandbox aktif. Aset engine perlu disiapkan sebelum build Mac (lihat panduan engine). Sampel 12 foto Caliterra telah menghasilkan GeoTIFF melalui runtime pengembangan native; [pengukuran dan optimasi M5](docs/ORTHOMOSAIC_PERFORMANCE.md) mencakup preparasi JPEG, thread fitur, dan pembersihan data kerja setelah berhasil. Seluruh misi pribadi pengguna, distribusi Developer ID/notarisasi pada Mac lain, serta akurasi survei belum divalidasi. Belum ada ColorChecker profiling, reflectance calibration otomatis, atau VARI.
- Pilihan format sensor/resolusi alternatif, ProRAW/HEIF, aperture variabel dan parameter hardware tambahan perlu capability discovery serta eksperimen lanjutan. Maksimum format aktif bukan janji 48/64/108 MP.
- Retry command ID dideduplikasi selama proses hidup (cache 256); bukan exactly-once lintas restart. Status ACK yang hilang harus diperiksa pada telemetry sebelum perintah baru.
- Transfer ulang berkas tersedia; belum byte-range resume, whole-dataset transactional import, atau autentikasi pasangan berbasis sertifikat.
- Background/lock/termination menghentikan atau menjeda kamera. Restart mempertahankan dataset, tidak otomatis meneruskan shutter atau misi lama.
- Pengaturan berubah setelah pause tercatat per capture; pemroses harus memisahkan kelompok kalibrasi yang berbeda.

Dasar keputusan, alternatif, sumber ilmiah, dan rencana eksperimen: [RESEARCH.md](docs/RESEARCH.md). Arsitektur: [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Jika build Mac gagal karena provisioning iOS

Pastikan toolbar Xcode memakai scheme **ControlDroneMapping** dengan destination **My Mac**. Scheme **DroneMapping** adalah aplikasi iPhone; memilih **My Mac (Designed for iPad)** pada scheme tersebut dapat memunculkan error provisioning iOS karena Mac bukan perangkat yang tercantum pada profil iOS. Untuk iPhone, gunakan scheme DroneMapping dan pilih iPhone fisik.

Pesan `PLA Update available` berkaitan dengan perjanjian akun Apple Developer dan harus ditinjau/disetujui pemilik akun bila diperlukan untuk provisioning; aplikasi tidak dapat menyetujuinya otomatis.

## Pemeliharaan source code

Struktur MVVM memisahkan `Presentation` (View/ViewModel), `Domain` (model, kebijakan dan kontrak), `Data` (hardware, transport dan berkas), serta `Application` (composition root). Baca [System Design](docs/SYSTEM_DESIGN.md) untuk diagram, peta komponen, aturan concurrency, kompatibilitas dataset, dan panduan perubahan. `Scripts/test-architecture.sh` menguji batas layanan dengan dependency pengganti; `Scripts/format-swift.sh` memakai konfigurasi format bersama.

## Kebun sekitar dan rute waypoint

Gunakan **Lokasi saya** pada dashboard untuk meminta lokasi perkiraan Mac dan memfilter kebun yang sudah diimpor/disimpan. **Rute waypoint** membuka sheet editor: home, profil multicopter, waypoint berurutan, tinggi relatif home, dan ekspor `.plan`. Draft rute tersimpan lokal tanpa iPhone. Muat file melalui **Plan → Open** di QGroundControl dan periksa sebelum upload. [Panduan lengkap](docs/FLIGHT_PLANNING_AND_MAC_LOCATION.md).

## Penyimpanan dan pengelolaan misi Mac

Misi tersimpan di Application Support/DroneControl/missions.json dengan identitas lokal tetap; identitas dataset iPhone ditautkan setelah persiapan diakui. Area berupa salinan batas milik misi, sehingga mengubah batas misi A tidak mengubah misi B yang memakai kebun sama. Rute waypoint terkait identitas misi dan disimpan di flight-routes.json. Mode demo menggunakan demo-missions.json dan demo-flight-routes.json secara terpisah.

Draft lama dari mission-draft.json dimigrasikan ke daftar misi. Berkas tersebut kini merupakan journal perintah persiapan yang belum diakui; menghapus journal setelah ACK tidak menghapus misi dari daftar. Hapus misi pada Mac menyembunyikan kartu secara persisten dan mempertahankan dataset foto di **Hasil**. Misi yang sedang mengambil foto dan operasi yang belum diketahui hasilnya harus diselesaikan sebelum diedit/dihapus. Jika penyimpanan gagal, aplikasi menampilkan kesalahan dan menyediakan **Coba simpan lagi**; daftar yang gagal dibaca tidak ditimpa.

## Peta misi dan waypoint langsung

Halaman detail misi memakai panel pengaturan di kiri dan peta satelit di kanan. Panel kiri dapat digulir sendiri; peta tetap terlihat. Pilih **Home** dan klik lokasi lepas landas, lalu **+ Waypoint** untuk menambah titik berurutan. Area tidak perlu diimpor terlebih dahulu untuk menempatkan waypoint. **Pilih** membuka waypoint dari penanda atau daftar; tinggi dan urutannya dapat diubah di panel kiri. **Pindah WP** / **Pindahkan di peta** memindahkan waypoint terpilih ke lokasi yang diklik. Titik juga dapat dihapus atau perubahan rute diurungkan. **Batas area** menambah batas polygon pada peta yang sama. Misi, batas, home dan rute disimpan per identitas misi. Detail firmware/elevasi home dan ekspor `.plan` tersedia melalui **Ekspor rute**. Koneksi dan setup perangkat tetap di panel Perangkat.
