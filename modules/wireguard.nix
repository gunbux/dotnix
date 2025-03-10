{
  config,
  pkgs,
  ...
}: {
  # networking.firewall.checkReversePath = false;
  # Enable Wireguard
  networking.wg-quick.interfaces = {
    # "wg0" is the network interface name. You can name the interface arbitrarily.
    wg0 = {
      # Disable autostart
      autostart = false;

      # Determines the IP address and subnet of the client's end of the tunnel interface.
      address = ["10.8.0.4/24"];
      dns = ["1.1.1.1" "8.8.8.8"];

      # Path to the private key file.
      #
      # Note: The private key can also be included inline via the privateKey option,
      # but this makes the private key world-readable; thus, using privateKeyFile is
      # recommended.
      privateKeyFile = "/root/wireguard-keys/private";

      peers = [
        # For a client configuration, one peer entry for the server will suffice.
        {
          # Public key of the server (not a file path).
          publicKey = "RKpaRg36yQwVeKQN0RQby/FBUV+6IePGwVXhQu4xMgA=";
          presharedKey = "I5MpVhABlUXsr5111IsAog7fDWXJ2AO0Go7MOqbRaLw=";

          # List of IPs assigned to this peer within the tunnel subnet. Used to configure routing.
          # For a server peer this should be the whole subnet.
          allowedIPs = ["0.0.0.0/0" "::/0"];

          # Set this to the server IP and port.
          endpoint = "vpn.chunyu.sh:51820";

          # Send keepalives every 25 seconds. Important to keep NAT tables alive.
          persistentKeepalive = 0;
        }
      ];
    };
  };
}
