{ pkgs, ... }:
{
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
  ];
}
