# Gerbang validasi perangkat fisik

Status seluruh uji hardware di bawah: **belum dilakukan**. Simulator tidak dapat membuktikan RAW, kualitas lensa, cadence, thermal, radio lapangan, atau akurasi photogrammetry.

## A. Bench test sebelum dipasang di drone

Catat model iPhone, iOS, macOS, Xcode, kapasitas disk, mount, kondisi cahaya, mode foto, resolusi aktual, dan versi kode. Mulai 20 foto pada interval 3 detik; ubah sesuai kemampuan yang terukur.

| Skenario | Bukti yang diperiksa | Kriteria |
|---|---|---|
| Izin kamera ditolak | UI dan status command | Penolakan jelas; tidak mengaku capture |
| Izin lokasi ditolak | Sidecar foto | Foto tetap tersimpan, lokasi absent |
| Local Network ditolak | Koneksi dan misi lokal | Tidak ada koneksi palsu; capture lokal tersedia |
| ISO/shutter/WB/fokus | EXIF, metadata, foto chart | Parameter didukung diterapkan; unsupported ditolak |
| JPEG dan RAW+JPEG | Dimensi aktual, DNG decoder, checksum | 1 capture = semua format yang dipilih + metadata |
| Matikan Wi-Fi Mac 2 menit | Jumlah foto dan timeline iPhone | Capture lokal berlanjut; gap/skips tercatat |
| Reconnect otomatis tanpa menyentuh iPhone | Nomor misi, jumlah foto, discovery/ACK | Pairing pertama sekali; kembali ke jangkauan memulihkan telemetry tanpa restart misi |
| Reconnect dan retry UUID | Counter dan ACK | Tidak membuat misi kedua untuk UUID cache yang sama |
| Layar dikunci / app background | State + timestamp | Paused terlihat; tidak ada janji capture background |
| Telepon/interruption | State, error, recovery | Tidak stuck mengaku capturing; resume eksplisit |
| Interval terlalu pendek | Missed counter, RAM, cadence | Tidak ada burst catch-up atau antrean tak terbatas |
| Disk rendah | Status dan folder partial | Berhenti jelas; foto committed tetap bisa dibaca |
| Thermal test wajar | Suhu, capture latency | Critical menghentikan capture; dokumentasikan serious |
| Force quit di tengah capture/save | Manifest, committed/staging | Startup reconcile; tidak auto-restart kamera |
| Putus saat download | Auditor, foto sumber | Sumber utuh; download ulang menghasilkan checksum cocok |
| Referensi pre/post | kind dan mission UUID | Referensi terpisah dari mapping, tergabung misi benar |
| Misi baru | UUID dan folder | Tidak menimpa dataset sebelumnya |

Uji gray card dengan target memenuhi bagian tengah seperti panduan Apple. Bandingkan gain dan patch netral sebelum/sesudah. Pastikan tombol referensi sesudah tidak mengubah WB yang ingin dievaluasi. Pengujian dilakukan pada kondisi cahaya stabil dan berubah.

## B. Uji akuisisi dan throughput

Ambil minimal tiga sesi untuk tiap format/interval yang relevan. Ukur actual host timestamp antar exposure, waktu callback hingga committed file, memori, baterai, suhu dan missed slots. Pilih interval yang memenuhi p99 latency dengan margin. Bila interval aman lebih lama daripada batas overlap, turunkan kecepatan atau ubah rencana; jangan mengklaim overlap tercapai dari timer saja.

Bandingkan wide JPEG dan Bayer RAW (jika tersedia) pada chart detail statis, objek bergerak, dan mount bergetar. Evaluasi blur, clipping, distorsi, resolusi aktual dan perubahan geometri. Pengujian ProRAW/format alternatif merupakan eksperimen berikutnya, belum jalur aplikasi ini.

## C. Uji pemetaan terkendali

Gunakan area uji dengan izin operasi yang sesuai, kontrol tanah dan checkpoint terpisah. Catat CRS dan datum vertikal, ukur GCP, distribusikan checkpoint di tepi/tengah serta variasi elevasi. Terbang dengan parameter konstan pada beberapa kecepatan, overlap, dan kondisi cahaya. Pisahkan dataset bila fokus/format/setting berubah.

