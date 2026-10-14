# Alur operator dan pressure test — 14 Oktober 2026

## Dasar riset

- [Apple HIG — Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback): feedback status membantu pengguna mengetahui keadaan operasi. Implementasi: petunjuk langkah berikutnya, status koneksi usang, dan status transfer aktual.
- [Apple HIG — Layout](https://developer.apple.com/design/human-interface-guidelines/layout): progressive disclosure untuk layout yang lebih mudah dipakai. Implementasi: parameter teknis dan daftar pemeriksaan lengkap tetap dapat dibuka; operator melihat satu langkah persiapan berikutnya, tanpa angka panjang dari blocker teknis.
- [QGroundControl Plan View](https://docs.qgroundcontrol.com/Stable_V4.3/en/qgc-user-guide/plan_view/plan_view.html) menjelaskan perencanaan tanpa kendaraan terhubung dan pengelolaan file/rencana. [Survey pattern](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/plan_view/pattern_survey.html) menggunakan polygon dan parameter survei. Implementasi Krops mempertahankan draft offline dan meminta operator menyamakan tinggi, kecepatan, serta overlap dengan rencana QGC. Impor polygon Krops belum menjadi upload jalur terbang.
- [QGC Fly Tools](https://docs.qgroundcontrol.com/master/en/qgc-user-guide/fly_view/fly_tools.html): checklist pra-terbang dan konfirmasi tindakan penerbangan berada pada QGC. Krops hanya memulai pengambilan kamera. Source QGC, arming, takeoff, landing dan MAVLink control tidak ditambahkan.
- [ODM Flying Tips](https://docs.opendronemap.org/flying/): overlap dan kompleksitas bangunan/vegetasi menentukan akuisisi, serta kalibrasi kamera tetap penting. Implementasi tidak menyimpulkan kesiapan dari satu foto preview atau tombol apply; kesiapan foto asli/cadence/mount/GCP tetap diperiksa operator.

Penentuan tahap Krops adalah keputusan desain dari rujukan tersebut, bukan urutan persis yang diwajibkan QGC/ODM. Default kamera dan estimasi FOV belum menggantikan kalibrasi atau uji akurasi lapangan.

## Flow yang diterapkan

1. Ringkasan → buat misi bernama, dapat dilakukan offline. Batas kebun opsional sebagai konteks peta.
2. Hubungkan DroneCam, tunggu status terbaru dan sinkronisasi draft. Jika iPhone sedang menjalankan misi, draft tetap menunggu dan monitoring memakai nama/target misi iPhone yang sebenarnya.
3. Periksa rencana penerbangan di QGC. Samakan tinggi/kecepatan/overlap pada Krops dan tandai rencana sudah diperiksa.
4. Siapkan kamera → posisikan kartu fisik dan ukur → singkirkan kartu → cari fokus dan foto uji. Petunjuk mengikuti ACK/referensi yang tersimpan, bukan hanya klik tombol.
5. Periksa asli, EXIF/ruang/interval serta checklist lapangan. Mulai pengambilan hanya aktif jika seluruh readiness sebelumnya terpenuhi. iPhone memverifikasi ID misi agar perintah mulai yang mengarah ke misi lama tidak diterapkan pada misi baru.
6. Saat capture, tampilkan progres misi iPhone. Disconnect memperlihatkan status terakhir beserta waktu penerimaan; navigasi dashboard tidak mengulang start. Kamera tetap otoritatif.
7. Selesai → Hasil untuk UUID misi yang sama → transfer → verifikasi → siapkan WebODM. Nol foto mapping tidak menawarkan ekspor orthomosaic. Status transfer tidak menyiratkan berkas sudah ada di Mac sebelum benar-benar ditransfer.

## Temuan dan perbaikan

| Temuan pressure test | Perbaikan |
|---|---|
| Tombol Lihat hasil hanya membuka semua data | Memilih UUID record yang diklik, dengan jalan kembali Semua hasil |
| Highlight hari ini/perlu tindakan tidak memfilter tujuan | Filter eksplisit hari ini, paused/failed, dan memiliki foto |
| Misi aktif tampil lagi di daftar terbaru | Recent list mengecualikan UUID aktif |
| Mac restart menampilkan plan default saat iPhone sedang capture | Memulihkan record.plan/survey otoritatif sekali per ID, tanpa start otomatis atau menimpa edit pada heartbeat berikutnya |
| Draft lokal berbeda dari misi iPhone yang sedang terbang | Kartu draft terpisah, monitoring memakai nama dan target dari record aktif; pause/resume/finish tetap menargetkan misi iPhone tanpa menghapus draft |
| Counter dataset tertinggal sampai daftar diperbarui | Telemetry menyegarkan saved/missed/phase untuk record aktif |
| Footer fokus mendahului gray card meski petunjuk utama meminta kartu | Petunjuk utama menentukan langkah; footer memakai status persiapan dan Lihat pemeriksaan |
| Pergantian halaman membawa pencarian/filter tersembunyi | Pencarian dibersihkan saat konteks berubah; sidebar Hasil mengembalikan semua; filter user menghapus pilihan record spesifik |
| Selesai bisa membuka hasil kosong dengan instruksi buat misi baru | Jika UUID hasil belum diterima, meminta sinkronisasi/Perbarui |
| Preview/readiness terlihat sukses tetapi operator belum menilai | Tahap review tetap wajib, tidak otomatis mengisi checklist |
| Tombol mulai tanpa mengikat misi iPhone | Command start menyertakan missionID; iOS menolak mismatch pada start, pause, resume dan finish |

## Bukti pengujian

- 90 assertions controller/hardware simulasi lulus, termasuk 27 tambahan terkait tahapan operator, restore plan, navigasi UUID/filter, active-versus-draft, heartbeat counts, serta disconnect tanpa start/pause otomatis. Tes core sebelumnya tidak diganti dengan tes UI.
- Build Debug macOS signed dan generic iOS unsigned berhasil.
- UI native mode demo diperiksa: create offline → connect demo → review rencana → siapkan otomatis → ukur kartu sintetis → test/fokus sintetis → manual checklist → Mulai pengambilan → monitoring 0/250 → Selesai → Hasil. Mode demo tidak berkomunikasi dengan iPhone dan tidak menyimpan dataset penerbangan asli. Perbaikan footer berasal dari ketidaksesuaian urutan yang benar-benar terlihat saat pemeriksaan UI.
- Transfer checksum dan ekspor JPEG telah diuji pada pekerjaan sebelumnya; sesi ini belum menguji transfer radio fisik atau rekonstruksi WebODM.
- Tetap perlu uji iPhone fisik: disconnect selama capture, reconnect, target ID stale, jumlah/hashes sumber-tujuan, endurance/thermal, serta dataset lapangan di WebODM. Tidak ada klaim berhasil menerbangkan drone atau menjamin orthomosaic.

Ulangi tes: Scripts/test-control-flow.sh. Kedua aplikasi perlu diperbarui bersama karena start/pause/resume/finish kini memerlukan ID misi yang cocok.
