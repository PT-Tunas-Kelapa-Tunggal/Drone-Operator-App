# Setup developer dan kolaborasi GitHub

Source aplikasi, worker Python, script, dan lock dependensi ada di GitHub. Runtime
native, sertifikat, cache build, dan dataset besar disiapkan di komputer masing-masing.
Clone repository saja belum cukup untuk build aplikasi Mac: paket engine harus dibuat
terlebih dahulu. Tidak ada backend atau akun layanan tambahan untuk capture/transfer lokal.

## Prasyarat

- Mac Apple Silicon (arm64), macOS 14 atau lebih baru. Runtime aplikasi Mac saat ini
  tidak mendukung Intel/Windows/Linux walaupun upstream OpenSfM punya platform lain.
- Xcode 27, versi yang dipakai proyek ini, beserta platform iOS untuk build DroneCam.
  Buka Xcode sekali untuk menyelesaikan pemasangan komponen dan perjanjian lisensi.
  Script memakai `/Applications/Xcode.app`; untuk lokasi lain set `DEVELOPER_DIR`.
- Git dan Miniforge/conda atau micromamba yang tersedia di `PATH`.
  Pemasang resmi: [Miniforge](https://github.com/conda-forge/miniforge).
- Akun Apple Developer dengan sertifikat Apple Development di Keychain. Masuk lewat
  Xcode → Settings → Accounts dan buat development certificate bila belum tersedia.
- Internet saat setup awal dan ruang kosong beberapa GB untuk environment, kompilasi,
  salinan runtime, serta hasil build. iPhone fisik diperlukan untuk uji kamera sebenarnya.

## Clone dan signing pribadi

Pemilik repository mengundang akun GitHub teman melalui Settings → Collaborators.
Setelah undangan diterima:

```sh
git clone --branch dev https://github.com/hatamisg/Control-Mapping.git
cd Control-Mapping
cp Config/Developer.local.xcconfig.example Config/Developer.local.xcconfig
```

Edit `Config/Developer.local.xcconfig`:

```xcconfig
DRONE_DEVELOPMENT_TEAM = ABCDE12345
DRONE_BUNDLE_PREFIX = com.namakamu.krops
```

Ganti contoh Team ID dengan Team ID akun Apple milikmu dan gunakan prefix bundle
pribadi yang unik. Kedua target, Debug dan Release, membaca file ini. File lokal
diabaikan Git; tidak perlu mengedit signing di `project.pbxproj`. Tanpa file lokal,
Team ID kosong sehingga akun pemilik repository tidak terpakai otomatis.

Nama helper internal `com.hata.ControlDroneMapping.engine.python` tetap: itu kontrak
validasi runtime, bukan Bundle ID aplikasi yang perlu didaftarkan ulang.

## Bangun engine sekali di komputer masing-masing

Dari root repository, pilih folder absolut tanpa spasi. Gunakan folder permanen:
environment conda pengembangan tidak boleh dipindahkan atau disalin ke Mac lain.

```sh
bash Scripts/setup-orthomosaic-engine.sh "$HOME/Developer/OrthomosaicEngine-v1"
```

Script otomatis mengambil commit OpenSfM di `Config/Engine/opensfm-commit.txt`,
submodule pada commit tersebut, dan dependensi di `Config/Engine/`:

- `conda-osx-arm64.lock`: URL dan checksum artifact native, termasuk Python 3.10,
  OpenCV, Ceres, compiler tools, dan SciPy conda-forge 1.15.2.
- `requirements-runtime.lock`: versi dan SHA-256 wheel library Python tambahan,
  termasuk rasterio dan Pillow, beserta dependensinya.
- `requirements-build.lock`: versi dan SHA-256 alat build Python. OpenSfM dibangun
  tanpa dependency resolver dan tanpa build isolation yang mengunduh versi terbaru.

Snapshot dependensi runtime diambil dari engine lokal yang sudah digunakan. Alat
build Python dikunci terpisah; keberhasilan rebuild penuh di Mac lain tetap perlu
dibuktikan dengan langkah pemeriksaan di bawah, termasuk dukungan GPU/OpenCL.
Penguncian paket tidak menjamin binary identik antar versi Xcode/macOS.

Script bisa diulang untuk melanjutkan pemasangan yang terputus dengan resep yang
sama. Script menolak environment lama tanpa marker resep, lock yang berubah,
source dengan commit berbeda, atau perubahan source tracked. Pilih folder baru
untuk kasus tersebut; script tidak menghapus runtime lama atau perubahan lokal.

## Kemas engine menggunakan identitas Apple sendiri

Lihat identitas signing:

```sh
security find-identity -v -p codesigning
```

Salin nama lengkap sertifikat Apple Development yang berasal dari Team yang
sama dengan `DRONE_DEVELOPMENT_TEAM`, lalu jalankan dari root repository:

```sh
python3 Scripts/package-orthomosaic-engine.py \
  --runtime "$HOME/Developer/OrthomosaicEngine-v1" \
  --identity "Apple Development: NAMA DI KEYCHAIN (IDENTIFIER)"
```

Identitas di atas hanya contoh, harus diganti. Script menghasilkan:

```text
.build/OrthomosaicEngine/
.build/OrthomosaicPython
.build/engine-package/orthomosaic-engine.zip
.build/engine-package/orthomosaic-engine.json
ControlDroneMapping/Resources/orthomosaic-engine.json
```

Semua hasil ini diabaikan Git. Xcode mengambil folder engine, helper dan manifest
untuk disertakan dalam aplikasi. Aplikasi sandbox tidak menjalankan environment
eksternal secara langsung. Engine bertanda tangan pemilik repo tidak dapat langsung
dipakai dengan aplikasi bertanda tangan Team lain; membangun dan mengemas engine
sendiri menghindari kebutuhan berbagi private key.

## Build, jalankan, dan periksa

1. Buka `DroneMapping.xcodeproj` di Xcode.
2. Pilih scheme **ControlDroneMapping**, destination **My Mac**, lalu Build & Run.
3. Di **Hasil → Olah foto**, pemeriksaan harus menampilkan **Engine lokal siap**.
   Uji impor dan proses dataset contoh untuk memastikan pipeline pada perangkatmu.
4. Untuk DroneCam, pilih scheme **DroneMapping** dan iPhone fisik. Aktifkan Developer
   Mode bila diminta dan izinkan Kamera, Local Network serta lokasi bila diperlukan.
5. Hubungkan kedua aplikasi mengikuti README. Build dengan akunmu sendiri dapat
   berjalan sebagai pasangan pengembangan tersendiri.

Pemeriksaan otomatis dari root repo:

```sh
python3 Scripts/test-development-setup.py
bash Scripts/test-core.sh
```

Sesudah build Mac, engine juga bisa diperiksa melalui executable hasil build:

```sh
/path/ke/ControlDroneMapping.app/Contents/MacOS/ControlDroneMapping --check-orthomosaic-engine
```

Jalankan executable aplikasi, bukan `OrthomosaicPython` langsung, agar pewarisan
sandbox ikut diuji. Detail pipeline dan troubleshooting ada di
[panduan engine](../ControlDroneMapping/Resources/ORTHOMOSAIC_ENGINE.md).

## Workflow bersama dan file besar

Mulai perubahan dari `dev`, buat branch fitur, lalu kirim pull request ke `dev`:

```sh
git switch dev
git pull --ff-only origin dev
git switch -c codex/nama-fitur
# Edit, periksa, lalu commit perubahan.
git push -u origin codex/nama-fitur
```

Jangan commit `Developer.local.xcconfig`, sertifikat/private key, `.build`, runtime
conda, atau dataset misi. Bagikan dataset contoh secara terpisah dengan izin akses
yang sesuai. GitHub Releases dapat menyimpan paket engine dan checksum secara
terpisah dari riwayat source, tetapi download aset Release tidak otomatis dijalankan
saat `git clone`. Paket runtime distribusi berbeda dari environment pengembangan;
jangan menjalankan conda/pip di dalam paket distribusi.

Untuk memperbarui engine, ubah commit dan lock sebagai satu perubahan yang ditinjau,
bangun di prefix baru, kemas ulang, dan uji aplikasi bertanda tangan serta dataset
contoh sebelum dipakai tim. Jangan mengubah lock hanya agar solver memilih paket
terbaru; pertahankan sumber snapshot dan hasil validasinya.
