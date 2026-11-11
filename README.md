# LagExpress Bazzite 45

Eleven x86_64 bootc images: all ten upstream Bazzite variants plus KDE Bazzite DX
with NVIDIA Open. Every image installs **Brave Origin** (`brave-origin`) from
[Brave's official signed release RPM repository](https://brave.com/origin/linux/).
Upstream drivers, desktop environments, gaming tools and DX tooling are inherited.

## Images

Images publish under `ghcr.io/lagexpress/`. All bases use `stable-45`, and the
container build rejects any Fedora release other than 45.

| Fork image | Upstream image | Desktop / graphics |
| --- | --- | --- |
| `bazzite-kde` | `bazzite` | KDE, AMD/Intel |
| `bazzite-gnome` | `bazzite-gnome` | GNOME, AMD/Intel |
| `bazzite-kde-nvidia` | `bazzite-nvidia` | KDE, NVIDIA proprietary/LTS |
| `bazzite-gnome-nvidia` | `bazzite-gnome-nvidia` | GNOME, NVIDIA proprietary/LTS |
| `bazzite-kde-nvidia-open` | `bazzite-nvidia-open` | KDE, NVIDIA Open |
| `bazzite-gnome-nvidia-open` | `bazzite-gnome-nvidia-open` | GNOME, NVIDIA Open |
| `bazzite-deck-kde` | `bazzite-deck` | KDE, game mode, AMD/Intel |
| `bazzite-deck-gnome` | `bazzite-deck-gnome` | GNOME, game mode, AMD/Intel |
| `bazzite-deck-kde-nvidia-open` | `bazzite-deck-nvidia` | KDE, game mode, NVIDIA Open |
| `bazzite-deck-gnome-nvidia-open` | `bazzite-deck-nvidia-gnome` | GNOME, game mode, NVIDIA Open |
| `bazzite-dx-nvidia-open` | `bazzite-dx-nvidia` | KDE, developer tools, NVIDIA Open |

The authoritative mapping is [images.json](images.json), shared by local builds
and GitHub Actions. Upstream calls the KDE edition simply `bazzite`; upstream's
Deck NVIDIA and DX NVIDIA names omit `open` even though they include the open driver.
See [upstream's image table](https://github.com/ublue-os/bazzite/blob/main/build.py)
and [DX's build matrix](https://github.com/ublue-os/bazzite-dx/blob/main/.github/workflows/build.yml).
All eleven `stable-45` manifests were checked on 2026-11-11; the metadata snapshot
is in [docs/upstream-bases-2026-11-11.json](docs/upstream-bases-2026-11-11.json).

## Development on NixOS

Tools are declared in `devenv.nix`, with inputs pinned by `devenv.lock`.

```bash
devenv shell -- just images
devenv shell -- just check
devenv shell -- actionlint
devenv shell -- just build bazzite-kde-nvidia-open
devenv shell -- just verify bazzite-kde-nvidia-open
```

Local builds produce `localhost/<variant>:45` in Podman. They require substantial
disk space for the upstream image, extracted layers and the build. Only build one
variant at a time on a small disk. The upstream base's layers are reused without
flattening or copying the entire OS into a new layer.

## Signing and publishing

The private signing key lives outside this repository:

`/home/mateo/Documents/dev/secrets/bazzite/cosign.key`

The secrets directory includes private setup, backup and rotation instructions.
Only `cosign.pub` belongs in Git. No extra GHCR token is needed: Actions uses its
short lived `GITHUB_TOKEN` with `packages: write`. The `.containerignore` allows
only the build context files and public key into container builds.

```bash
# Confirm the local private key matches the committed public key.
devenv shell -- bash scripts/signing-key.sh check

# Upload the key as the repository Actions secret SIGNING_SECRET.
devenv shell -- bash scripts/signing-key.sh upload
```

`BAZZITE_SECRETS_DIR` can override the local key directory. Do not regenerate
keys as routine setup; existing installations trust the current public key.

The container workflow runs on pushes to `main`, daily, and by manual dispatch.
Pull requests build and verify without publishing or reading signing secrets.
Every published image gets `45`, `stable-45`, `latest`, and
`45-YYYYMMDD-<commit>` tags; `latest` deliberately stays on Fedora 45.
Signing-key validation runs before the expensive build. Published digests are
signed and verified using the repository public key.

After reviewing and committing the setup changes:

```bash
git push origin main
gh run list --repo LagExpress/bazzite --workflow build.yml --limit 5
```

For unauthenticated installation, set the published GHCR packages' visibility to
public in GitHub's package settings. Verify a published image with:

```bash
devenv shell -- cosign verify --key cosign.pub ghcr.io/lagexpress/bazzite-kde-nvidia-open:45
```

Each image includes the public key and containers signature policies for all
eleven fork images, preserving upstream policies. These can enforce signature
verification when using tools that honor containers/image policy.

## Brave Origin packaging

`build_files/build.sh` installs the RPM through DNF5 with signature checks enabled.
It temporarily replaces a symlinked `/opt` with a real directory during the RPM
transaction, then restores the original symlink without changing its existing target.
The payload is moved from `/opt/brave.com/brave-origin` to
`/usr/lib/opt/brave.com/brave-origin`; a tmpfiles rule recreates the expected link
at boot. This keeps Brave available after bootc deployments, where `/var` content
from an image does not act as an immutable application payload. The RPM package
remains registered; updates arrive in rebuilt OS images.

The image verifier checks Fedora 45, the installed RPM, the executable payload,
the restored launcher path and the signature policy. Hardware boot, graphical
browser operation and NVIDIA behavior still require checks on the target machine.

## Disk images

ISO/disk workflows are disabled. The template workflow is preserved outside
GitHub's active workflow directory at `.github/workflows-disabled/build-disk.yml`.
The old template documentation is preserved in [docs/IMAGE_TEMPLATE.md](docs/IMAGE_TEMPLATE.md)
for reference; its single-image setup and ISO instructions do not describe this fork.
