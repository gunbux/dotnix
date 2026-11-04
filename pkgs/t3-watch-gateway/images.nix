{
  dockerTools,
  t3-ask-bridge,
  t3-headless,
  t3-watch-gateway,
  cloudflared,
  cacert,
  git,
  coreutils,
  bash,
}: let
  common = {
    # Docker Tools derives the immutable tag from the image derivation.
    tag = null;
    created = "1970-01-01T00:00:01Z";
    extraCommands = ''
      mkdir -p data tmp etc
      chmod 1777 tmp
      echo 'gateway:x:65532:65532:T3 watch gateway:/data:/bin/sh' > etc/passwd
      echo 'gateway:x:65532:' > etc/group
    '';
    fakeRootCommands = ''
      chown 65532:65532 data
    '';
    enableFakechroot = true;
  };
  environment = [
    "HOME=/data"
    "PATH=/bin"
    "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
    "NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
  ];
in {
  bridge = dockerTools.buildLayeredImage (common
    // {
      name = "ghcr.io/gunbux/t3-ask-bridge";
      contents = [t3-ask-bridge cacert coreutils bash];
      config = {
        User = "65532:65532";
        WorkingDir = "/data";
        Cmd = ["/bin/t3-ask-bridge"];
        Env =
          environment
          ++ [
            "T3_ASK_HOST=0.0.0.0"
            "T3_ASK_PORT=8789"
            "T3_ASK_T3_URL=http://127.0.0.1:3773"
            "T3_ASK_T3_TOKEN_FILE=/run/t3-bridge/t3-token"
            "T3_ASK_WATCH_TOKEN_FILE=/run/t3-bridge/watch-token"
            "T3_ASK_T3_MCP_TOKEN_FILE=/run/t3-bridge/t3-mcp-token"
            "T3_ASK_PEERS_FILE=/run/t3-bridge/peers.json"
          ];
        ExposedPorts."8789/tcp" = {};
      };
    });
  gateway = dockerTools.buildLayeredImage (common
    // {
      name = "ghcr.io/gunbux/t3-watch-gateway";
      contents = [t3-headless t3-watch-gateway cloudflared cacert git coreutils bash];
      config = {
        User = "65532:65532";
        WorkingDir = "/data";
        Cmd = ["/bin/t3-watch-gateway"];
        Env =
          environment
          ++ [
            "T3_BIN=/bin/t3"
            "T3_GATEWAY_BASE_DIR=/data/t3"
            "T3_GATEWAY_SECRETS_DIR=/data/bridge-secrets"
            "T3_GATEWAY_HOST=127.0.0.1"
            "T3_GATEWAY_PORT=3773"
            "T3CODE_CLOUDFLARED_PATH=${cloudflared}/bin/cloudflared"
          ];
      };
    });
}
