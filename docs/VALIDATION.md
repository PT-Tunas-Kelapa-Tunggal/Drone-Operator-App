# Validasi layout misi dan waypoint langsung — 14 Oktober 2026

- Build final Debug Mac tanpa signing: **BUILD SUCCEEDED**.
- **45** pemeriksaan planner/lokasi dan **122** pemeriksaan controller/alur misi lulus.
- Uji UI native demo: pengaturan berada di kiri, peta tetap terlihat di kanan; penempatan Home dan tiga waypoint melalui klik peta berhasil tanpa batas area terlebih dahulu.
- Klik penanda WP 1 memilih titik yang benar; tinggi diubah menjadi 90 m dan tetap pulih setelah restart aplikasi.
- Mode **Pindah WP** mengubah koordinat waypoint terpilih melalui klik lokasi baru; jumlah waypoint tetap tiga dan jarak rute diperbarui.
- Mode **Batas area** menyimpan tiga titik batas serta menggambar polygon pada peta yang sama dengan rute.
- Berkas demo diperiksa setelah aplikasi ditutup: satu rute terkait identitas misi, tiga waypoint, Home, tinggi 90 m dan tiga titik batas tersimpan. Data uji UI dibersihkan setelah verifikasi.
- Uji ini tidak mengirim perintah ke drone/iPhone; setup perangkat tetap di panel Perangkat.

---

# Validasi waypoint manual dan lokasi Mac — 14 Oktober 2026

- Build Debug Mac standar: **BUILD SUCCEEDED**. Build demo dengan identitas terpisah juga berhasil untuk memisahkan uji UI dari aplikasi utama yang terbuka.
- **42** assertions baru lulus pada `Scripts/test-flight-planner.sh`: rute offline/persistensi, review, undo/reorder, JSON QGC, elevasi home, profil firmware, invalid input, format desimal, lokasi stale/denied/expiry, dan radius kebun.
- Regresi yang relevan: **7** tes import kebun/ViewModel dan **21** tes batas arsitektur lulus.
- Entitlement produk standar diperiksa: App Sandbox, network client/server, user-selected read-write, dan personal-information.location hadir. Info.plist produk memuat usage description lokasi Mac serta tipe `.plan`.
- Pengujian UI final: buat rute, pilih ArduPilot Copter, input home `1.05, 104.45` dengan elevasi sintetis `35`, tambah dua waypoint melalui klik peta, review, buka NSSavePanel, dan simpan file `.plan` ke folder sementara. File hasil benar-benar dibaca kembali: Plan v1 / mission v2, home desimal benar, command `[22,178,16,16,20]`, dan dua waypoint relatif home 80 m.
- Uji UI menemukan parsing titik desimal memakai grouping locale Indonesia; latitude/longitude diperbaiki memakai POSIX dan tanpa grouping, kemudian diverifikasi lagi pada UI/file hasil.
- Layanan lokasi native berhasil memberikan penanda perkiraan Mac pada sesi UI awal. Lokasi operator tidak otomatis menjadi home. Expiry state diuji otomatis; pengujian ini tidak membuktikan akurasi GPS survei.
- QGC tidak ditemukan pada direktori instalasi standar yang diperiksa. Import file pada QGC, upload autopilot, serta penerbangan fisik **belum diuji**. Tidak ada perintah ke drone atau iPhone dalam pengujian demo.
- `git diff --check`: lulus.

[Panduan operator, sumber, dan batasan](FLIGHT_PLANNING_AND_MAC_LOCATION.md).

---

# Validasi refactor MVVM — 14 Oktober 2026

