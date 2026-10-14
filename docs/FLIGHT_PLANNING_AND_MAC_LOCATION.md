# Kebun sekitar, waypoint manual, dan lokasi Mac

Implementasi 14 Oktober 2026.

## Alur operator

1. Dashboard memakai peta untuk melihat **kebun yang sudah disimpan/import**, bukan untuk menambah waypoint dengan klik yang tidak disengaja. Gunakan impor GeoJSON untuk menambahkan batas kebun.
2. Pilih **Lokasi saya**. Aplikasi meminta lokasi saat aksi tersebut, bukan saat startup. Setelah layanan macOS memberikan lokasi, peta menampilkan penanda perkiraan dan radius akurasi. Filter 5/10/25 km memakai jarak ke perkiraan pusat kebun; **Semua** menampilkan seluruh kebun tersimpan. Fitur ini belum mengambil kebun dari backend eksternal.
3. Pilih kebun lalu **Rencanakan waypoint**, atau gunakan **Rute waypoint** pada toolbar. Editor terbuka sebagai sheet terpisah. Tidak memerlukan iPhone.
4. Tentukan nama dan profil multicopter sesuai QGC, titik **Home** pada lokasi lepas landas drone, elevasi home **AMSL**, tinggi waypoint relatif home, dan kecepatan. Home dan elevasinya tidak diambil otomatis dari lokasi operator.
5. Mode **+ Waypoint** menambah titik dengan klik peta. Mode **Pilih** memungkinkan pemilihan/drag waypoint. Daftar titik mendukung pindah urutan, tinggi per titik, hapus dan undo. Koordinat manual tersedia tanpa citra peta, dengan titik desimal yang konsisten (`1.05`, `104.45`).
6. Periksa home, rute, tinggi, dan profil drone, lalu tandai checklist. **Ekspor .plan** menampilkan dialog simpan native. Draft rute otomatis disimpan secara atomik di Application Support; perubahan membatalkan review dan status file ekspor sebelumnya.
7. Setelah ekspor, gunakan **Lihat file** dan **Buka QGroundControl**. Di QGC gunakan **Plan → Open** untuk memuat file, periksa keseluruhan misi, lalu tentukan upload melalui QGC. Membuka QGC tidak berarti file otomatis diimpor. Aplikasi tidak mengirim MAVLink, upload misi, atau perintah arm/takeoff.

Halaman **Misi** tetap digunakan untuk persiapan dan pengambilan foto iPhone. Rute penerbangan dan misi akuisisi kamera mempunyai siklus hidup berbeda; tinggi relatif home bukan bukti tinggi AGL yang sama, terutama pada medan tidak rata. Takeoff/RTL mengikuti profil dan konfigurasi autopilot yang harus diperiksa di QGC. Waypoint manual belum membuktikan cakupan/overlap survei atau kelayakan rute terhadap terrain/hambatan.

## Batas lokasi dan offline

Core Location menentukan lokasi dari sumber yang tersedia pada Mac; tidak dilabeli sebagai GPS survei atau posisi drone. Akurasi, status izin, layanan nonaktif, kegagalan lokasi, dan sample usang ditampilkan. Query lokasi bersifat satu kali dengan batas waktu pengambilan 15 detik setelah permintaan lokasi dimulai. Sample berumur lebih dari 120 detik tidak dipakai sebagai lokasi aktif. Timer UI memperbarui status kedaluwarsa tanpa memulai tracking background.

Lokasi operator disimpan di memori dan tidak ditanamkan otomatis ke file plan atau metadata foto. Izin lokasi menggunakan `NSLocationUsageDescription`/`NSLocationWhenInUseUsageDescription` pada target Mac serta entitlement lokasi App Sandbox. Simpan file `.plan` menggunakan akses berkas yang dipilih pengguna. Konfigurasi Info.plist Mac dipisahkan dari iOS; permission dan capture iPhone tidak diubah.

Draft dan ekspor tidak memerlukan internet. Memuat citra satelit baru dan menentukan lokasi Mac dapat bergantung pada layanan/jaringan macOS. Bila lokasi tidak tersedia, semua kebun tersimpan tetap bisa diakses; koordinat manual tetap tersedia untuk rute. Putus koneksi Mac–iPhone tetap tidak menghentikan timer capture iPhone.

## Format dan komponen

File hasil: QGC Plan version 1, mission version 2, multicopter `vehicleType=2`, profil ArduPilot (`firmwareType=3`) atau PX4 (`12`) yang dipilih secara eksplisit. Item berurutan: takeoff, perubahan groundspeed, waypoint, serta RTL bila diaktifkan. NAV memakai `MAV_FRAME_GLOBAL_RELATIVE_ALT=3`. Parameter yaw yang tidak ditentukan disimpan sebagai JSON null. Field UI altitude opsional dihilangkan agar loader QGC mengambil altitude frame dari MAVLink frame. Tidak ada camera-trigger, geofence kebun, atau rally point otomatis.

- Domain: `FlightRoute`, `MapCoordinate`, `FlightWaypoint`, `FlightFirmware`, `FlightRouteRepository`, `OperatorLocationSample`, `OperatorLocationProviding`.
- Data: `FileFlightRouteRepository`, `QGCPlanExporter`, `MacLocationService`.
- Presentation: `FlightPlannerViewModel`, `FlightPlannerView`, `WaypointMap`, `OperatorLocationViewModel`, serta filter pada `FarmAreaViewModel`.
- Composition: `ControlDependencies` membuat layanan/repository dan memasoknya pada aplikasi.

Draft berada pada `Application Support/DroneControl/flight-routes.json`, di dalam container aplikasi saat App Sandbox aktif. Tidak memakai file `mission-draft.json` yang merupakan draft akuisisi iPhone. Error save/read ditampilkan; JSON yang gagal di-encode tidak menimpa file sebelumnya. Koordinat invalid tetap terlihat pada editor, dihindari oleh renderer peta, dan ditolak untuk ekspor.

## Verifikasi dan sumber

`Scripts/test-flight-planner.sh` menguji rute offline, persistence/identity, urutan/undo, review invalidation, schema/parameter JSON, elevasi home, profil firmware, data invalid, format desimal, lokasi stale/denied/expiry, serta radius kebun. Tes tidak melakukan upload atau penerbangan. QGC tidak ditemukan di lokasi instalasi standar pada Mac pengujian; import runtime QGC dan penerbangan fisik masih perlu diverifikasi.

- [QGC Plan File Format](https://docs.qgroundcontrol.com/master/en/qgc-dev-guide/file_formats/plan.html)
- [QGC SimpleMissionItem loader — v5.0.8](https://github.com/mavlink/qgroundcontrol/blob/v5.0.8/src/MissionManager/SimpleMissionItem.cc)
- [QGC Plan View](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/plan_view/plan_view.html)
- [QGC Command Line Options](https://docs.qgroundcontrol.com/master/en/qgc-dev-guide/command_line_options.html)
- [Apple: Configuring location services](https://developer.apple.com/documentation/corelocation/configuring-your-app-to-use-location-services)
- [Apple: Location Services & Privacy](https://www.apple.com/legal/privacy/data/en/location-services/)
- [Apple: Location entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.location)
