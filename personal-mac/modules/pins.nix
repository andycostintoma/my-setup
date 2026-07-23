{
  microsoftEdge = {
    # ponytail: url is Microsoft's "latest" fwlink, not an immutable versioned
    # URL, so this hash drifts whenever they ship a new build. Bump both
    # fields together when darwin-rebuild reports a hash mismatch here.
    version = "150.0.4078.83";
    url = "https://go.microsoft.com/fwlink/?linkid=2093504";
    hash = "sha256-hG9jItFrI+6Noxv2FlG3aKr6Kep4iflYYiHhv8Opu2w=";
  };

  kumospace = {
    version = "6.1.0";
    url = "https://downloads.kumospace.com/production/macos/universal/latest/Kumospace.dmg";
    hash = "sha256-wOf4dabEIsJd5yHWXwlA/+lSrvz6ijVvZHLvswNZSas=";
  };
}
