# Konfigurasi publish ke GitHub — edit sesuai kebutuhan.
# File ini di-import dengan & (bukan dot-source) agar nilai terbaca sebagai hashtable.

@{
    # Akun GitHub Anda
    GitHubUser = 'Memedsugianto'

    # Nama repo di https://github.com/Memedsugianto/<RepoName>
    RepoName = 'idx-stock-ml'

    # Pesan commit awal saat pertama kali push
    InitialCommitMessage = 'Initial commit: IDX Stock ML (Flutter + FastAPI)'

    # Branch default
    DefaultBranch = 'main'

    # Visibilitas: 'public' atau 'private'
    Visibility = 'public'

    # Deskripsi repo (opsional, dipakai saat `gh repo create`)
    Description = 'Flutter + FastAPI dashboard saham IDX/BEI dengan analisis fundamental, teknikal, dan ML.'
}
