{
  lib,
  python3Packages,
  fetchFromGitHub,
  fetchPypi,
}: let
  # Upstream still imports mcp.server.fastmcp, which mcp 2.x removed, and caps
  # mcp<2. nixpkgs ships 2.x, so pin the last 1.x wheel here.
  mcp_1 = python3Packages.buildPythonPackage rec {
    pname = "mcp";
    version = "1.30.0";
    format = "wheel";

    src = fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-Zm7bUAlQPhBHydYDRqdW+UsmHwXMJiXyPUHHKP/EhNA=";
    };

    dependencies = with python3Packages;
      [
        anyio
        httpx
        httpx-sse
        jsonschema
        pydantic
        pydantic-settings
        pyjwt
        python-multipart
        sse-starlette
        starlette
        typing-extensions
        typing-inspection
        uvicorn
      ]
      ++ pyjwt.optional-dependencies.crypto;

    pythonImportsCheck = ["mcp.server.fastmcp"];
  };
in
  python3Packages.buildPythonApplication {
    pname = "garmin-mcp";
    version = "0.1.0-unstable-2026-10-20";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "Taxuspt";
      repo = "garmin_mcp";
      rev = "a2ca5fcac34524b83814fe2fcf3d479f8a75983f";
      hash = "sha256-+feBYmZs6S+xt0YfelHTUQqql2qXHBy9krvNHBajCsc=";
    };

    build-system = [python3Packages.hatchling];

    dependencies = with python3Packages; [
      fitparse
      garminconnect
      mcp_1
      python-dotenv
      requests
    ];

    # Upstream pins garminconnect==0.3.2; its open bump to 0.3.19 (Taxuspt/garmin_mcp#479)
    # needs no application change, and newer releases carry Garmin SSO fixes.
    pythonRelaxDeps = [
      "garminconnect"
      "python-dotenv"
      "requests"
    ];

    # The server only loads cached tokens (~/.garminconnect), so parallel agent
    # sessions never each start a rate-limited SSO login. Only the one-off
    # login tool reads credentials, from private files outside the repo.
    postFixup = ''
      wrapProgram $out/bin/garmin-mcp-auth --run '
        garmin_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/garmin"
        if [ -z "''${GARMIN_EMAIL-}" ] && [ -r "$garmin_dir/username" ]; then
          export GARMIN_EMAIL_FILE="''${GARMIN_EMAIL_FILE:-$garmin_dir/username}"
        fi
        if [ -z "''${GARMIN_PASSWORD-}" ] && [ -r "$garmin_dir/password" ]; then
          export GARMIN_PASSWORD_FILE="''${GARMIN_PASSWORD_FILE:-$garmin_dir/password}"
        fi
      '
    '';

    pythonImportsCheck = ["garmin_mcp"];

    meta = {
      description = "MCP server for Garmin Connect health and activity data";
      homepage = "https://github.com/Taxuspt/garmin_mcp";
      license = lib.licenses.mit;
      mainProgram = "garmin-mcp";
      platforms = lib.platforms.unix;
    };
  }