Jalankan pipeline kandidat pada dataset yang sama. Laporkan parameter alignment, model rolling shutter, calibration groups, residual, bias, RMSE XY/Z checkpoint, coverage, holes, seams, clipping dan warna patch independen. Tetapkan kebutuhan akurasi proyek sebelum menentukan lulus/gagal; GSD bukan akurasi absolut.

## Kebutuhan agar dapat dijalankan bersama

Hubungkan iPhone fisik via USB atau wireless debugging, unlock dan trust Mac, aktifkan Developer Mode, pilih signing team. Sampaikan model perangkat dan platform drone agar rentang kamera serta workflow pemasangan bisa diuji. Pengujian penerbangan memerlukan operator dan lokasi nyata; tidak dapat digantikan build generik.


## Workflow Mac baru: uji penerimaan

1. Update kedua aplikasi. Hubungkan, siapkan kamera dan pastikan dimensi/rentang parameter nyata tampil.
2. Isi AGL/kecepatan/overlap/GSD; tinjau asumsi FOV nominal vs kalibrasi foto. Pastikan interval memenuhi overlap pada jalur/terrain nyata.
3. Terapkan rekomendasi, sesuaikan exposure/fokus. Pastikan ACK datang sebelum lanjut. Ubah ISO sesudah review: start harus kembali terkunci.
4. Gray card pada cahaya yang sama → ukur WB → foto referensi tersimpan → keluarkan kartu → foto uji. Preview harus sesuai foto asli dan metadata. Foto uji/referensi tidak menambah counter mapping.
5. Unduh asli; inspeksi ketajaman pixel dan clipping. Uji cadence berulang pada format yang dipilih, termasuk RAW; waktu capture+save × 1.25 harus muat dalam interval. Lanjutkan uji hingga durasi misi dan kondisi termal yang direncanakan.
6. Lengkapi pemeriksaan lapangan setelah benar-benar dilakukan. Start terkunci untuk status >6 detik, pending ACK, foto busy, disk <512 MB, baterai <20% atau suhu panas/kritis.
7. Putus radio setelah countdown diterima dan saat capture. Hitungan/file iPhone tetap naik. Saat kembali, status terbaru dan UUID misi sama; tidak ada start ulang. Kontrol Mac offline tidak dijalankan belakangan.
8. Finish: tunggu foto terakhir committed, pindah ke hasil, ambil referensi sesudah, download/audit. Misi baru meminta pemeriksaan kualitas baru.
9. Proses hanya mapping; periksa alignment, checkpoint independen, holes/seam, warna dan geometri. Catat parameter yang gagal dan revisi rekomendasi berdasarkan hasil fisik.


## Misi bernama dan import WebODM

1. Update kedua aplikasi. Periksa dataset lama sebelum/sesudah migrasi: jumlah foto dan byte/hash sama, sumber hanya dihapus setelah commit terverifikasi. Uji ruang disk rendah saat migrasi.
2. Buat dua misi dengan nama sama: UUID/folder berbeda, dataset sebelumnya tetap ada. Create saat capture/countdown/paused harus ditolak.
3. Capture JPEG serta RAW+JPEG: JPEG mapping langsung di folder utama, DNG di RAW, uji/referensi di Calibration, metadata di Metadata. Counter mapping tidak menghitung uji/referensi.
4. Simulasikan restart selama penyimpanan. Journal lengkap dipulihkan, tidak ada auto-resume; audit jumlah mapping dan metadata. Jangan mengandalkan preview sebagai bukti file lengkap.
5. Transfer ke Mac, buka folder misi, audit checksum dan jumlah. Putus radio di tengah transfer, reconnect dan ulangi: tidak menambah file duplikat. Status selesai harus baru tampil setelah verifikasi manifest terakhir.
6. Di WebODM buat task dan pilih hanya IMG_*.jpg pada root misi. Periksa jumlah input, kualitas/geometri, serta georeferencing terpisah; GNSS sidecar belum otomatis dipakai oleh WebODM.

