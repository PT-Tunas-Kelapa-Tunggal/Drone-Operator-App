# Dashboard Krops — 14 Oktober 2026

Dashboard Mac memakai sidebar berlabel, tiga highlight ringkas, daftar misi dan status perangkat di kiri, serta peta satelit MapKit di kanan. Misi dan Hasil memakai tema yang sama. Pengaturan umum (tema, lokasi dataset, aplikasi QGroundControl) ada di kiri bawah; parameter pengambilan, kamera dan kalibrasi tetap berada pada Misi. Tema awal Mac terang sesuai desain; dapat memilih gelap atau mengikuti sistem. Tampilan iOS tetap gelap.

## Data dan batas fungsi

- Ringkasan berasal dari draft/misi lokal dan daftar misi iPhone yang telah diterima. Highlight Perlu tindakan menghitung draft + record paused/failed; Misi dibuat hari ini menghitung waktu pembuatan, bukan jadwal terbang; Hasil tersedia menghitung record yang mempunyai foto mapping. Angka ilustratif permintaan/jadwal pada mockup tidak dijadikan data produksi.
- Pencarian memfilter nama/UUID misi pada Ringkasan dan Hasil.
- Permintaan petani menampilkan empty state; backend permintaan belum diintegrasikan. Cuaca belum diintegrasikan. Drone ditandai dikelola di QGC; belum menerima telemetry MAVLink.
- Buka QGroundControl menjalankan aplikasi yang dipasang di Mac, dengan pemilihan lokasi .app jika perlu. Source QGC tidak diubah dan dashboard tidak mengirim perintah penerbangan.
- Impor batas menggunakan GeoJSON Polygon/MultiPolygon, koordinat longitude/latitude. Nama berasal dari properties.name atau nama file. Polygon dengan interior ring ditolak agar area pengecualian tidak salah ditampilkan. Batas tersimpan atomik di Application Support/DroneControl/farm-areas.json. Memilih marker menampilkan kartu area dan tindakan membuat draft misi bernama area itu. Batas tersebut hanya konteks peta, belum menjadi jalur terbang autopilot.
- Citra satelit memerlukan jaringan; alur camera capture/transfer lokal tetap memakai koneksi offline yang sudah ada. Tampilan lokasi awal Bintan adalah posisi peta, bukan klaim lokasi pengguna atau kebun yang telah terdaftar.

## Validasi

Build Debug macOS dengan signing berhasil. 63 assertions controller simulasi lolos. Empat pemeriksaan GeoJSON meliputi impor nama, urutan longitude/latitude, persistence ID, serta kegagalan input tanpa menghapus batas sebelumnya. UI native demo diperiksa melalui screenshot dan accessibility: Ringkasan dengan status kosong nyata, misi dibuat saat offline menuju Misi, panel persiapan tetap tersedia, dan Pengaturan berfungsi. Demo tidak menjalankan discovery/perintah iPhone. Pemeriksaan ini tidak menguji drone atau penerbangan fisik.

Ulangi pemeriksaan dengan Scripts/test-dashboard.sh dan Scripts/test-control-flow.sh. Test dashboard perlu compiler SwiftUI Xcode yang dapat mengakses layanan compiler di Mac.