- Build Debug `ControlDroneMapping`, generic macOS, signed lokal: **BUILD SUCCEEDED**.
- Build Debug `DroneMapping`, generic iOS, `CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.
- Tes inti: **158** assertions lulus.
- Tes alur controller/operator: **90** assertions lulus dengan kamera sintetis.
- Tes repository dan ViewModel batas kebun: **7** pemeriksaan lulus.
- Tes ekspor WebODM: **31** assertions lulus dengan JPEG sintetis yang benar-benar di-encode; tanpa rekonstruksi aerial.
- Tes batas arsitektur: **21** assertions lulus dengan kamera/transport/draft/exporter pengganti, tanpa discovery atau capture fisik.
- Total: **307** pemeriksaan otomatis lulus.
- Tes JPEG gagal saat rendering Core Image di sandbox; tes yang sama lulus di luar sandbox dengan layanan rendering macOS tersedia. Tidak ada perubahan algoritma rendering untuk melewati kegagalan ini.
- UI demo diamati dari pembuatan misi offline, sinkronisasi, peninjauan survei, penerapan kamera, referensi, fokus/foto uji, review, start, sampai hasil dengan UUID misi yang sama. Demo tidak melakukan countdown fisik, shutter, atau transfer radio.
- `git diff --check`: lulus. Konfigurasi dan skrip swift-format ditambahkan untuk format source yang konsisten.
- SDK 27 masih memberi warning deprecation MultipeerConnectivity. Implementasi transport dipertahankan di belakang `LocalTransport`; migrasi transport bukan bagian refactor ini.

Refactor mempertahankan protokol, schema dataset, dan bundle ID. Tidak dilakukan uji drone/perangkat fisik baru pada tahap ini. Pengujian ini tidak menjamin kualitas orthomosaic, kalibrasi reflectance, thermal endurance, atau reconnect radio di penerbangan nyata. Desain terkini: [SYSTEM_DESIGN.md](SYSTEM_DESIGN.md).

---

# Hasil validasi — 10 Oktober 2026

## Terverifikasi

- Xcode 27.0 (27A266a) ditemukan pada `/Applications/Xcode.app`.
- Build Debug scheme `DroneMapping`, generic iOS, `CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.
- Build Debug scheme `ControlDroneMapping`, generic macOS, `CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**.
- Build akhir tidak memiliki compiler warning pada source aplikasi. Xcode mencatat metadata AppIntents dilewati karena framework itu tidak digunakan.
- `Scripts/test-core.sh`: **33 assertions lulus**, mencakup unit GSD/interval/blur, input invalid, scheduler skip/no-burst, JSON roundtrip, manifest, SHA-256, streaming hash, traversal rejection, partial-file exclusion dan recovery tanpa auto-resume.
- `python3 -m unittest discover -s Tests -p 'test_*.py'`: **2 tests lulus**. Fixture sintetis menguji import lengkap, hash rusak, foto hilang dan transfer parsial. Pesan `FAIL` yang dicetak selama tes adalah kasus negatif yang diharapkan, bukan kegagalan suite.
- `git diff --check`: lulus.
- Info.plist produk iOS diperiksa: deskripsi Kamera, Location, Local Network, layanan Bonjour dan File Sharing hadir; deployment target 17.0.
- DroneControl diluncurkan pada Mac ini. UI ground station diamati melalui accessibility tree dan screenshot; navigasi ke Perencanaan overlap berfungsi dan contoh menampilkan GSD 2.67 cm/px, interval 3.23 s, shutter 0.00267 s. Pengamatan UI dilakukan sebelum perapihan label final; build final juga berhasil.

## Belum terverifikasi

Xcode mencatat iPhone fisik tetapi semuanya berstatus **unavailable** saat pemeriksaan. Maka belum dilakukan: install/signing iPhone fisik, izin runtime iOS, capture JPEG/DNG nyata, kemampuan/interval RAW, preview iPhone, koneksi dua perangkat, kehilangan radio saat capture, transfer foto nyata, thermal/battery endurance, akurasi GNSS, kalibrasi warna, atau hasil orthomosaic.

Simulator yang tersedia tidak menjadi pengganti uji kamera. Generic build tanpa signing juga tidak membuktikan provisioning, entitlements saat distribution, atau runtime pada semua versi deployment target.

## Cara mengulang build

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project DroneMapping.xcodeproj -scheme DroneMapping -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/DroneMapping-ios-build \
  CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project DroneMapping.xcodeproj -scheme ControlDroneMapping -configuration Debug \
  -destination 'generic/platform=macOS' -derivedDataPath /tmp/DroneMapping-build \
  CODE_SIGNING_ALLOWED=NO build
```

Build membutuhkan layanan/compiler plugin Xcode yang tidak berfungsi dalam sandbox sempit; build diverifikasi dengan akses lokal di luar sandbox. Tidak ada konfigurasi global xcode-select yang diubah.

## Urutan kelanjutan

