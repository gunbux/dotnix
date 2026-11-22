# Daily refresh for Parl Digest at parl.chunyu.sh (github.com/gunbux/parl-digest).
#
# parliament.gov.sg serves an AWS WAF challenge to hosting-provider IPs, which
# includes both pinfra nodes, so the refresh runs here on a home connection.
# pinfra only serves the site (github.com/gunbux/pinfra, k8s/apps/parl-digest.yaml).
#
# The timer runs the published image's `ingest` against a local state folder,
# with the OpenRouter key from sops (modules/sops.nix). It then replaces
# /state/data in the pinfra pod with the result. A run with partial source
# failures exits 1 but its data is still safe to publish (it keeps last-good
# values), so the copy happens either way. A missed day is caught up next run.
{
  lib,
  pkgs,
  ...
}: let
  image = "ghcr.io/gunbux/parl-digest:latest";
  refresh = pkgs.writeShellApplication {
    name = "parl-digest-refresh";
    runtimeInputs = with pkgs; [docker kubectl openssh coreutils gnutar iproute2 gnugrep];
    text = ''
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/parl-digest"
      mkdir -p "$state"

      docker pull -q ${image} >/dev/null
      status=0
      docker run --rm --user "$(id -u):$(id -g)" \
        -e HOME=/state -e OPENROUTER_API_KEY="$(cat /run/secrets/openrouter_api_key)" \
        -v "$state:/state" ${image} ingest --sittings 3 || status=$?
      if [ "$status" -gt 1 ] || [ ! -f "$state/data/index.json" ]; then
        echo "ingest failed (exit $status); nothing published" >&2
        exit 1
      fi

      ss -ltn | grep -q ':16443 ' || ssh -o BatchMode=yes -fN -L 16443:127.0.0.1:6443 pani
      tar -C "$state/data" -cf - . | kubectl --context pinfra -n apps exec -i deploy/parl-digest -- sh -c '
        set -e
        rm -rf /state/data.new /state/data.old
        mkdir /state/data.new
        tar -xf - -C /state/data.new
        mv /state/data /state/data.old
        mv /state/data.new /state/data
        rm -rf /state/data.old'
      echo "published (ingest exit $status)"
      exit "$status"
    '';
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    home.packages = [refresh];

    systemd.user.services.parl-digest-refresh = {
      Unit.Description = "Refresh Parl Digest and publish it to pinfra";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe refresh;
        TimeoutStartSec = "2h";
      };
    };
    systemd.user.timers.parl-digest-refresh = {
      Unit.Description = "Refresh Parl Digest daily at 22:00 SGT";
      Timer = {
        OnCalendar = "*-*-* 22:00:00 Asia/Singapore";
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
      Install.WantedBy = ["timers.target"];
    };
  }
