# Pressure test dataset fisik — 10 Oktober 2026

## Kesimpulan

Belum layak menyatakan kalibrasi gray card valid atau dataset pasti menghasilkan orthomosaic di WebODM. Pengukuran kamera dan penyimpanan berjalan pada misi terbaru; kualitas kalibrasi dan rekonstruksi belum lulus validasi lapangan.

## Bukti yang diperiksa

- Tes ulang: 147 assertions core, 49 assertions controller dengan hardware simulasi, dan 3 tes auditor Python lulus.
- Inventaris read-only container DroneCam pada iPhone fisik yang paired: empat misi, semuanya hanya berisi Calibration/Metadata (dan RAW pada satu misi). Tidak ada foto mapping di root.
- Misi terbaru `tuu`, ID `11447BDE-5B8D-4AB7-8D63-A5856586462B`: salinan lengkap ke `/tmp/drone-pressure-tuu` melalui CoreDevice, tanpa mengubah iPhone. Audit checksum ketiga JPEG dan keberadaan sidecar lulus. Ini bukan uji tombol transfer melalui MultipeerConnectivity.
- Satu referensi sebelum dan dua foto quality-test. Ketiganya berhasil didekode penuh menggunakan ImageIO, ukuran asli 4032 × 3024, JPEG dengan metadata kamera/focal length/time.
- Manifest mencatat metering ISO 55.384075 × 0.008332 s dan pemilihan ISO 461.4601 × 0.001 s. Produk ISO × waktu dipertahankan oleh perhitungan. Fokus terakhir tercatat 0.7921569 setelah autofocus lalu lock.
- EXIF asli ketiga JPEG melaporkan exposure 0.000999000999 s (~1/1001 s), ISO 500, white balance manual. Shutter mendekati permintaan 1/1000; ISO EXIF berbeda sekitar 0.116 EV dari ISO API yang diminta. Konsisten antarfoto, tetapi jangan menyebut nilai ISO API sebagai hasil EXIF yang persis sama. WB manual tidak membuktikan netralitas warna.
- Inspeksi visual thumbnail dari JPEG asli: referensi bertanda calibration-before memperlihatkan monitor dan ruangan; tidak terlihat gray card. Foto uji terakhir memperlihatkan ruangan gelap. Karena itu operasi sukses tidak membuktikan pengukuran kartu 18% yang benar.
- JPEG asli tidak memiliki GPS EXIF. Sidecar aplikasi mempunyai lokasi, tetapi aplikasi belum mengekspor `geo.txt` dan WebODM tidak membaca sidecar khusus aplikasi secara otomatis.
- Audit sampel lama `sutrisno` menunjukkan shutter/ISO EXIF berbeda jauh dari permintaan. Salinan massal timeout sehingga beberapa berkas lokal parsial; kegagalan checksum pada salinan parsial tersebut tidak menjadi bukti korupsi di iPhone. Misi terbaru disalin ulang secara terpisah dan lengkap.

## Arti status aplikasi

`Diterapkan` berasal dari kecocokan pengaturan draft, ACK, dan telemetry. Status itu membuktikan konfirmasi konfigurasi, bukan pengenalan gray card, ketajaman foto asli, ataupun validasi radiometrik.

Mode panduan menjalankan metering kamera, menghitung ISO/shutter dalam batas gerak, mengunci WB/exposure, dan menyimpan referensi. Operator masih harus menempatkan kartu yang benar di pencahayaan yang sama, menghindari glare/bayangan, dan mengisi sebagian besar frame. Tidak ada deteksi kartu atau pemeriksaan netralitas ROI otomatis. Metering tidak memiliki jaminan target luminansi JPEG tertentu.

Referensi awal/akhir belum digunakan oleh aplikasi untuk menormalisasi semua foto secara otomatis. Exposure/WB terkunci selama misi; perubahan matahari/awan di tengah misi belum dikompensasi atau dikalibrasi secara radiometrik. Gray card tunggal tidak setara dengan profil ColorChecker atau panel reflektansi terkalibrasi.

## WebODM: batas klaim

JPEG asli dapat dibaca; struktur folder memisahkan foto mapping dari calibration/test. Ini membuktikan jalur berkas, bukan keberhasilan rekonstruksi. Saat ini foto mapping berjumlah nol sehingga belum ada dataset penerbangan yang dapat diolah.

Untuk georeferencing diperlukan GPS EXIF yang sesuai, `geo.txt`, atau GCP. Format geolokasi dan prosedur GCP dijelaskan dalam [dokumentasi resmi WebODM](https://docs.webodm.org/ground-control-points/). Kebutuhan overlap dan pengambilan gambar dijelaskan dalam [panduan OpenDroneMap](https://docs.opendronemap.org/flying/). Ketajaman, overlap nyata, tekstur, rolling shutter, kalibrasi kamera, dan checkpoint independen menentukan hasil; tidak ada jaminan hanya karena JPEG bisa diimpor.

Docker CLI tidak ditemukan dan belum ada instance WebODM lokal yang dikonfirmasi. Tidak menjalankan rekonstruksi WebODM, penerbangan, uji putus-sambung radio saat capture, atau endurance/thermal pada sesi ini. Pengujian tersebut tetap diperlukan; tes scheduler/controller simulasi tidak menggantikannya.

## Gerbang validasi berikutnya

1. Ambil referensi kartu fisik 18% dengan pencahayaan lapangan yang benar; periksa ROI netral dan clipping pada foto asli. Jangan memakai monitor sebagai pengganti kartu.
2. Ambil foto uji objek bertekstur pada jarak kerja; periksa crop 100%, actual EXIF, serta cadence berulang. Fokus pada objek dekat di ruangan tidak membuktikan fokus pada tanah dari ketinggian penerbangan.
3. Jalankan misi pendek dengan foto mapping, hilangkan koneksi Mac selama capture, lalu reconnect dan transfer melalui tombol aplikasi. Bandingkan jumlah, UUID, dan checksum sumber/tujuan.
4. Lengkapi georeferencing; proses JPEG mapping saja di WebODM. Nilai kamera yang berhasil direkonstruksi, reprojection error, coverage/hole, seam warna, serta error checkpoint independen sebelum menerima hasil profesional.
5. Uji kondisi pencahayaan berubah. Jika konsistensi warna lintas perubahan awan menjadi persyaratan, tambahkan workflow koreksi saat pengolahan dan validasi radiometrik; alur saat ini belum memenuhi klaim normalisasi otomatis sepanjang penerbangan.
