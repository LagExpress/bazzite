{ pkgs, ... }:
{
  languages.python.enable = true;
  packages = with pkgs; [
    git
    gh
    cosign
    podman
    skopeo
    jq
    just
    shellcheck
    shfmt
    actionlint
    curl
    rpm
    cpio
    gnupg
  ];
}