## Gray card 18%: uji perangkat yang masih diperlukan

- Terapkan kamera, letakkan kartu mengisi bagian tengah 50% pada iluminasi survei tanpa silau/bayangan. Klik **Ambil referensi gray card 18%**. Pastikan gain WB terkunci, ISO/shutter tetap, dan berkas JPEG (+DNG jika dipilih) muncul di Calibration/.
- Putuskan koneksi setelah perintah diterima tetapi sebelum foto tersimpan. Setelah reconnect, pastikan referensi terbaru dan ACK yang sama tersinkron tanpa mengambil ulang foto. Status tersimpan tidak boleh berasal dari referensi lama/misi lain.
- Singkirkan kartu; ambil foto uji detail lapangan dan periksa exposure pada asli. Setelah misi, ambil gray card sesudah tanpa lock WB ulang untuk pembandingan.
- Bandingkan matahari stabil, awan berubah, dan pencahayaan campuran pada exposure tetap. Fitur ini belum melakukan normalisasi radiometrik, deteksi kartu, atau ISO adaptif; ukur clipping/noise sebelum merancang koreksi offline.

## Mode panduan dan exposure metering

1. Uji 18% gray card di matahari stabil: cek ISO × shutter sebelum/sesudah pemilihan manual; cocokkan ExposureTime/ISOSpeedRatings pada sidecar asli dengan pengaturan. Semua foto memakai .speed untuk menghindari penggantian exposure oleh quality fusion.
2. Uji matahari terik: shutter boleh dipercepat saat ISO minimum. Uji redup: sistem harus menolak kebutuhan ISO di atas ceiling mutu dan meminta mengurangi kecepatan/menunggu cahaya. Jangan diam-diam memperpanjang shutter melewati batas gerak.
3. Uji kartu bergerak/awan cepat, tutup lensa, session interruption/background dan disconnect pada tahap metering, lock, penyimpanan. Timeout/penolakan harus mengembalikan manual sebelumnya, tidak menandai referensi siap; reconnect harus membawa metadata dan preview perintah yang sama.
4. Uji shutter pendek dan RAW/JPEG pada interval rekomendasi minimal 10 menit. Cocokkan target durasi, jumlah foto, missed slots, panas, ruang simpan dan overlap efektif.
5. Foto hampir seluruhnya hitam/putih tidak boleh lolos hanya lewat checkbox; foto berhighlight parsial tetap harus diperiksa pada berkas asli. Uji negative control kartu salah warna/bersilau untuk mengukur keterbatasan metering pusat.

## AF → lock → foto uji

- Setelah gray card disingkirkan, arahkan ke target bertekstur dekat untuk uji meja: Cari fokus & ambil foto uji harus menghasilkan posisi terukur dan foto asli yang lebih tajam dibanding endpoint 1.0 pada kondisi sama.
- Ulangi pada target jauh yang mewakili jarak kerja survei. Jangan memakai fokus monitor dekat untuk penerbangan. Verifikasi pusat/tepi pada 100%, dengan ISO/shutter tetap dan cahaya cukup.
- Ambil ulang gray card setelah fokus: lensPosition harus tetap, dan perubahan exposure harus meminta pemeriksaan ulang. Selama capture mapping tidak boleh ada focus hunting.
- Uji target minim tekstur, cahaya redup, interupsi/background, disconnect selama AF/lock/capture, dan callback terlambat. Misi belum siap sampai ACK, foto committed, diagnostik dan pemeriksaan tersedia; reconnect tidak menjalankan ulang shutter.
- Periksa data focusCalibration dalam mission.json, lensPosition pada setiap capture, lima skor detail dan pesan minim tekstur. Skor detail belum merupakan klasifikasi tajam/blur tervalidasi.
- Benchmark peak memory dan waktu diagnostik JPEG resolusi maksimum. Analisis dilakukan pada antrean writer untuk foto uji saja, bukan setiap foto mapping.
