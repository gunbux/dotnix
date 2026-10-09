{
  writeShellScriptBin,
  paseo-desktop,
}:
# Runs config/vicinae/paseo/bridge/paseo-bridge.mjs on Paseo's bundled runtime so
# it reuses the installed CLI's daemon client. Used by the Vicinae Paseo extension
# and by glance's Paseo backend.
let
  resources = paseo-desktop.resources;
in
  writeShellScriptBin "paseo-bridge" ''
    exec env PASEO_RESOURCES=${resources} ELECTRON_RUN_AS_NODE=1 PASEO_NODE_ENV=production \
      ${paseo-desktop}/bin/paseo-desktop --disable-warning=DEP0040 \
      ${resources}/app.asar.unpacked/dist/daemon/node-entrypoint-runner.js \
      node-script ${../../config/vicinae/paseo/bridge/paseo-bridge.mjs} "$@"
  ''
