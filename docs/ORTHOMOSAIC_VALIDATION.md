# Validasi panel Hasil dan pengolah lokal — 15 Oktober 2026

## Sudah diperiksa

- Build macOS scheme ControlDroneMapping, destination My Mac, tanpa signing: berhasil.
- `Scripts/test-orthomosaic.sh`: 52 assertions Swift dan 6 tes adapter Python. Cakupan: impor transaksional, nama file sama, deduplikasi, checksum, pengecualian gray card, pemisahan proyek, UUID misi Mac vs dataset iPhone, recovery interupsi, penerapan gain linear RGB pada gambar nyata sintetis, metadata GNSS segar/kedaluwarsa, penolakan hasil parsial, riwayat, reentrancy, pergantian editor, dan penghentian worker termasuk fallback saat SIGTERM diabaikan. Tambahan pemasang: penolakan start ganda, editor tetap dapat dipakai, tutup/pindah misi selama instalasi, cancel, pesan kegagalan jaringan, retry, pemilihan otomatis, HTTP error, penolakan readiness setelah download bila validasi gagal, serta penghentian proses anak pemasang yang mengabaikan SIGTERM. Error DNS menyebut host dan dibedakan dari offline; prefix dengan spasi ditolak sebelum mengunduh atau membuat environment.
- `Scripts/test-architecture.sh`: 21 assertions batas layanan lulus.
- `Scripts/test-control-flow.sh`: 122 assertions controller dengan hardware sintetis lulus.
- Tes adapter memeriksa blok rekonstruksi, pemisahan camera model setelah normalisasi, urutan command, opsi warna, syarat keluaran GeoTIFF, serta penghentian child process pool tanpa mematikan worker induk.
- Pemeriksaan aplikasi demo melalui UI: panel Hasil, menu impor, pemilihan folder Finder, impor tiga PNG sintetis, editor per misi, impor gray card terpisah, preview/ROI, dan persistensi konfirmasi ketika editor ditutup. Tombol proses tetap nonaktif ketika engine belum siap.
- Script pemasangan engine diperiksa sintaksnya. Worker dan panduan pemasangan disertakan dalam Resources paket aplikasi.
- Pemasang native: tombol **Unduh & pasang engine**, status background, tombol batal, serta kegagalan jaringan dengan **Coba pasang lagi** terlihat lewat UI aplikasi demo. Pada percobaan awal, unduhan sebenarnya gagal menghubungi host dan runtime tidak dinyatakan siap. Pratinjau memakai salinan build `.build/EngineInstallerPreview.app` dengan flag demo di Info.plist salinan build, tanpa mengubah konfigurasi source. Dataset impor demo yang sudah ada tetap terbaca.
- Diagnosis jaringan: resolver Wi-Fi mengembalikan SERVFAIL untuk GitHub; resolver publik berhasil, dan HTTPS GitHub berhasil ketika memakai hasil DNS tersebut. Dengan persetujuan pengguna, DNS diubah sementara selama pemasangan. Bootstrap micromamba terunduh dari aplikasi, lalu ditemukan dan diperbaiki pembacaan pybind11 yang sebenarnya sudah dibundel di source OpenSfM.
- Runtime nyata berhasil dikompilasi di Library/Caches/DroneControl/Engines/OpenSfM-local-v1 memakai compiler/linker Apple. Prefix Application Support dengan spasi dan linker conda yang tidak mengenali arsitektur SDK macOS baru dihindari. SciPy PyPI yang ditolak dyld diganti dengan SciPy 1.15.2 conda-forge. Worker asli `--check` menghasilkan `ready: OpenSfM dan GPU lokal siap` (exit 0), tanpa stub atau menonaktifkan pemeriksaan pemuat library. Commit OpenSfM: `c1fbfcec947e0e4fa4d39eb02a66cddac10934ad`.
- Alur layanan pemasang akhir dijalankan ulang pada instalasi nyata: preflight Apple, cache sumber, lock dependensi, SciPy conda, build editable, rasterio, dan `LocalOrthomosaicProcessor.check` selesai dengan exit 0. DNS Wi-Fi kemudian dikembalikan ke otomatis dan diverifikasi melalui konfigurasi sistem. Setelah aplikasi terbaru dibuka ulang, UI otomatis menemukan engine, menampilkan **Engine lokal siap**, dan mengaktifkan **Buat orthomosaic** pada proyek demo yang sudah dikonfirmasi. Tidak ada pengolahan foto atau hasil TIFF baru yang dibuat dalam verifikasi pemasangan ini.

