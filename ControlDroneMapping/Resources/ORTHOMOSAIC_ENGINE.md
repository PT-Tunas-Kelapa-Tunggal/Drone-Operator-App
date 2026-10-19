# Pengolahan orthomosaic lokal

Alur: foto per misi → normalisasi opsional dengan gray card awal → rekonstruksi kamera dan permukaan → orthomosaic TIFF/GeoTIFF. Tidak ada analisis VARI.

## Engine bawaan aplikasi

Pengolahan memakai OpenSfM pada Mac Apple Silicon, tanpa WebODM/Docker. Runtime disertakan di Resources aplikasi, sedangkan helper Python bertanda tangan berada di Contents/MacOS dan mewarisi App Sandbox. Aplikasi memeriksa identitas penandatangan, modul engine, dan GPU sebelum menampilkan **Engine lokal siap**. Tidak diperlukan pengunduhan atau pemasangan Python saat memakai aplikasi.

Di **Hasil → Olah foto**, pemeriksaan berjalan otomatis. Jika perlu, klik **Periksa engine**. Build tanpa engine harus dibangun ulang dengan aset lengkap. Folder interpreter eksternal tidak digunakan oleh aplikasi sandbox; izin memilih folder tidak memberikan izin eksekusi. Cache engine lama tidak perlu dihapus dan tidak dipakai bila engine bawaan tersedia. Gray card opsional; jika diunggah, area kartu harus dikonfirmasi untuk normalisasi.

Readiness berhasil diuji melalui executable aplikasi Apple Development bertanda tangan dengan App Sandbox aktif pada Mac pengembangan. Ini belum membuktikan rekonstruksi foto lapangan maupun distribusi Developer ID/notarisasi pada Mac lain.

### Menyiapkan paket untuk build aplikasi (developer)

Kompilasi OpenSfM dilakukan di luar aplikasi sandbox. `xcrun` secara eksplisit menolak dijalankan di dalam App Sandbox; memasang Xcode tambahan tidak memperbaikinya. Memilih folder Python eksternal juga tidak memberikan izin eksekusi sandbox.

1. Bangun runtime di luar aplikasi menggunakan `Scripts/setup-orthomosaic-engine.sh` atau pemasang pengembangan. Gunakan prefix tanpa spasi, compiler/linker Apple, dan SciPy conda-forge 1.15.2 untuk Python 3.10. Wheel PyPI SciPy 1.15.3 ditolak dyld pada macOS pengujian.
2. Jalankan:

   ```sh
   python3 Scripts/package-orthomosaic-engine.py --runtime /lokasi/engine --identity 'identitas signing aplikasi'
   ```

   Script menyiapkan runtime distribusi dengan jalur library relatif, menghapus editable import yang menunjuk source developer, dan menandatangani native library. Interpreter memakai hardened runtime dengan hanya entitlement `app-sandbox` dan `inherit`. Tidak ada penonaktifan sandbox atau library validation. Gunakan identitas Developer ID dan opsi `--timestamp` untuk menyiapkan rilis yang akan dinotarisasi; identitas Apple Development hanya untuk build pengembangan.
3. Build scheme `ControlDroneMapping`. Fase Resources Xcode menyalin `.build/OrthomosaicEngine`; fase Copy Files menyalin `.build/OrthomosaicPython` ke Executables dengan **Code Sign On Copy**. Aset tersebut dan manifest harus dihasilkan sebelum build Mac, termasuk pada mesin CI. Script shell embedding tidak dipakai; App Sandbox dan user-script sandbox tetap aktif.
4. Periksa build tanpa membuka UI:

   ```sh
   /lokasi/ControlDroneMapping.app/Contents/MacOS/ControlDroneMapping --check-orthomosaic-engine
   ```

   Hasil yang diharapkan: `OpenSfM dan GPU lokal siap`, exit 0. Jalankan melalui executable aplikasi, bukan helper secara langsung, agar sandbox inheritance ikut diuji.