1. Hubungkan iPhone fisik, signing dan jalankan bench test pada `DEVICE_TEST_PLAN.md`.
2. Perbaiki temuan nyata kemampuan kamera, concurrency, pairing/radio, dan throughput.
3. Tambahkan dataset completion manifest/ACK, identitas pairing persisten, timeout konfigurasi yang teruji, dan fault injection runtime.
4. Tambahkan histogram/clipping/blur QA serta preview hemat bandwidth pada Mac berdasarkan anggaran baterai/panas.
5. Jalankan eksperimen gray card vs ColorChecker, format kamera, dan pipeline orthomosaic dengan checkpoint independen.

Tahap ini selesai pada riset awal, implementasi fondasi, build dan tes logika. Sasaran sistem profesional end-to-end masih terbuka sampai seluruh gerbang hardware dan akurasi terpenuhi.

## Pembaruan kontrol dan countdown — 10 Oktober 2026

Pengguna mengonfirmasi kedua perangkat sudah saling terhubung pada versi sebelumnya. Versi pembaruan memusatkan kontrol pada Mac, menyisakan informasi/preview/tombol Mulai pada iPhone, menambahkan countdown otoritatif iPhone 3–2–1–START, indikator koneksi pada kedua layar, dan dark mode tetap.

Build Debug generik iOS dan macOS pembaruan: **BUILD SUCCEEDED**. Tes inti: **41 assertions lulus**, termasuk batas waktu countdown, tidak ada foto sebelum detik ketiga, dan recovery misi yang terhenti saat countdown. `git diff --check` lulus. Sinkronisasi countdown dan UI pembaruan belum diuji langsung pada pasangan perangkat fisik; kedua aplikasi perlu dijalankan ulang dari build terbaru.

## Layar informasi iPhone dan operasi saat disconnect

Tombol Mulai di iPhone dihapus; semua kontrol misi berasal dari Mac. Konfirmasi koneksi perangkat tetap tersedia saat pairing. Status disconnected saat countdown/capture menampilkan bahwa foto tetap disimpan lokal.

Peninjauan jalur disconnect menunjukkan MCSession hanya memperbarui status link, tanpa memanggil pause atau menghentikan timer kamera. Pengiriman telemetry kini dilewati saat tidak terhubung. Inactive sementara tidak lagi meminta pause; background dan interupsi kamera tetap menjeda sesuai batas iOS. Rencana yang diterima saat start disinkronkan ke informasi pada iPhone.

Build iOS generik tanpa signing dan build macOS dengan signing: **BUILD SUCCEEDED**. Tes inti: **41 assertions lulus**; diff whitespace check lulus. Perubahan ini belum diuji dengan memutus radio pada iPhone fisik saat capture; uji tersebut tetap diperlukan untuk validasi hardware.


## Reconnect otomatis perangkat berpasangan

Identitas peer lokal dan peer yang disetujui disimpan via secure archive. Mac mencoba reconnect ke pasangan yang ditemukan dengan timeout/backoff; iPhone menerima pasangan yang sudah disetujui tanpa konfirmasi ulang. Discovery disegarkan saat offline. Reconnect mengirim snapshot misi terbaru dan dapat mengambil ACK dari cache tanpa mengulang perintah.

Build iOS generik dan macOS dengan signing: **BUILD SUCCEEDED**. Tes inti **53 assertions lulus**, termasuk bounded backoff, reset setelah koneksi berhasil, archive/recreation MCPeerID, isolasi pasangan antar role, penolakan peer berbeda bernama sama, serta packet permintaan ACK yang tidak mengandung command. Compiler tes pada deployment default macOS 27 memperingatkan deprecation MPC; target aplikasi macOS 14/iOS 17 tetap berhasil dibangun.

Hasil ini belum membuktikan reconnect radio dua perangkat saat terbang. Setelah update lakukan pairing sekali, kemudian uji hilang jangkauan/kembali tanpa menyentuh iPhone dan periksa counter foto serta UUID misi tetap berlanjut.


## Perombakan workflow Mac dan pressure test — 10 Oktober 2026

UI Mac diganti dengan enam langkah persiapan sampai hasil, footer alasan penghalang, estimasi survei, kamera terkunci, gray card, foto uji tersimpan dengan preview/latency, checklist lapangan dan gerbang start pada controller. iPhone tetap layar informasi; hanya protokol foto uji/preview ditambahkan.