Tes normalisasi Core Image dan build SwiftUI membutuhkan layanan grafis/compiler di luar pembatasan shell sandbox pengujian. Build/tes berhasil setelah akses tersebut tersedia; ini terpisah dari sandbox distribusi aplikasi.

## Belum terbukti

Rekonstruksi end-to-end dari foto lapangan menjadi TIFF/GeoTIFF belum dijalankan. Worker contract dalam tes memakai fixture yang jelas terpisah dari implementasi produksi; hasil tes tersebut tidak membuktikan rekonstruksi atau akurasi pemetaan. Pemeriksaan engine/GPU nyata hanya membuktikan runtime dapat dimuat dan pipeline yang diperlukan tersedia.

Kualitas geometri/warna dataset iPhone, waktu/memori/disk pengolahan, dan akses interpreter eksternal pada aplikasi sandbox bertanda tangan masih perlu diuji. Keluaran lokal tidak mengklaim posisi atau skala absolut. Keluaran GeoTIFF memakai GNSS perkiraan dan belum memiliki pengukuran checkpoint. Engine merupakan aset yang dapat dipasang ulang di Caches; penghapusan cache oleh sistem memerlukan pemasangan kembali.

## Langkah verifikasi berikutnya

Pasang engine melalui tombol **Unduh & pasang engine** sesuai [panduan](../ControlDroneMapping/Resources/ORTHOMOSAIC_ENGINE.md), lalu proses satu misi kecil dengan overlap memadai dan gray card awal. Pilih folder engine hanya diperlukan untuk instalasi manual. Periksa seluruh foto masuk satu rekonstruksi; buka TIFF di penampil gambar/GIS, periksa alpha/no-data, sambungan, CRS/posisi bila GPS memadai, dan bandingkan foto yang dinormalisasi dengan sumber. Ulangi pada build distribusi bertanda tangan sebelum menyatakan fitur siap digunakan di lapangan.

## Koreksi integrasi aplikasi utama — sesi lanjutan

Hasil readiness pada preview tanpa sandbox tidak membuktikan kesiapan aplikasi utama. Pengujian aplikasi utama bertanda tangan menunjukkan: `xcrun` secara eksplisit menolak App Sandbox; Python eksternal ditolak eksekusinya; runtime bertanda tangan yang diekstrak ke cache juga ditolak. Helper Python di paket aplikasi berhasil diluncurkan, tetapi Gatekeeper memblokir pemuatan `_ctypes.cpython-310-darwin.so` dari cache dan menampilkan peringatan verifikasi malware. Tidak ada pengecualian Gatekeeper yang diterapkan.

Percobaan bundling seluruh runtime belum tervalidasi. Langkah build eksperimen yang gagal karena izin script dihapus dari proyek. Paket serta skrip packaging merupakan pekerjaan pengembangan yang belum menjadi jalur distribusi terverifikasi. Integrasi engine pada aplikasi utama belum selesai; jangan menyatakan fitur siap atau meminta pengguna menonaktifkan perlindungan macOS. Tes terakhir: 54 assertions Swift dan 6 tes Python lulus, terpisah dari validasi keamanan distribusi.

## Perbaikan sandbox terverifikasi — 15 Oktober 2026

Jalur build kini memakai fase Resources dan Copy Files bawaan Xcode: seluruh runtime berada di `Contents/Resources/OrthomosaicEngine`, helper di `Contents/MacOS/OrthomosaicPython` dengan Code Sign On Copy. Tidak menggunakan script embedding atau menonaktifkan user-script sandbox. Aset engine wajib disiapkan sebelum build Mac. Aplikasi memprioritaskan engine tertanam; interpreter eksternal ditolak dengan pesan yang jelas dalam App Sandbox, dan pilihan folder eksternal disembunyikan pada build sandbox.

Build Debug Apple Development dari scheme ControlDroneMapping berhasil di `.build/sandbox-engine`. Executable aplikasi akhir dijalankan dengan `--check-orthomosaic-engine`, tanpa UI, menghasilkan `OpenSfM dan GPU lokal siap` dan exit 0. Jalur ini memakai `LocalOrthomosaicProcessor.check` produksi beserta validasi identitas helper dan modul GPU. `codesign --verify --deep --strict` berhasil. Entitlement aplikasi tetap `app-sandbox=true`; helper hanya memiliki `app-sandbox=true` dan `inherit=true`. Tidak ada perubahan Gatekeeper, SIP, quarantine, DNS, atau library validation.

