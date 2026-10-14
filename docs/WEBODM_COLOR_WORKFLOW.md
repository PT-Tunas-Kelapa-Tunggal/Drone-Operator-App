# Workflow gray card dan WebODM

Implementasi 11 Oktober 2026, native macOS. Foto asli tidak diubah.

1. Foto kartu fisik 18% sebelum terbang dalam pencahayaan lapangan yang sama. Jangan memakai monitor sebagai pengganti kartu. Singkirkan kartu dan cari fokus pada jarak kerja sebelum misi.
2. Satu referensi kartu sebelum terbang cukup untuk alur aplikasi ini; tidak ada langkah wajib mengambil kartu sesudah. **Transfer ke Mac** mengirim semua foto mapping, JPEG/RAW, metadata, dan Calibration. Tidak perlu mengunduh kartu satu per satu.
3. Pada Hasil misi pilih **Siapkan WebODM**. Untuk pembanding pilih Foto asli (tanpa koreksi). Untuk koreksi pilih referensi sebelum terbang, klik/geser kotak pada area kartu yang bersih dan rata, lalu konfirmasi kartu fisik. Kartu harus terlihat jelas pada JPEG asli; aplikasi tidak mengenali kartu secara otomatis.
4. Pilihan koreksi overlap berada di pengaturan eksperimen. Gunakan pada uji terkendali dan bandingkan dengan ekspor tanpa overlap. Foto yang gagal cocok tetap memakai koreksi acuan kartu dan memiliki catatan; tidak dinyatakan berhasil dinormalisasi.
5. Klik **Buat folder WebODM**, lalu **Buka Images**. Upload JPEG dan geo.txt (jika tersedia) di Images saja. Jangan upload References, quality-test, RAW dan JPEG sekaligus, atau processing-report.json sebagai foto.

## Isi ekspor

Setiap ekspor memakai UUID baru di Exports/WebODM_<UUID>/ agar tidak menimpa run sebelumnya. Ekspor dikerjakan dalam staging tersembunyi dan dipublikasikan setelah semua gambar selesai; kegagalan menghapus staging. Foto sumber tetap di lokasi awal dan checksum sumber/output tercatat.

- Images/: hanya mapping JPEG resolusi asli. Ekspor original adalah copy byte-for-byte; ekspor terkoreksi di-encode JPEG quality 0.98 sRGB. Metadata kamera EXIF dan orientasi dipertahankan; MakerApple tidak disalin ke hasil koreksi.
- References/: hanya satu JPEG referensi sebelum terbang yang dipilih untuk koreksi, terpisah dari input WebODM. Pengukuran ulang atau referensi lama tetap tersimpan dalam dataset asli.
- processing-report.json: referensi dan checksum, ROI yang dikonfirmasi operator, gain RGB per foto, pasangan overlap, dan peringatan.
- README.txt: instruksi input dan batas hasil.

geo.txt dibuat hanya bila semua foto memiliki GNSS valid dengan age-at-request maksimal 2 detik dan accuracy nonnegatif. Longitude/latitude mengikuti EPSG:4326. Altitude berasal dari altitudeMSL sidecar; bukan tinggi RTK atau jaminan datum vertikal. Validasi tinggi dan gunakan GCP/checkpoint sesuai kebutuhan. Jika data kurang, ekspor tetap tersedia dengan catatan tanpa geo.txt. [Format resmi WebODM](https://docs.webodm.org/ground-control-points/).

## Metode dan batas teknis

Koreksi acuan memakai median RGB pada ROI preview sRGB yang dilinearisasi. Gain channel = 0.18/median linear; batas ±2 EV, penolakan clipping/dark >1%, minimal 64 pixel dan median absolute deviation/median <0.12 per channel. Ini batas rekayasa awal, bukan ambang universal teruji lapangan. Target 0.18 linear sRGB (~118/255) adalah target rendering visual yang dipilih, bukan pengukuran reflectance absolut. JPEG telah melalui pemrosesan kamera; jangan menerapkan klaim kalibrasi sensor linear/reflectance ke hasil ini.

Referensi harus berasal dari misi yang sama, sebelum foto mapping, dan memiliki pengaturan radiometri yang sama (perubahan posisi fokus diperbolehkan). Koreksi diterapkan ke piksel resolusi penuh melalui CIColorMatrix dengan working space linear sRGB; resolusi, posisi piksel dan orientasi tidak diubah. Highlight yang sudah terpotong dan detail blur tidak dipulihkan.

Overlap mencocokkan preview orientation-corrected maksimal 768 pixel memakai Vision homography, dengan fallback translasi. Preview untuk registrasi diberi normalisasi gain luminansi global khusus pencarian geometri. Pengukuran kecerahan tetap memakai preview asli pada koordinat objek yang cocok. Gerbang: >=200 sampel, >=4 dari 9 sel, tidak memakai channel gelap/clip, deviasi tekstur minimum, korelasi Pearson >0.95, MAD log ratio <0.08, gain maksimal ±1 EV per pasangan dan relatif terhadap awal segmen. Gain luminansi scalar mempertahankan koreksi RGB acuan; tidak mengubah warna per foto berdasarkan histogram umum.

Hanya pasangan berurutan dicoba, bukan bundle adjustment radiometrik seluruh flight block. Parallax terrain/bangunan, yaw besar, tekstur minim, bayangan bergerak, dan pencahayaan lokal bisa menggagalkan kecocokan. Kegagalan menghasilkan fallback acuan kartu dan awal segmen baru, serta catatan eksplisit. Satu referensi awal tidak mengukur perubahan pencahayaan sepanjang penerbangan; koreksi overlap tetap bersifat relatif. Koreksi ini bukan pengganti ColorChecker, panel reflectance, atau sensor irradiance. [Apple registration](https://developer.apple.com/documentation/vision/vnhomographicimageregistrationrequest), [prinsip koreksi warna berdasarkan overlap Agisoft](https://www.agisoft.com/forum/index.php?topic=8284.0).

## Validasi

Jalankan Scripts/test-webodm-export.sh. Fixture JPEG asli yang di-encode secara sintetis menguji netralitas output patch linear, resolusi/EXIF, integritas original, koreksi exposure dengan translasi yang diketahui, penolakan posisi salah/tekstur minim/gain berlebihan, geolocation ordering/staleness, laporan hash, serta rollback jika berkas bukan JPEG. Ini belum uji penerbangan atau rekonstruksi WebODM. Bandingkan dataset asli dan hasil koreksi dengan parameter WebODM yang sama, nilai sambungan warna, detail, coverage, dan checkpoint independen sebelum penggunaan produksi.
