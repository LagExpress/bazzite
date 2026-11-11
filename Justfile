set shell := ["bash", "-euc"]

default:
    @just --list

# List output names and upstream Fedora 45 bases.
images:
    @jq -r '.images[] | "\(.name) <- \(.base)"' images.json

# Build one variant from images.json.
build variant="bazzite-kde":
    bash scripts/build-image.sh "{{variant}}"

# Check a locally built image.
verify variant="bazzite-kde":
    bash scripts/verify-image.sh "{{variant}}"

check:
    for script in build_files/*.sh scripts/*.sh; do bash -n "$script"; done
    shellcheck build_files/build.sh scripts/*.sh
    jq -e '.fedora == 45 and (.images | length == 11) and ([.images[].name] | length == (unique | length)) and all(.images[]; (.name | test("^[a-z0-9-]+$")) and (.base | test("^ghcr.io/ublue-os/[a-z0-9-]+:stable-45$")))' images.json
    jq -e 'keys == ["hex", "opencode"] and all(.[]; (.version | test("^[0-9]+[.][0-9]+[.][0-9]+$")) and (.release | test("^[0-9]+$")) and (.sha256 | test("^[0-9a-f]{64}$")) and (.url | startswith("https://")))' build_files/desktop-apps.json

# Print the same matrix used by Actions.
matrix:
    @jq -c '{include: .images}' images.json