Paket runtime tidak dipakai sebagai environment conda yang dapat diubah. Instalasi source conda asli tetap tidak boleh dipindahkan. **Pilih folder engine** tersedia untuk pemeriksaan runtime manual, tetapi folder eksternal biasa belum tentu dapat dieksekusi oleh build sandbox. Untuk penggunaan normal, gunakan paket bawaan.

Dasar upstream: [OpenSfM building](https://github.com/OpenSfM/OpenSfM/blob/master/doc/building.md) dan [dense reconstruction](https://github.com/OpenSfM/OpenSfM/blob/master/doc/dense.md). Panduan Apple: [embedding a command-line tool in a sandboxed app](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app).

## Menyiapkan foto per misi

- Hasil iPhone: transfer seluruh misi ke Mac, lalu pilih **Olah foto** pada kartu misi. Foto mapping dan referensi sebelum penerbangan dibaca dari metadata; checksum diperiksa.
- Impor baru: **Impor dari Finder → Pilih foto pemetaan** atau **Pilih folder foto**. Setiap impor baru menjadi misi pengolahan terpisah. Impor folder hanya membaca gambar di tingkat teratas; RAW, Calibration, dan Exports di subfolder tidak ikut masuk.
- Impor ke misi yang sudah ada: **Impor foto** pada kartu misi, **Lainnya → Impor foto ke misi ini**, atau **Tambah foto dari Finder** pada pengolah misi tersebut. Misi Mac yang belum memiliki dataset iPhone juga tersedia. UUID misi Mac tetap menjadi pengelompokan hasil ketika dataset iPhone ditautkan kemudian.
- Setelah transfer tambahan: gunakan **Lainnya → Muat ulang foto transfer** untuk memperbarui daftar input. Konfirmasi kembali area gray card; riwayat TIFF sebelumnya tetap tersedia.
- Format input: JPEG, HEIC/HEIF, PNG, TIFF. Gunakan JPEG pasangan RAW atau kembangkan RAW secara konsisten terlebih dahulu. Jangan memasukkan beberapa representasi exposure yang sama.
- Tanpa gray card, foto dapat langsung diolah tanpa koreksi warna/exposure. Bila ingin normalisasi, pilih foto gray card awal. Klik/geser kotak sampling dan sesuaikan ukurannya agar hanya berisi bagian kartu yang polos. Konfirmasi waktu pengambilan dan pengaturan kamera. Foto dengan checksum yang sama dengan referensi dikecualikan dari input stitching.

Impor manual menyalin file ke penyimpanan aplikasi. Nama file sama dari folder berbeda tidak bertabrakan; isi identik dideduplikasi. Foto asli tidak ditimpa. Data per misi tersimpan dalam Application Support/DroneControl/Orthomosaics (atau DemoOrthomosaics pada mode demo).

## Warna, geometri, dan hasil

Jika gray card tersedia dan dikonfirmasi, satu set gain RGB dihitung dari gray card 18% pada preview sRGB yang dilinearisasi, lalu diterapkan menggunakan ruang kerja linear pada seluruh foto dan disimpan sebagai PNG sRGB 8-bit. Tanpa gray card, filter gain tidak dijalankan: JPEG RGB 8-bit dengan profil sRGB yang dikenali digunakan tanpa encoding ulang, melalui salinan APFS bila tersedia atau salinan biasa. Format lain, termasuk HEIC, PNG, TIFF dan JPEG wide-gamut, tetap dikonversi menggunakan Core Image. Checksum sumber dan salinan diperiksa; orientasi piksel dan metadata kamera dipertahankan. Pilih **Hapus gray card** untuk mengganti mode pada misi yang sudah memiliki kartu. Ini normalisasi tampilan RGB, bukan kalibrasi reflektansi sensor. Area kartu yang gelap, clipping, tidak seragam, atau memerlukan gain di luar ±2 EV ditolak. Foto iPhone dengan pengaturan radiometri berbeda dari referensi juga ditolak.

Worker memakai estimasi pose, undistortion, rekonstruksi kedalaman OpenCL, fusi permukaan, dan orthophoto OpenSfM. Equalization tambahan dimatikan; satu view digunakan untuk warna akhir, tanpa detail injection, median kosmetik, atau feather antartile. Undistortion dan reprojection tetap melakukan resampling. Resolusi fitur dibatasi 2048 px, depthmap 1600 px, gambar undistorted 4096 px, dengan deteksi fitur berurutan per foto memakai hingga dua thread native OpenCV, batas konfigurasi dua worker untuk tahap lainnya, dan anggaran merge 512 MB. Resolusi output mengikuti rekonstruksi; bukan janji GSD survei.

Semua foto harus masuk satu rekonstruksi; blok terputus/hasil parsial gagal secara eksplisit. Minimal tiga foto berbeda diperlukan, tetapi jumlah minimum ini belum menjamin rekonstruksi berhasil. Pemotretan memerlukan overlap dan tekstur yang memadai.

- **GeoTIFF**: minimal tiga posisi GPS yang tersebar secara dua dimensi tersedia dan hasil engine benar-benar memiliki CRS proyeksi. Koordinat keluaran mengikuti UTM hasil OpenSfM. GPS ponsel tetap perkiraan, bukan RTK atau bukti akurasi absolut.
- **TIFF lokal**: referensi GPS belum memadai. CRS bumi tidak disematkan; posisi dan skala absolut belum tervalidasi.

Setiap proses membuat folder Run baru berisi `orthomosaic.tif`, `preview.png`, `processing-report.json`, `request.json`, `result.json`, log, serta laporan waktu preparasi dan engine. Setelah TIFF lengkap tervalidasi, dataset kerja dihapus secara default; konfigurasi, metadata kamera, rekonstruksi dan laporan OpenSfM dipertahankan dalam `diagnostics`. Aktifkan **Simpan data kerja setelah selesai** untuk mempertahankan seluruh dataset. Pengolahan masih memerlukan ruang sementara yang dapat mencapai beberapa GB. Run lama dan foto asli tidak dibersihkan oleh kebijakan ini. Run yang gagal/dihentikan mempertahankan dataset di folder Unfinished untuk diagnosis. Tombol **Simpan TIFF ke…** menyalin hasil ke tujuan pilihan pengguna. Menutup sheet tidak menghentikan proses; pilih Hentikan bila diperlukan. Aplikasi yang ditutup saat bekerja menandai pengolahan terinterupsi pada pembukaan berikutnya; tidak melanjutkan diam-diam.

`preparation-performance.json` mencatat durasi, jumlah JPEG yang digunakan langsung/PNG yang dikonversi, dan ukuran logis input. `engine-performance.json` diperbarui per tahap, termasuk tahap yang gagal. `workerPeakRSSBytes` merupakan puncak memori proses Python secara kumulatif, bukan total unified memory, memori GPU, atau jumlah semua subprocess. Status `running` yang tertinggal membantu mengidentifikasi tahap saat proses dihentikan paksa. Tidak ada cache lintas run atau resume otomatis.

## Status validasi

Tes otomatis memeriksa impor/transaksi/checksum, pemisahan misi, gray card, normalisasi, kontrak worker, penolakan hasil parsial, metadata koordinat, cancellation, dan state pengolahan. Pengujian ini tidak menggantikan rekonstruksi dataset penerbangan nyata. Validasi end-to-end OpenSfM, performa, serta distribusi Mac dengan sandbox/signing memerlukan runtime lengkap dan dataset lapangan.

### Diagnosis tahap titik foto

“Mencari titik foto” mencari ciri visual, bukan GPS. Adapter menjalankan detektor per foto tanpa antrean producer/consumer atau perintah Linux `free`, sehingga tetap berjalan bila joblib hanya menyediakan satu worker di sandbox. Progres menampilkan nomor foto dan waktu berjalan setiap lima detik; log menyimpan stack Python setiap dua menit untuk diagnosis tahap panjang. Waktu berjalan bukan estimasi waktu selesai. Foto tanpa titik visual atau kegagalan detektor dilaporkan sebagai error.

Pemeriksaan native tanpa UI pada data sintetis (bukan validasi akurasi rekonstruksi):

```sh
/lokasi/ControlDroneMapping.app/Contents/MacOS/ControlDroneMapping --check-orthomosaic-features
```
