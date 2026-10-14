# Pressure test workflow DroneControl

10 Oktober 2026. Pengujian logika dan UI demo; belum uji penerbangan fisik.

| Kondisi | Perilaku yang diverifikasi |
|---|---|
| Belum koneksi / status usang / ACK belum diterima | Start ditolak dan alasan ditampilkan |
| Target GSD, overlap atau blur tidak terpenuhi | Ubah tinggi, kecepatan, interval atau shutter terlebih dahulu |
| ISO/shutter di luar kemampuan, RAW tak didukung | Start ditolak |
| Setting berubah setelah kalibrasi/review | Review dan referensi lama dibatalkan |
| Interval berubah | Uji cadence perlu dikonfirmasi ulang |
| Gray card dipilih | Panduan meminta WB, referensi, kemudian foto uji |
| Foto uji tidak tersimpan / setting berbeda / terlalu lambat | Start ditolak; latency penyimpanan dibandingkan interval |
| Baterai/disk/suhu tidak layak | Start ditolak |
| Radio terputus saat misi | Controller tidak mengubah fase capture; iPhone tetap otoritatif |
| Reconnect | UUID/state misi dipertahankan; start tidak diputar ulang |
| Misi selesai | Menuju hasil dan persetujuan kualitas direset |

104 assertions core + 22 assertions controller + 2 tes auditor lulus. Controller memakai LocalLink nonaktif dan foto sintetis berlabel DEMO. UI native diperiksa dengan screenshot/accessibility. Build Mac dengan signing dan iOS generik berhasil.

Satu foto uji belum mengukur cadence jangka panjang. Review ketajaman/exposure merupakan pemeriksaan operator, bukan deteksi otomatis. Preview 1200 pixel tidak menggantikan inspeksi foto asli. Estimasi FOV belum membuktikan kalibrasi geometrik; gray card belum membuktikan profil warna/reflectance. Uji hardware pada DEVICE_TEST_PLAN.md tetap diperlukan.