- Tes inti: **104 assertions lulus**; termasuk 47 skenario input/state negatif pada readiness.
- Tes controller: **22 assertions lulus**, menggunakan perangkat sintetis tanpa radio. Mencakup perubahan setting, urutan gray card/referensi/foto uji, disconnect/reconnect mempertahankan misi, pause/resume/finish dan review baru setelah selesai.
- Auditor: **2 tests lulus**; output FAIL pada fixture negatif memang diharapkan.
- Build Debug Mac dengan signing dan build iOS generik tanpa signing: **BUILD SUCCEEDED**.
- UI native mode demo diperiksa melalui accessibility dan screenshot: koneksi → rencana → rekomendasi kamera → ACK → gray card → referensi → preview uji → checklist → start → pause → resume → finish. Perbaikan terakhir menyempurnakan label overlap persen dan transisi finish ke hasil; transisi tersebut juga diuji pada controller.

Uji radio putus, JPEG/DNG nyata, waktu capture, endurance dan hasil orthomosaic pada perangkat/penerbangan fisik belum dilakukan dalam sesi ini. Koneksi versi terdahulu dilaporkan sudah berhasil oleh pengguna. Mode demo bukan bukti performa kamera.


## Misi bernama, layout flat, transfer — 10 Oktober 2026

- Build Debug Mac dengan signing serta iOS generic tanpa signing: **BUILD SUCCEEDED**.
- **125 assertions inti lulus**, termasuk 21 pemeriksaan layout/migrasi/recovery/transfer bernama. Layout tests memakai byte sintetis, bukan JPEG/DNG kamera nyata.
- **23 assertions controller lulus**; pembuatan misi bernama, reset review, dan alur disconnect/reconnect sintetis.
- **3 tes auditor lulus**, termasuk layout flat dengan quality-test/referensi terpisah serta file hilang/rusak.
- UI native demo: tombol create terkunci sebelum kamera siap, nama kosong tidak bisa disubmit, nama Kebun Utara diterima dan tampil pada sidebar serta halaman perencanaan. Tampilan persen overlap juga diamati.
- Migrasi asli pada container iPhone dan transfer dataset fisik belum dilakukan dalam sesi ini. Update kedua aplikasi lalu jalankan tes penerimaan perangkat.


## Penyederhanaan Mac menjadi dua layar — 10 Oktober 2026

Navigasi enam langkah diganti **Misi / Hasil**. Create, survei, kamera, gray card, preview, checklist dan start berada di satu layar Misi. Saat capture, konten berubah menjadi monitoring serta kontrol pada layar yang sama. Hasil memuat dataset/transfer/Finder. Petunjuk panjang dihapus; informasi tambahan menjadi tooltip, disclosure atau popover. Readiness serta kontrol start pada model tetap berlaku.

Build Mac dengan signing berhasil. **23 assertions controller lulus** setelah pembaruan navigasi; aturan kualitas/capture/penyimpanan tetap menggunakan implementasi yang sudah diuji sebelumnya. UI demo diperiksa langsung: create inline, konfigurasi dua kolom, apply, gray card, referensi, foto uji membuka checklist otomatis, dan navigasi Misi/Hasil. Bukan validasi kamera atau transfer fisik. iPhone tidak diubah oleh penyederhanaan ini.


## Koreksi cadence foto uji — 10 Oktober 2026

Screenshot pengguna menunjukkan foto uji 1.05 s dan interval 1.1 s. Margin 25% meminta 1.3125 s; langkah interval 0.1 s dibulatkan ke atas menjadi 1.4 s. Pesan sebelumnya selalu menyuruh menurunkan kecepatan, meskipun interval lebih panjang masih dapat memenuhi overlap. Pesan baru menyebut interval yang diperlukan; jika tidak muat dalam batas overlap, barulah meminta kecepatan lebih rendah. Tombol Sesuaikan interval tersedia hanya untuk foto uji dengan setting kamera yang sama dan interval yang masih memenuhi overlap. Koreksi membatalkan review cadence, tanpa menandai uji sebagai sudah dilakukan.

129 assertions core dan 26 assertions controller lulus, termasuk regresi geometri screenshot 8064×6048, GSD 0.59 cm/px, 5 m/s, overlap 80%, capture 1.05 s. Build Mac signed berhasil. Tidak ada capture fisik baru dilakukan untuk koreksi ini.

## Perbaikan alur gray card 18% — 10 Oktober 2026

