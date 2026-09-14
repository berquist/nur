# anilist-mal-sync — syncs anime/manga watch progress between AniList and
# MyAnimeList.
#
# Not a Python package and not in nixpkgs.  Here for ../../nixos-modules/anilist-mal-sync.nix,
# which runs it as a personal background sync service.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "anilist-mal-sync";
  version = "0.27.1";

  src = fetchFromGitHub {
    owner = "bigspawn";
    repo = "anilist-mal-sync";
    tag = "v${finalAttrs.version}";
    hash = "sha256-RufN0hMuhhkCQOt8OCfn97Rr8PhGtWU14QhfBIpAHsw=";
  };

  # The source carries a committed vendor/ (go.sum-consistent), so there is
  # nothing to fetch or regenerate.
  vendorHash = null;

  # Matches the Makefile's own LDFLAGS, whose $(VERSION) comes from
  # `git describe --tags` — i.e. "v0.27.1", not "0.27.1" — so `--version`
  # here reports the same string upstream's own build would.
  ldflags = [ "-X main.version=v${finalAttrs.version}" ];

  meta = {
    description = "Sync anime/manga watch progress between AniList and MyAnimeList";
    homepage = "https://github.com/bigspawn/anilist-mal-sync";
    changelog = "https://github.com/bigspawn/anilist-mal-sync/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "anilist-mal-sync";
    maintainers = with lib.maintainers; [ berquist ];
  };
})
