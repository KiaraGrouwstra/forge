{
  forge-lib,
  config,
  lib,
  pkgs,
  ...
}:
let
  app = config.apps.cryptpad;
  webEndpoint = app.services.components.cryptpad.endpoints.web;
  sandboxEndpoint = app.services.resources.sandbox-proxy.endpoints.sandbox;
  webPort = toString webEndpoint.forwardedPort;
  sandboxPort = toString sandboxEndpoint.forwardedPort;
  stateDir = "/var/lib/cryptpad";

  # The CryptPad configuration file is a JavaScript file that exports a JSON value.
  # The NixOS module `services.cryptpad` makes a similar file. Most of these values are its defaults.
  configFile = pkgs.writeText "cryptpad-config.js" ''
    module.exports = ${
      builtins.toJSON {
        # The origins must be the URLs that the web browser uses.
        httpUnsafeOrigin = "http://localhost:${webPort}";
        httpSafeOrigin = "http://localhost:${sandboxPort}";
        # Listen on all addresses, so that forwarded ports and other containers can reach the service.
        httpAddress = "0.0.0.0";
        httpPort = webEndpoint.port;
        websocketPort = 3003;
        logToStdout = true;
        logLevel = "info";
        # Disable telemetry.
        blockDailyCheck = true;
      }
    }
  '';
in
{
  apps.cryptpad = {
    displayName = "CryptPad";
    description = "End-to-end encrypted collaboration suite with documents, spreadsheets, forms and a drive.";
    categories = with forge-lib.categories; [ Office ];
    usage = ''
      CryptPad is a collaboration suite. All documents are encrypted in the web browser before they go to the server.

      It runs as a web service. The web interface is available on [http://localhost:${webPort}](http://localhost:${webPort}).
      You can use CryptPad without an account, or you can register a new account in the web interface.
      The log of the `cryptpad` service component shows an installation link (`journalctl -u cryptpad` in the NixOS runtime). Use this link to make the first administrator account.

      CryptPad uses a second origin as a sandbox: `http://localhost:${sandboxPort}`. The web interface must be able to reach it.

      This configuration is for evaluation only. Before you use CryptPad in production, configure TLS and two different domain names.
    '';

    icon = ./icon.svg;

    links = {
      website = "https://cryptpad.org";
      source = "https://github.com/cryptpad/cryptpad";
      docs = "https://docs.cryptpad.org";
    };

    ngi.grants = {
      Commons = [
        "CryptPad-Notes"
        "Cryptpad-scaling"
      ];
      Entrust = [ "CryptPad-Blueprints" ];
      Review = [
        "Cryptpad"
        "CryptPad-Auth"
        "Cryptpad-Communities"
        "Cryptpad-Directory"
        "CryptPadForms"
        "CryptPad-QA"
        "CryptPad-WCAG"
      ];
    };

    services = {
      components.cryptpad = {
        process = {
          # The `cryptpad` executable makes links to the source directories in the working directory.
          # It also makes the `customize` directory there. The working directory is `stateDir`.
          command = pkgs.cryptpad;
          environment = {
            CRYPTPAD_CONFIG = "${configFile}";
            HOME = stateDir;
          };
          inherit stateDir;
        };
        endpoints.web.port = 3000;
        healthcheck = {
          enable = true;
          test = [
            "curl"
            "-fs"
            "http://localhost:${toString webEndpoint.port}/api/config"
          ];
          packages = [ pkgs.curl ];
          interval = "3s";
          timeout = "3s";
          startPeriod = "5s";
          retries = 60;
        };
      };

      # CryptPad does not listen on a sandbox port when `httpSafeOrigin` is set.
      # Nginx sends the requests for the sandbox origin to the CryptPad server.
      resources.sandbox-proxy = {
        role = "frontend";
        endpoints.sandbox.port = 3001;
        nixosConfig = {
          services.nginx = {
            enable = true;
            virtualHosts.cryptpad-sandbox = {
              listen = [
                {
                  addr = "0.0.0.0";
                  port = sandboxEndpoint.port;
                }
              ];
              locations."/" = {
                proxyPass = "http://cryptpad:${toString webEndpoint.port}";
                proxyWebsockets = true;
                extraConfig = ''
                  client_max_body_size 150m;
                '';
              };
            };
          };
        };
      };

      runtimes = {
        container.enable = true;
        nixos.enable = true;
      };
    };

    # The container image is large (approximately 2 GiB).
    # The default disk of the test VM does not have sufficient space to load it.
    test.services.nixosConfig.virtualisation.diskSize = lib.mkForce 16384;

    test.services.script = ''
      curl="curl --retry 10 --retry-max-time 120 --retry-all-errors"

      $curl --fail localhost:3000 | grep -i "cryptpad" >/dev/null
      $curl --fail localhost:3000/api/config | grep "localhost:3001" >/dev/null
      $curl --fail localhost:3001/sheet/inner.html | grep -i "cryptpad" >/dev/null
    '';
  };
}