- Build Debug DroneControl macOS dengan signing: berhasil. Build DroneCam generic iOS tanpa signing: berhasil.
- Tes core: 129 assertions; controller: 34 assertions dengan hardware sintetis. Mencakup satu operasi WB + referensi, exposure tetap, penolakan referensi lama/misi berbeda, dan preview sebelum ACK saat reconnect.
- UI native diperiksa melalui mode demo: create mission → apply → ambil referensi → status warna terkunci/referensi tersimpan → foto uji membuka pemeriksaan. Mode demo tidak mengendalikan iPhone.
- Normalisasi radiometrik, ISO adaptif, deteksi kartu dan validasi kualitas warna pada perangkat fisik belum dilakukan. Tes fisik tambahan tercatat di DEVICE_TEST_PLAN.md. Kedua aplikasi perlu diperbarui karena ada perintah grayCardReference baru.

## Mode panduan untuk operator — 10 Oktober 2026

- Tes core: 143 assertions; controller: 43 assertions dengan hardware sintetis. Termasuk pemilihan ISO/shutter dari metering, cahaya terlalu redup/terang, input nonfinite, durasi, geometri tidak layak, foto hitam/jenuh, referensi dan readiness mode panduan, serta perubahan cadence yang mempertahankan target durasi.
- UI native demo: buat misi → tinjau rencana → siapkan otomatis → ukur kartu → foto uji → pemeriksaan → Mulai → Selesai → Hasil. Dataset dan metering demo sintetis; tidak ada capture/transfer radio pada pengujian ini.
- Generic iOS build tanpa signing dan Debug macOS build dengan signing berhasil. Pembacaan meter, kualitas JPEG/RAW .speed, recovery saat interupsi dan ketahanan capture perlu uji iPhone fisik sesuai DEVICE_TEST_PLAN.md. Belum ada validasi penerbangan, deteksi kartu otomatis, QA ketajaman otomatis atau normalisasi radiometrik.
- Durasi target diturunkan menjadi jumlah foto; jeda dan slot terlewat dapat memperpanjang waktu aktual.

## Fokus terukur dan diagnostik ketajaman — 10 Oktober 2026

- 147 core assertions dan 49 controller assertions lolos (hardware sintetis). Mencakup perubahan fokus yang mempertahankan kalibrasi exposure/warna, sinkronisasi posisi AF, pemeriksaan crop, penolakan foto uji misi berbeda, dan analisis detail yang hilang.
- Build macOS Debug signed dan generic iOS unsigned berhasil; build iOS diulang setelah penambahan watchdog lock. Uji autofocus, tekstur, getaran dan kualitas asli pada iPhone fisik masih diperlukan.
- Mode panduan mengganti asumsi endpoint fokus dengan autofocus sekali sebelum foto uji; posisi dikunci sepanjang misi. Pengukuran gray card mempertahankan posisi tersebut. Skor ketajaman informatif, bukan bukti akurasi photogrammetry.

## Misi tanpa koneksi iPhone — 11 Oktober 2026

- DroneControl dapat membuat nama/draft misi sebelum iPhone terhubung. Draft dan perubahan rencana disimpan atomik di Application Support/DroneControl/mission-draft.json dan dipulihkan saat aplikasi dibuka kembali.
- Draft dikirim menggunakan ID perintah yang tetap setelah telemetry terbaru menyatakan kamera siap. ACK diperlukan sebelum draft dianggap tersedia pada iPhone. Misi yang sedang capturing/countdown/paused tidak diganti; Mulai dan operasi kamera tetap memerlukan perangkat serta kesiapan yang valid.
- 60 assertions controller dengan hardware simulasi lulus, termasuk pembuatan offline, nama tidak valid, pemulihan perubahan draft, sinkronisasi setelah prepare, tidak menciptakan misi ulang pada telemetry berikutnya, dan perlindungan misi aktif. Perubahan ini belum diuji pada koneksi iPhone fisik.

## Koreksi kartu dan ekspor WebODM — 11 Oktober 2026

