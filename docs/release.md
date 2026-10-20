# Releases

armsense has two kinds of version:

* the **product version** inside the images (for example `2.9.0-DEVELOPMENT`),
  which follows the upstream source snapshot the images were built from;
* the **repository tag** (`v0.1.0`, `v0.2.0`, ...), which versions the build
  tooling, branding and documentation in this repository.

## Cutting a release

1. Make sure `main` is green (the CI workflow lints the scripts and checks
   that the branding assets in `build/branding/` match the generator).
2. Add release notes in `docs/releases/<tag>.md` (optional; the workflow
   writes a generic note otherwise) and an entry in `CHANGELOG.md`.
3. Tag and push:

       git tag -a v0.1.0 -m "armsense v0.1.0"
       git push origin main v0.1.0

4. The **Release** workflow validates the tree, packages the build overlay
   (`armsense-build-overlay-<tag>.tar.gz`), the libvirt recipe
   (`armsense-libvirt-<tag>.tar.gz`, from `deploy/libvirt/`) and the logo
   files, and creates the GitHub release. Tags that start with `v0.` or contain a `-` are marked
   as pre-releases.
5. Build the images on the FreeBSD arm64 build VM (`SETUP.md`; for a release
   use `build/vm/clean-build.sh`), then attach them:

       buildvm/publish-release.sh v0.1.0      # needs `gh auth login`

## Why images are not built by GitHub Actions

Building needs a FreeBSD arm64 host with poudriere (world, kernel and 220+
packages; about an hour natively). GitHub-hosted runners are Linux or macOS;
running FreeBSD under emulation there is far too slow for the job limits.
`.github/workflows/build-images.yml` is a manual workflow for a self-hosted
runner on a prepared FreeBSD arm64 machine, for when such a runner exists.

## Package repository

Images are configured for the armsense package repositories at the URL in
`build/armsense.conf` (`PKG_REPO_SERVER`). During development that is the
build host; a public repository server (with signed packages) is a
prerequisite for a release that is meant to be updated in place.
