# Dasar riset dan keputusan teknis

Tanggal tinjauan: 10 Oktober 2026. Status: rancangan dan implementasi tahap pertama, belum tervalidasi pada penerbangan. Rekomendasi di bawah adalah hipotesis operasional yang harus diuji pada model iPhone, mount, kecepatan, dan kondisi cahaya aktual. Sistem ini mengendalikan akuisisi kamera, bukan autopilot drone.

## 1. Geometri dan image acquisition

Orthomosaic membutuhkan rekonstruksi geometri (SfM, bundle adjustment, model permukaan, orthorectification), bukan sekadar panorama/stitching. Ketajaman, overlap efektif, distribusi titik kontrol, dan stabilitas kalibrasi lebih menentukan akurasi daripada angka megapixel saja.

Agisoft menyebut minimal sekitar 80% forward dan 60% side overlap untuk pengambilan udara umum. Ini pedoman awal vendor, bukan jaminan semua medan. Implementasi memberi saran awal 80% forward dan 70–80% side sebagai margin operasional; vegetasi, tekstur berulang, dan relief memerlukan percobaan dengan overlap lebih besar. [Agisoft, Image Capture Tips](https://www.agisoft.com/pdf/tips_and_tricks/Image%20Capture%20Tips%20-%20Equipment%20and%20Shooting%20Scenarios.pdf).

Untuk nadir pada bidang datar, dengan tinggi di atas tanah H, focal length terkalibrasi f dalam pixel, dimensi searah gerak N, kecepatan tanah v dan overlap o:

- GSD = H / f, dalam meter/pixel.
- Footprint searah gerak = N × GSD.
- Interval maksimum = footprint × (1 − o) / v.
- Blur translasi dalam pixel ≈ v × waktu exposure / GSD.
- Batas exposure untuk budget blur b = b × GSD / v.

Ini turunan model pinhole, bukan pengukuran akurasi absolut. Contoh H=80 m, f=3000 px, N=3024 px, v=5 m/s, o=0.8 menghasilkan GSD 2.67 cm/px, interval 3.226 detik dan batas exposure 1/375 s untuk blur translasi 0.5 px. Nilai f contoh bukan spesifikasi iPhone. Getaran, gerak angular, relief, perubahan kecepatan, dan rolling shutter tidak tercakup; pilih margin lebih ketat berdasarkan hasil uji. Side spacing dihitung dengan footprint lintas arah terbang; jangan tertukar orientasi sensor.

Kalibrasi geometrik harus mempertahankan kamera fisik, fokus, resolusi, dan pipeline pemrosesan. Hindari pergantian lensa otomatis dan digital zoom selama misi. Lakukan test field/checkerboard multi-orientasi dan bundle adjustment dengan geometri kuat; nadir tunggal di medan datar dapat membuat parameter focal length dan elevasi saling berkorelasi. Validasi dengan checkpoint independen, jangan menggunakan titik yang sama sebagai GCP dan bukti akurasi. Pedoman USGS menempatkan kalibrasi geometrik, radiometrik, QA, dan metadata ketidakpastian sebagai bagian akuisisi data kuantitatif. [USGS OFR 2023–1033](https://pubs.usgs.gov/publication/ofr20231033).

Posisi iPhone bukan RTK/PPK. Simpan waktu GNSS, horizontal/vertical accuracy, dan umur sampel. Altitude Core Location bukan tinggi AGL; jangan masukkan langsung ke rumus GSD. Untuk target sentimeter diperlukan kontrol tanah terukur atau integrasi GNSS eksternal beserta sinkronisasi shutter dan lever arm yang tervalidasi. Tahap pertama menyimpan geolokasi perkiraan di sidecar, tanpa klaim akurasi survei.

## 2. Kamera iPhone: alternatif dan kompromi

| Opsi | Keuntungan | Keterbatasan | Keputusan awal |
|---|---|---|---|
| JPEG hasil AVFoundation | Ringkas, interoperabel, throughput lebih ringan | Tone mapping, sharpening, noise reduction dapat berubah; kompresi lossy | Baseline untuk semua perangkat yang mendukung kontrol manual |
| Bayer RAW + JPEG | Data sensor minimal proses; pengembangan warna konsisten dapat dilakukan offline | Berkas besar, throughput/panas, resolusi bergantung format perangkat | Pilihan eksplisit jika tersedia, tanpa fallback diam-diam |
| Apple ProRAW | Rentang edit RAW dengan computational photography | Fusion multi-frame dapat mempengaruhi adegan bergerak; dukungan berbeda antar perangkat | Ditunda sampai eksperimen banding bergerak tersedia |
| Frame video | Cadence tinggi | Resolusi/kompresi/pipeline berbeda dari still photo | Bukan jalur foto pemetaan utama |

Apple membedakan Bayer RAW dari ProRAW dan menjelaskan bahwa ProRAW menggunakan teknik multi-image fusion. Format harus dideteksi melalui output aktif; data RAW dari `fileDataRepresentation()` berupa DNG. RAW+JPEG menghasilkan callback untuk masing-masing hasil. Implementasi menyimpan keduanya sebelum menyatakan satu capture berhasil. Resolusi yang diminta adalah maksimum pada format aktif, bukan jaminan resolusi sensor maksimum yang dipasarkan. [Apple RAW/ProRAW](https://developer.apple.com/documentation/avfoundation/capturing-photos-in-raw-and-apple-proraw-formats).

Prinsip awal: wide camera fisik, zoom 1×, ISO serendah mungkin **yang masih memenuhi batas blur dan highlight**, shutter pendek berdasarkan GSD/gerak, fokus terkunci setelah pemeriksaan ketajaman objek jauh, WB tetap per kondisi cahaya. ISO terendah bukan selalu terbaik jika shutter terlalu lambat. Focus position 1 bukan bukti semua objek tajam. Aperture hanya boleh ditawarkan bila API/perangkat benar-benar mendukung; tahap pertama tidak menebaknya. EV compensation auto tidak mempunyai fungsi yang sama ketika ISO/shutter sudah eksplisit terkunci.

Shutter pendek mengurangi blur tetapi tidak menghilangkan rolling shutter: setiap baris tetap dibaca pada waktu berbeda. Vautherin dkk. menunjukkan peningkatan akurasi dengan pemodelan rolling shutter pada dataset UAV, khususnya kecepatan tinggi; hasil itu bukan kalibrasi readout iPhone. Uji mount, kecepatan dan software yang mendukung model tersebut. [ISPRS 2016, DOI 10.5194/isprs-annals-III-3-139-2016](https://isprs-annals.copernicus.org/articles/III-3/139/2016/isprs-annals-III-3-139-2016.html).

Stabilisasi koneksi video dan stabilisasi foto adalah pengaturan berbeda. Implementasi mematikan stabilisasi video bila didukung dan content-aware distortion correction. Seluruh foto kini menggunakan photoQualityPrioritization `.speed`: header resmi AVCaptureDevice menyatakan `.balanced`/`.quality` dapat mengubah ISO/durasi exposure dalam kondisi gelap walaupun mode custom terkunci. Pilihan `.speed` mempertahankan exposure manual dan diwajibkan untuk Bayer RAW; tetap perlu pemeriksaan metadata exposure aktual dan mutu JPEG pada perangkat. API stabilisasi foto lama sudah deprecated sehingga tidak digunakan; ini **bukan bukti OIS mekanis benar-benar terkunci** pada semua iPhone. Hindari klaim intrinsics konstan tanpa pengujian. [Apple still stabilization](https://developer.apple.com/documentation/avfoundation/avcapturephotosettings/isautostillimagestabilizationenabled).

## 3. Gray card, ColorChecker, dan radiometri

| Referensi | Yang bisa dibantu | Yang tidak otomatis diperoleh |
|---|---|---|
| Gray card netral | Titik netral WB; pembandingan exposure antar referensi | Profil warna lengkap, reflectance absolut, koreksi awan sepanjang misi |
| ColorChecker | Profil rendering warna berdasarkan banyak patch, evaluasi perbedaan warna | Kalibrasi spektral sensor atau reflectance setiap band |
| Panel reflektansi terkalibrasi | Hubungan radiometrik dengan target bernilai diketahui, dalam pipeline yang sesuai | Koreksi otomatis BRDF, shadow, perubahan spektrum iluminasi atau ISP nonlinear |
| Downwelling irradiance + panel | Pemantauan perubahan iluminasi | Solusi universal tanpa kalibrasi orientasi/spektral/waktu |

Gray card efektif sebagai langkah praktis konsistensi WB, bukan pengganti proses radiometrik. Apple menyediakan `grayWorldDeviceWhiteBalanceGains` dengan asumsi target netral mengisi 50% bagian tengah frame. Aplikasi membaca gain, memvalidasi rentang, lalu menunggu callback lock. Tombol **Ambil referensi gray card 18%** menjalankan lock dan capture referensi dalam satu operasi lokal iPhone; koneksi Mac tidak diperlukan untuk menyelesaikan operasi yang sudah diterima. Status tersimpan menunggu preview setelah berkas asli committed dan dicocokkan dengan ID perintah, misi, serta pengaturan kamera. ISO dan shutter tidak diubah oleh gray card. Tidak ada deteksi kartu otomatis atau jaminan kartu benar-benar netral. [Apple gray-world gains](https://developer.apple.com/documentation/avfoundation/avcapturedevice/grayworlddevicewhitebalancegains).

ColorChecker menambahkan informasi patch berwarna untuk membuat profil kamera pada workflow pengembangan RAW. Ini berbeda dari hanya memilih titik WB. Profil perlu diuji pada pencahayaan dan pipeline yang sesuai. Tahap pertama hanya menyimpan foto referensi; belum melakukan deteksi patch, pembuatan DCP/ICC, atau penghitungan ΔE. [Calibrite workflow](https://calibrite.com/white_balance_and_colour_calibration_in_photoshop_acr10-3/).

Untuk reflectance kuantitatif, penelitian radiometric block adjustment menggabungkan normalisasi antar gambar dengan referensi radiometrik dan dapat memperhitungkan sifat directional/BRDF. Empirical line memerlukan asumsi hubungan respons dengan reflectance; menerapkannya langsung ke RGB JPEG yang sudah tone-mapped tidak otomatis sah. Hasil multispektral tidak bisa dipindahkan begitu saja ke iPhone RGB. [Honkavaara dkk., Remote Sensing 2018, 10(2), 256](https://www.mdpi.com/2072-4292/10/2/256), [evaluasi Sequoia 2021](https://www.mdpi.com/2072-4292/13/4/577).

Prosedur yang diusulkan untuk diuji:

1. Bersihkan lensa/target; catat ID kartu/panel dan pencahayaan. Tentukan parameter kamera memakai area survei dengan highlight paling terang yang relevan.
2. Letakkan kartu pada iluminasi lapangan yang sama, tidak tertutup bayangan operator atau silau. Ukur dan kunci WB; jangan mengubah exposure hanya agar kartu memenuhi frame jika itu membuat area survei clipping.
3. Simpan referensi sebelum terbang dengan parameter yang digunakan pada misi. Ambil ColorChecker/panel tambahan bila tujuan memerlukannya. Simpan RAW bila tersedia.
4. Selama terbang pertahankan pengaturan untuk satu segmen. Bila cahaya berubah besar, jeda dan dokumentasikan pergantian segmen; mengunci exposure juga bisa menghasilkan foto under/overexposed saat awan berubah.
5. Sesudah terbang ambil referensi kedua tanpa terlebih dahulu mengukur ulang WB; itu memungkinkan evaluasi drift. Bila mengkalibrasi lagi, simpan sebagai referensi tambahan.
6. Bandingkan nilai patch netral, clipping, residual warna, dan seam sebelum/sesudah koreksi. Ulangi pada matahari stabil dan awan bergerak. Jangan menyimpulkan keberhasilan hanya karena mosaic tampak mulus.

Pre/post panel tidak mengukur semua perubahan cahaya di tengah penerbangan. Literatur 2024 menguji perbaikan radiometric block adjustment di bawah iluminasi berubah; kebutuhan penelitian tersebut menegaskan pentingnya observasi temporal, bukan membuktikan satu gray card awal cukup. [Remote Sensing 2024, 16(16), 3019](https://www.mdpi.com/2072-4292/16/16/3019).

## 4. Pipeline orthomosaic yang dievaluasi

Implementasi saat ini adalah akuisisi dan pengelolaan dataset, belum mesin orthomosaic. Kandidat eksternal: OpenDroneMap untuk pipeline terbuka/lokal dan Metashape untuk workflow komersial dengan kontrol kalibrasi. Pemilihan final harus menggunakan dataset yang sama, parameter tercatat, dan checkpoint independen. [Dokumentasi opsi ODM](https://docs.opendronemap.org/arguments/).

Rancangan evaluasi: audit checksum → ekstraksi metadata → pisahkan referensi dari foto mapping → QA blur/clipping/overlap → pengembangan DNG konsisten ke TIFF (jika RAW) → feature matching → bundle adjustment dengan model distorsi/rolling shutter yang sesuai → evaluasi checkpoint → dense reconstruction/DSM → orthorectification → seamline/blending → QC geometri dan warna.

Jangan memberikan dua versi RAW/JPEG dari exposure yang sama sebagai dua kamera independen. Jangan campurkan foto gray card dengan flight block. Jangan undistort dua kali. Jangan memakai histogram matching agresif untuk produk reflectance: warna cantik dan radiometri kuantitatif adalah sasaran berbeda. Untuk produk visual, koreksi gain/offset antar gambar dan blending perlu dibandingkan terhadap detail patch dan seam, tanpa menyembunyikan kesalahan geometri.

Metrik eksperimen yang diusulkan: capture interval p50/p95/p99, skipped slots, persen clipping, ketajaman patch, tie-point coverage, reprojection residual, RMSE XY/Z checkpoint dan bias, seam color discontinuity, serta ΔE pada patch independen bila profil warna diterapkan. Target numerik survei belum ditetapkan sebelum perangkat dan kebutuhan akurasi diketahui.

## 5. Komunikasi dan reliability

| Alternatif | Evaluasi | Keputusan |
|---|---|---|
| Multipeer Connectivity | Discovery, transport lokal, pesan/resource transfer, dukungan Apple-to-Apple | Dipakai tahap pertama dengan enkripsi wajib dan approval di iPhone |
| Network.framework + Bonjour/TLS | Kontrol protokol, autentikasi dan resume lebih rinci; lebih banyak implementasi | Kandidat jika pengujian MPC tidak memenuhi reliability/throughput |
| HTTP/WebSocket lokal | Mudah diinspeksi dan integrasi lintas platform | Perlu discovery, TLS/pairing, framing, retry tersendiri |
| Bluetooth sebagai jalur foto utama | Throughput foto resolusi penuh tidak menjadi asumsi yang aman | Bukan target throughput utama; gunakan Wi-Fi lokal |
| USB/Finder | Alternatif recovery dataset tanpa radio | File Sharing diaktifkan untuk ekspor manual |

MPC mendukung discovery lokal dan transfer resources; izin Local Network dan daftar Bonjour diperlukan. Tidak ada server/cloud. Enkripsi transport tidak membuktikan identitas manusia: approval nama peer adalah batas prototipe, bukan certificate pinning. Pairing identitas persisten/pinning perlu sebelum deployment di jaringan tidak tepercaya. [Apple Multipeer Connectivity](https://developer.apple.com/documentation/multipeerconnectivity).

Penjadwal memakai waktu monotonic lokal dan tidak bergantung heartbeat Mac. Satu capture in-flight membatasi memory dan antrean I/O; slot yang terlewat dihitung, tidak dikejar dengan burst. Ini mengutamakan integritas data daripada throughput maksimum. Benchmark diperlukan untuk menentukan interval minimum aman.

iOS mendokumentasikan interupsi kamera ketika aplikasi masuk background dan akibat system pressure. Mematikan idle timer hanya mencegah auto-lock selama misi; tidak mengatasi tombol lock, app termination, panggilan, atau thermal shutdown. Tidak ada penggunaan background task/audio palsu untuk mengakali batas tersebut. [Apple interruption reasons](https://developer.apple.com/documentation/avfoundation/avcapturesession/interruptionreason).

Setiap capture ditulis di direktori staging, kemudian dipublikasikan dengan rename setelah kedua hasil dan sidecar lengkap. Restart merekonsiliasi jumlah capture committed dan menandai misi interrupted, tanpa melanjutkan shutter otomatis. Atomic write/rename mengurangi partial dataset, tetapi tidak diklaim sebagai transaksi power-loss dengan fsync penuh. Transfer ulang tersedia pada tingkat berkas; byte-range resume dan whole-dataset commit marker belum ada.

## Mode panduan: implementasi exposure pra-terbang

Tim memasukkan tinggi AGL, kecepatan, target GSD, overlap dan durasi. Kamera dihitung memakai margin 0.8 terhadap interval maksimum dan batas blur, serta shutter paling lambat 1/1000 s pada kebijakan awal. Ini kebijakan rekayasa yang harus diuji, bukan angka optimal universal. Target jumlah foto = ceil(durasi/interval). Bila rencana tidak memenuhi batas kamera, konfigurasi ditolak dengan arahan operasional.

Saat gray card diposisikan menutupi sebagian besar frame (termasuk pusat), iPhone menggunakan continuous auto exposure dengan exposurePointOfInterest pusat dan bias 0 EV untuk pembacaan meter. Metering pusat bukan spot meter dengan ukuran ROI yang terjamin pada seluruh iPhone; kartu dan posisi yang salah dapat membias hasil. Pembacaan menunggu sedikitnya 3 sampel stabil (perubahan <0.05 EV, jarak 0.2 s) setelah jeda awal 0.6 s, timeout 6 s. Angka ini perlu benchmark perangkat. Tidak ada deteksi kartu otomatis. [Apple exposure point](https://developer.apple.com/documentation/avfoundation/avcapturedevice/exposurepointofinterest), [Apple exposure bias](https://developer.apple.com/documentation/avfoundation/avcapturedevice/exposuretargetbias), [Calibrite gray balance](https://calibrite.com/us/product/colorchecker-gray-balance/).

Produk ISO × durasi hasil metering dipertahankan saat mengubah kembali ke shutter berdasarkan gerak; aperture kamera fisik tetap. ISO dibatasi ke min(800, maksimum perangkat), sebagai batas mutu awal yang harus dievaluasi terhadap noise/ketajaman. Jika terlalu terang pada ISO minimum, shutter dipercepat; jika terlalu redup untuk shutter dan ceiling ISO, pengukuran ditolak. Setelah itu exposure, fokus dan WB dikunci, referensi asli disimpan beserta data metering dalam mission.json. Kegagalan metering mencoba mengembalikan pengaturan manual sebelumnya. Proses setelah perintah diterima tetap lokal saat Mac disconnect.

Pemeriksaan exposure memakai preview JPEG yang diperkecil: fraksi RGB gelap/jenuh dan brightness rata-rata. Foto hampir seluruhnya gelap/jenuh memblokir start; highlight parsial memunculkan arahan untuk pemeriksaan asli. Ini bukan pengukuran clipping RAW, reflectance absolut, validasi ketajaman atau deteksi kartu. Operator tetap memeriksa asli, cadence berulang dan kesiapan lapangan. Tidak ada ISO adaptif selama penerbangan atau normalisasi radiometrik otomatis.
