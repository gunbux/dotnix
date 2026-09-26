{pkgs, ...}: {
  # Android container, used for apps without a Linux client (e.g. Libby).
  # The Android image is not managed by Nix; initialise it once with:
  #   sudo waydroid init -s GAPPS
  virtualisation.waydroid = {
    enable = true;
    # The default package (chosen because networking.nftables is off) sets up
    # networking with iptables-legacy, but the kernel no longer ships the
    # legacy ip_tables module. Use the nftables variant instead.
    package = pkgs.waydroid-nftables;
  };

  # Let the container reach the host's DHCP/DNS (dnsmasq) through the firewall.
  networking.firewall.trustedInterfaces = ["waydroid0"];

  environment.systemPackages = with pkgs; [
    waydroid-helper
  ];
}
