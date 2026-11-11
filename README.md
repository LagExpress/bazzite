# LagExpress Bazzite 45

Eleven x86_64 bootc images: all ten upstream Bazzite variants plus KDE Bazzite DX
with NVIDIA Open. Every image installs **Brave Origin** (`brave-origin`) from
[Brave's official signed release RPM repository](https://brave.com/origin/linux/).
Every variant also includes [OpenCode Desktop](https://opencode.ai/product),
[Hex](https://anoma.ly/hex/), [Codex in ChatGPT Desktop](https://learn.chatgpt.com/docs/linux/linux-app), and
[Orca IDE](https://www.onorca.dev/) from their
official Linux releases. All applications automatically follow the latest vendor
releases during image builds.
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
devenv shell -- just update-apps
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
`45-YYYYMMDD-<commit>-run<number>` tags; `latest` deliberately stays on Fedora 45.
Signing-key validation runs before the expensive build. Published digests are
signed and verified using the repository public key.

GHCR package permissions are separate from repository permissions. If a package
name already exists from an older project, its Package settings → Manage Actions
access must grant `LagExpress/bazzite` Write access. Otherwise publishing fails
with `permission_denied: write_package`, even though the workflow requests
`packages: write`. An obsolete package can instead be deleted by its owner and
recreated by this workflow, which connects the new package to this repository.
See [GitHub's package access documentation](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility#ensuring-workflow-access-to-your-package).

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

## Applications and automatic updates

The workflow builds daily at **07:05 America/Argentina/Salta** (10:05 UTC), on
pushes to `main`, and by manual dispatch. At the start of each run,
`scripts/update-desktop-apps.py` resolves the latest official stable releases.
The resulting `desktop-app-releases` artifact is shared by all eleven jobs:
every variant uses the same versions, immutable URLs and SHA-256 checksums, even
if a vendor releases another update while the matrix is running. No manual
version-pin edits are needed for routine updates. Brave Origin independently
uses the latest package in its signed release RPM repository on each rebuild.

| Application | Release source | Installed launcher |
| --- | --- | --- |
| OpenCode Desktop | Official latest desktop RPM redirect | `opencode-desktop` |
| Hex | Official stable manifest and content-addressed RPM | `hex` |
| Codex desktop | OpenAI's signed ChatGPT RPM repository | `chatgpt` (choose Codex in the app) |
| Orca IDE | Latest stable `stablyai/orca` GitHub release RPM | `orca-ide` |

Codex and OpenCode's bundled CLI executables are also exposed as `codex` and
`opencode` when those commands are not already supplied by the base image, so
Orca can discover them. Sign in to the agents with your own account
after booting the image. OpenAI's Linux app is a preview; its documented Fedora
support currently lists Fedora 43 and 44. These images target Fedora 45 and
verify package installation and CLI loading in CI; graphical compatibility
still requires a target desktop test.

OpenAI repository metadata and its RPM are verified using the pinned public key
in `build_files/keys/chatgpt.asc` (fingerprint
`3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4`). Hex's manifest and GitHub's release
asset metadata supply artifact checksums. OpenCode's latest download resolves
to an immutable version URL, whose checksum is captured once per run. Every
download must match the shared snapshot before installation. OpenCode, Hex and
Orca RPMs are unsigned; only local RPM signature checking for the mixed install
is disabled, while OpenAI's signature is checked explicitly and repository
dependency GPG checks remain enabled.

OpenCode and Orca's `/opt` payloads are relocated under `/usr/lib/opt`, with
tmpfiles rules restoring their expected paths at boot. Hex and ChatGPT install
directly under `/usr`. Hex's user service is installed and can be enabled through the app;
its speech model downloads on first use. Accounts, API credentials, microphone
grants and speech models are user state rather than image contents.

Application upgrades are delivered through normal Bazzite system updates and a
reboot. The installed release snapshot remains available at
`/usr/share/lagexpress/desktop-apps.json`; its SHA-256 is also an OCI image label.
The checked-in `build_files/desktop-apps.json` is a reproducible baseline.
`just update-apps` refreshes it locally, and `just build` does this automatically.
CI resolves a fresh snapshot by default; a manual workflow run can explicitly
disable `update_apps` to reproduce the checked-in versions. Vendor signing-key
rotations require reviewing and updating the trusted public key.

The image verifier checks Fedora 45, installed RPM versions, executable payloads,
restored launcher paths, Hex and coding-agent version commands, desktop entries,
the user service and signature policy. Hardware boot, graphical
browser operation and NVIDIA behavior still require checks on the target machine.

## Disk images

ISO/disk workflows are disabled. The template workflow is preserved outside
GitHub's active workflow directory at `.github/workflows-disabled/build-disk.yml`.
The old template documentation is preserved in [docs/IMAGE_TEMPLATE.md](docs/IMAGE_TEMPLATE.md)
for reference; its single-image setup and ISO instructions do not describe this fork.