Tes akhir: 54 assertions Swift dan 6 tes Python lulus. Hasil ini menggantikan status integrasi terblokir pada catatan sesi sebelumnya untuk Mac pengembangan ini. Rekonstruksi foto lapangan end-to-end, distribusi Developer ID/notarisasi, dan penggunaan pada Mac lain tetap belum diuji. Aplikasi yang sedang terbuka dari build lama perlu ditutup dan diganti dengan build baru; pengujian sesi ini tidak mengontrol UI pengguna.


## Gray card opsional dan antrean fitur — 15 Oktober 2026

Gray card kini opsional pada domain, tombol proses, dan preparasi native. Tanpa referensi, tidak ada filter gain RGB/exposure; konversi PNG sRGB 8-bit untuk engine tetap dilakukan. Referensi yang diunggah tetap harus dikonfirmasi. Request versi 2 mencatat `normalization: none` atau `gray-card`, dengan gains/hash referensi hanya pada mode normalisasi. Semua referensi dikecualikan dari stitching; tombol hapus gray card mengeluarkan foto referensi dari daftar pemetaan sebelum melepas referensinya.

Log pengguna berhenti setelah antrean fitur berisi 10 gambar, tanpa log ekstraksi pertama. Sumber joblib menunjukkan fallback satu worker ketika semaphore multiprocessing tidak tersedia. Diagnostik aplikasi sandbox mengonfirmasi `ThreadingBackend().effective_n_jobs(2) == 1`. Alur producer/consumer OpenSfM meminta dua worker, tetapi ketika dijalankan serial, producer memenuhi antrean sebelum consumer dapat bekerja. Peringatan `free: command not found` berasal dari perencanaan memori Linux upstream.

Adapter sekarang memanggil detektor upstream berurutan per gambar, tanpa antrean tersebut atau pemeriksaan `free`, dengan OpenCV satu thread selama deteksi. Kesalahan/hasil kosong langsung diteruskan. Progress menyebut nomor foto dan waktu berjalan; stack diagnostik ditulis setiap 120 detik pada tahap panjang. Batas dua worker tahap lain tidak dinaikkan dan keamanan macOS tidak diubah.

Validasi: 60 assertions Swift dan 7 tes Python lulus; termasuk piksel tanpa gain vs dengan gain, request tanpa referensi fiktif, tombol start tanpa kartu, serta propagasi kesalahan/hasil kosong detektor. Build bertanda tangan berhasil. `--check-orthomosaic-features` pada executable aplikasi sandbox menghasilkan `Deteksi titik foto nyata selesai: 12/12 foto uji sintetis (joblib workers: 1)`, exit 0, melewati batas antrean lama 10 foto. Ini memakai detektor SIFT nyata, bukan stub. Seluruh misi pengguna sampai TIFF belum dijalankan ulang pada sesi ini.

## Optimasi M5 — 18 Oktober 2026

JPEG sRGB tanpa gray card kini dapat dipakai tanpa konversi PNG. Detektor menggunakan dua thread native per foto setelah benchmark 1/2/4 thread menunjukkan hasil fitur identik dan keuntungan minimal dari empat thread. Run baru yang berhasil dibersihkan setelah validasi dan publikasi; foto asli, laporan dan riwayat lama tetap tersimpan. Pengguna dapat mengaktifkan penyimpanan seluruh data kerja. Tahap gagal/dihentikan tetap menyimpan dataset untuk diagnosis.

Tes terbaru: 72 assertions Swift dan 9 tes Python lulus. Build bertanda tangan, verifikasi signature, serta diagnostik detektor dalam sandbox berhasil dengan `joblib workers: 1, native threads: 2`. Dua rekonstruksi nyata pada 12 foto sampel Caliterra, menggunakan runtime pengembangan native, menghasilkan GeoTIFF EPSG:32614 dengan 12/12 foto dalam satu blok. Rata-rata reprojection error sekitar 0,577 px pada jalur lama dan 0,576 px pada jalur baru. Ini menggantikan status belum adanya uji rekonstruksi sampel pada catatan sebelumnya, tetapi bukan pengujian seluruh misi pribadi pengguna atau bukti akurasi survei. Tidak ada UI yang dikendalikan dalam pengujian ini. Detail pengukuran dan batas klaim ada di [laporan performa M5](ORTHOMOSAIC_PERFORMANCE.md).
