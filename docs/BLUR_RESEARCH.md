# Pencegahan blur pada DroneCam

Ditinjau 10 Oktober 2026. AF → lock → foto uji dan analisis crop asli kini diimplementasikan. Efektivitasnya belum diuji pada perangkat fisik.

## Kesimpulan dan temuan pada implementasi

Pendekatan prioritas: fokus berdasarkan pengukuran pada jarak kerja → kunci fokus → batasi exposure menurut gerak dan GSD → kendalikan getaran → periksa foto asli. Optimalitas akhir harus ditentukan melalui eksperimen pada iPhone, mount, format dan kondisi penerbangan yang digunakan.

Kode saat ini menetapkan lensPosition = 1 pada default, rekomendasi manual, dan GuidedAcquisition.plan. Metering gray card membentuk ulang rekomendasi tersebut. Apple secara eksplisit menyatakan 1 adalah posisi terjauh aktuator, bukan jaminan infinity; nilainya tidak identik antarperangkat. Karena itu, fokus 1 tidak boleh dianggap sebagai kalibrasi fokus. Screenshot monitor dekat yang tampak lembut konsisten dengan defocus, tetapi preview gelap/resolusi rendah tidak cukup untuk diagnosis. [Apple lensPosition](https://developer.apple.com/documentation/avfoundation/avcapturedevice/lensposition).

Aplikasi sudah menghitung blur translasi dengan budget 0.5 pixel dan margin 0.8 pada shutter; belum memasukkan gerak angular/getaran. PreviewAssessment hanya memeriksa brightness/clipping, belum ketajaman. Foto menggunakan .speed: header resmi AVCaptureDevice SDK menyatakan .balanced/.quality dapat mengganti ISO/durasi melalui fusion pada cahaya redup, sedangkan .speed diperlukan untuk mempertahankan exposure manual. Ini harus diverifikasi pada EXIF foto asli, bukan hanya nilai yang diminta aplikasi.

## Evaluasi alternatif

| Pendekatan | Manfaat | Batas / keputusan |
|---|---|---|
| Fokus selalu 1.0 | Sederhana | Ditolak sebagai bukti fokus benar; tidak portabel antar iPhone |
| Autofocus terus sepanjang penerbangan | Mengikuti jarak berubah | Dapat hunting/berubah pada air, vegetasi atau bayangan; perubahan kondisi optik perlu diperhitungkan. Bukan default awal |
| Autofocus sekali pada target bertekstur di jarak kerja, verifikasi, lalu lock | Praktis; konfigurasi lebih konsisten | Rekomendasi awal. Gagal fokus harus menghasilkan arahan operator, bukan status siap |
| Sweep fokus lokal dengan beberapa foto | Memilih posisi terbaik berdasarkan bukti foto | Tahap kedua bila AF tidak konsisten; perlu target bertekstur, exposure sebanding dan waktu pra-terbang |
| Shutter tetap 1/1000 | Mudah | Tidak cukup untuk semua kecepatan/GSD; pakai batas dari geometri |
| Perlambat atau stop-and-shoot | Mengurangi gerak translasi | Menambah waktu dan tetap tidak menghilangkan getaran. Aplikasi kamera belum mengendalikan autopilot |
| Gimbal / mount peredam | Mengurangi gerak angular/transmisi getaran | Uji resonansi, distribusi berat dan posisi kamera; OIS bukan pengganti mount |
| Deblur/sharpen sesudah capture | Dapat memperbaiki penampilan | Bukan jalur utama dataset metrik; perlu validasi terhadap detail asli dan checkpoint, simpan sumber tanpa modifikasi |

Apple menyediakan autoFocus, isAdjustingFocus serta lock posisi lensa. Rancangan sebaiknya menunggu fokus selesai, memotret uji, dan menyimpan posisi terukur. [Apple Focus](https://developer.apple.com/documentation/avfoundation/capture-device-focus).

## Shutter dan kecepatan

Untuk translasi nadir di bidang datar: b ≈ v × t / GSD. Jadi t maksimum = b_target × GSD / v. Ini turunan model geometrik sederhana, bukan klaim seluruh blur sudah dimodelkan. Budget 0.5 pixel adalah target rekayasa awal yang perlu diuji.

Contoh v = 5 m/s, GSD aktual perkiraan = 0.59 cm/px: t ≤ 0.00059 s (sekitar 1/1700). Margin 0.8 memberi sekitar 1/2100. Pada 1/1000, blur translasi diperkirakan 0.85 pixel. Gunakan GSD yang dihitung dari kamera/tinggi, bukan hanya target GSD yang diketik operator.

Gerak angular di sekitar pusat secara pendekatan b_rotation ≈ f_px × omega × t, dengan omega dalam rad/s. Gerak pada tepi, rotasi roll, readout rolling shutter, OIS dan getaran memerlukan model lebih lengkap. Gyro dapat dipakai sebagai indikator risiko setelah sinkronisasi waktu dan orientasi kamera diuji; tidak boleh dianggap pengukur blur aktual yang sempurna.

Jika ISO untuk shutter aman terlalu tinggi, pilih memperlambat penerbangan, cahaya lebih baik, atau format/resolusi yang sudah diuji. ISO ceiling 800 saat ini hanya kebijakan awal, belum batas mutu universal. Interval mengatur overlap, bukan durasi exposure; menaikkan interval saja tidak menyembuhkan blur.

## Mount, rolling shutter dan pemrosesan

Apple merekomendasikan mount peredam atau gimbal untuk penggunaan pada drone dan menjelaskan sensitivitas OIS/AF terhadap getaran tertentu. Jangan menganggap stabilisasi video yang dinonaktifkan berarti OIS fisik juga dinonaktifkan. [Apple vibration guidance](https://support.apple.com/en-ie/102175).

Rolling shutter mendistorsi geometri antarbaris dan berbeda dari blur selama exposure. Shutter pendek tidak membuat sensor menjadi global shutter. Penelitian Vautherin dkk. menunjukkan manfaat pemodelan rolling shutter pada rekonstruksi UAV, tetapi hasil tersebut tidak langsung memvalidasi readout iPhone. [ISPRS 2016](https://isprs-annals.copernicus.org/articles/III-3/139/2016/).

## Pemeriksaan ketajaman

Nilai Tenengrad/modified Laplacian pada beberapa crop resolusi asli (pusat dan tepi), dengan penolakan patch minim tekstur dan evaluasi noise. Skor dari gambar yang diperkecil tidak cukup untuk menjamin detail pixel asli. Jangan menggunakan satu ambang universal lintas resolusi, ISO, JPEG/RAW atau jenis medan. Studi focus measures membandingkan sensitivitas metode terhadap kondisi citra; aplikasi pada iPhone aerial tetap memerlukan kalibrasi sendiri. [Pertuz dkk. 2013](https://www.sciencedirect.com/science/article/pii/S0031320312004736).

Gabungkan bukti citra, exposure aktual, fokus terukur dan data gerak. Studi Teo & Zhan menguji gabungan citra dan POS pada dataset eBee; mendukung evaluasi multi-sumber, bukan jaminan akurasi detektor iPhone. [ISPRS 2016](https://isprs-archives.copernicus.org/articles/XLI-B1/1051/2016/).

Analisis dijalankan terpisah dari antrean capture dan dibatasi bebannya. Simpan semua foto asli; tandai suspect blur untuk review. Jangan otomatis membuang foto atau menunda shutter tanpa menghitung dampak terhadap overlap. Status READY saat ini berarti fase kamera siap, bukan bukti foto tajam.

## Alur aplikasi yang direkomendasikan

1. Isi rencana dan hitung exposure/interval awal.
2. Ukur cahaya dan WB dengan gray card; jangan jadikan kartu dekat sebagai target fokus penerbangan.
3. Singkirkan kartu. Arahkan ke target bertekstur pada jarak kerja yang representatif. Jalankan autofocus sekali, verifikasi foto asli, lalu lock. Mode uji meja memakai jarak objek meja; hasil itu tidak dianggap kalibrasi fokus udara.
4. Simpan posisi fokus terukur; apply ulang atau gray-card metering tidak boleh diam-diam menggantinya dengan 1.0. Jika kamera/lensa/format/fokus berubah, ulangi verifikasi yang relevan.
5. Uji capture berulang dengan mount nyata sebelum terbang; periksa pusat/tepi, exposure, interval aktual, panas dan getaran.
6. Selama misi simpan asli dan indikator QA lokal walau Mac disconnect. Tampilkan tindakan seperti 'Fokus belum terverifikasi', 'Kurangi kecepatan', atau 'Periksa getaran'.

## Eksperimen penentu keputusan

- Statis, terang, kamera diam: bandingkan fokus 1.0 dengan AF-lock dan sweep lokal pada target dekat serta target jauh bertekstur. Pertahankan exposure/format agar perubahan bisa diatribusikan ke fokus.
- Dengan fokus terbaik terkunci: bandingkan shutter sekitar 1/1000, 1/2000, 1/4000 bila rentang exposure memungkinkan; catat ISO/noise dan EXIF aktual.
- Pada mount drone: bandingkan kamera diam, hover dan lintasan pada kecepatan yang direncanakan. Pisahkan pengaruh getaran dari translasi.
- Bandingkan format/resolusi yang benar-benar didukung, dengan fokus terverifikasi untuk setiap konfigurasi dan capture berulang yang sebanding.
- Ukur persentase foto usable, detail pusat/tepi, cadence, missed slots, tie-point coverage, residual bundle adjustment dan RMSE checkpoint independen. Kesimpulan tidak boleh hanya berdasarkan preview terlihat tajam.

Prioritas implementasi berikutnya adalah AF → verifikasi → lock, kemudian QA ketajaman resolusi asli, lalu integrasi gyro dan pengujian mount. Implementasi sekarang menjalankan autofocus saat foto uji mode panduan, menunggu posisi stabil, mengunci hasil terukur, mempertahankan posisi saat gray-card metering, dan menghasilkan diagnostik Tenengrad dari lima crop JPEG resolusi asli. Tidak ada ambang lulus blur universal; pemeriksaan foto asli oleh operator tetap wajib. Pengambilan foto misi tidak menjalankan autofocus atau analisis ini berulang. Timeout AF 6 detik dan callback lock 5 detik mengembalikan kegagalan yang dapat ditangani operator.