- Hasil misi memiliki Siapkan WebODM: original byte-for-byte atau koreksi acuan kartu dengan pemilihan ROI dan konfirmasi kartu fisik. Referensi otomatis ikut transfer misi dan dipisahkan dari Images saat ekspor. Hasil lokal dapat dibuka saat iPhone offline.
- 29 assertions ekspor lulus dengan JPEG sintetis yang benar-benar di-encode/decode: netralitas patch di output, dimensi/EXIF, checksum source/output, identitas referensi, koreksi exposure pada translasi terukur melalui Vision, penolakan posisi salah/tekstur minim/gain berlebihan, fallback dengan warning, geo.txt, serta rollback JPEG palsu yang memiliki checksum valid. Core Image/Vision membutuhkan akses layanan lokal di luar sandbox pengujian.
- 147 core assertions dan 60 controller assertions lulus. Build generic macOS Debug tanpa signing berhasil. Source iOS tidak diubah.
- Koreksi overlap masih eksperimental dan hanya mencoba pasangan berurutan dengan homography/fallback translasi dan gerbang photometric. Bukan radiometric block adjustment global, calibrated reflectance, atau jaminan normalisasi perubahan matahari/bayangan. Dataset penerbangan dan rekonstruksi WebODM belum diuji. Detail metode/batas: WEBODM_COLOR_WORKFLOW.md.

## Keandalan konfigurasi dan pemeriksaan foto asli — 12 Oktober 2026

- Penerapan exposure/fokus/WB memiliki watchdog 5 detik. Timeout mengakhiri operasi dengan kegagalan, mengosongkan status pengaturan dan kalibrasi, serta membebaskan status sibuk. Callback terlambat tidak boleh memulihkan status sukses. Start misi yang sudah disiapkan dan resume memerlukan pengaturan yang masih terkonfirmasi.
- Draft yang mendapat penolakan eksplisit memperoleh ID percobaan baru yang disimpan di Mac. Heartbeat tidak mengulanginya sampai operator memilih Coba siapkan misi. Pengiriman dengan hasil belum diketahui tetap memakai ID sebelumnya untuk mengambil konfirmasi. ID balasan di iPhone masih belum persisten setelah restart aplikasi; ini belum menjamin exactly-once lintas restart kedua aplikasi.
- Foto uji mengirim ISO/shutter EXIF JPEG asli dan total byte JPEG/RAW beserta sidecar. Mac menampilkan angka aktual dan memblokir mulai jika informasi hilang atau berbeda di luar toleransi: ISO 1/3 EV, shutter 1/6 EV. Kedua angka diperiksa terpisah agar produk exposure yang sama tidak menutupi shutter lambat. Shutter aktual juga diperiksa terhadap perkiraan batas gerak.
- Ruang awal misi dihitung dari byte foto uji × target foto × 1.3 + cadangan 512 MiB. Ini estimasi dari satu sampel, bukan jaminan ukuran setiap scene. Penjagaan ruang minimum setiap capture di iPhone tetap aktif. Data foto uji dari versi lama tanpa EXIF/ukuran meminta pembaruan DroneCam dan pengambilan ulang.
- 158 assertions core dan 63 assertions controller simulasi lulus. Termasuk EXIF rounding iPhone yang pernah diamati, EXIF hilang/nonfinite, shutter lambat dengan produk exposure sama, storage overflow, ruang kurang untuk target, penolakan draft tanpa resend otomatis dan retry eksplisit dengan ID baru.
- Build Debug generic macOS dan generic iOS tanpa signing berhasil. Timeout callback kamera dan uji flight/disconnect/reconnect pada perangkat fisik belum diuji; build dan simulasi tidak menggantikan pengujian perangkat. Kedua aplikasi perlu diperbarui bersama.

## Dashboard native Krops — 14 Oktober 2026

Build macOS Debug signed berhasil; 63 tes controller simulasi dan 4 pemeriksaan impor/persistence batas kebun lulus. Ringkasan, pembuatan misi offline, halaman Misi bertema baru, serta Pengaturan diperiksa melalui UI native mode demo. Peta menggunakan MapKit dan impor GeoJSON, sementara angka dashboard memakai data misi aktual. Permintaan petani, cuaca dan telemetry drone belum diintegrasikan; tidak memakai data mockup sebagai produksi. Rincian terdapat pada DASHBOARD.md. Source iOS dan scheduler akuisisi tidak diubah pada pekerjaan dashboard.

## Pressure test alur operator — 14 Oktober 2026

90 assertions controller simulasi lulus; build macOS signed dan generic iOS unsigned berhasil. UI demo melalui tahapan persiapan sampai selesai diperiksa. Perbaikan mencakup petunjuk langkah berikutnya, hasil spesifik UUID dan filter, restore rencana aktif setelah reconnect/restart, draft versus monitoring, counter telemetry, feedback transfer, dan target ID start/pause/resume/finish yang diverifikasi iOS. Riset, temuan, serta batas uji fisik tercatat pada OPERATOR_FLOW_PRESSURE_TEST.md.
