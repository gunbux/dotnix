# `remote-mode on|off|status`: swap Touch ID for passwords while away from the Mac.
#
# Touch ID for sudo lives in /etc/pam.d/sudo_touchid, which sudo_local includes.
# That file is plain (not a nix store symlink), so the toggle can rewrite it
# without a rebuild. The state is the flag file /var/db/remote-mode.
# The same switch also turns off system-wide biometrics (lock screen, auth dialogs).
{
  lib,
  pkgs,
  ...
}: let
  remote-mode = pkgs.writeShellApplication {
    name = "remote-mode";
    runtimeInputs = [pkgs.flock];
    text = ''
      flag=/var/db/remote-mode
      pamfile=/etc/pam.d/sudo_touchid
      reattach=${pkgs.pam-reattach}/lib/pam/pam_reattach.so

      status() {
        if [ -e "$flag" ]; then echo "remote mode: ON (passwords only)"; else echo "remote mode: OFF (Touch ID)"; fi
        /usr/bin/bioutil -r -s | grep -E "Biometrics (functionality|for unlock)" || true
      }

      case "''${1:-status}" in
        status) status; exit 0 ;;
        on | off | apply) ;;
        *) echo "usage: remote-mode on|off|status" >&2; exit 2 ;;
      esac

      if [ "$(id -u)" -ne 0 ]; then
        exec /usr/bin/sudo "$0" "$@"
      fi

      # One update at a time: a switch and a manual toggle must not interleave.
      # The kernel drops the flock when this process dies, so a crash leaves no stale lock.
      exec 9> /var/db/remote-mode.lock
      flock 9

      case "$1" in
        on) touch "$flag" ;;
        off) rm -f "$flag" ;;
      esac

      tmp=$(mktemp /etc/pam.d/.sudo_touchid.XXXXXX)
      if [ -e "$flag" ]; then
        echo "# remote mode: no Touch ID, sudo asks for the password" > "$tmp"
        echo "auth       optional       pam_permit.so" >> "$tmp"
        bio=0
      else
        echo "auth       optional       $reattach" > "$tmp"
        echo "auth       sufficient     pam_tid.so" >> "$tmp"
        bio=1
      fi
      chmod 644 "$tmp"
      mv "$tmp" "$pamfile"

      # `apply` runs on every switch; leave biometrics alone unless remote mode is on.
      # A failed write exits non-zero, except in `apply`, which must not fail a switch.
      rc=0
      if [ "$1" != apply ] || [ "$bio" = 0 ]; then
        /usr/bin/bioutil -w -s -f "$bio" -u "$bio" > /dev/null || rc=1
      fi

      status
      if [ "$rc" -ne 0 ]; then
        echo "error: bioutil failed. The sudo setting changed, system biometrics did not." >&2
        [ "$1" = apply ] || exit 1
      fi
    '';
  };
in {
  environment.systemPackages = [remote-mode];

  # sudo_local includes the toggled file. A missing include is ignored by macOS PAM.
  security.pam.services.sudo_local.text = "auth       include        sudo_touchid\n";

  # Re-apply the saved state after every switch. Do not pass `on` or `off` here.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    ${lib.getExe remote-mode} apply
  '';
}
