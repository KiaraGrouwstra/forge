{
  forge-lib,
  config,
  lib,
  pkgs,
  ...
}:
let
  app = config.apps.taler;
  webPort = toString app.services.components.merchant-httpd.endpoints.web.forwardedPort;

  port = 8083;
  dbName = "taler-merchant";

  # The configuration that all merchant processes use.
  # `database` is the host name of the database resource.
  talerConf = lib.generators.toINI { } {
    taler = {
      CURRENCY = "KUDOS";
      CURRENCY_ROUND_UNIT = "KUDOS:0.01";
    };
    merchant = {
      SERVE = "tcp";
      PORT = port;
      DB = "postgres";
    };
    merchantdb-postgres = {
      CONFIG = "postgres://${dbName}@database/${dbName}";
      SQL_DIR = "${pkgs.taler-merchant}/share/taler/sql/merchant/";
    };
  };

  mkMerchantComponent =
    name: extraConfig:
    lib.recursiveUpdate {
      process = {
        command = lib.getExe' pkgs.taler-merchant "taler-merchant-${name}";
        argv = [
          "-c"
          "$XDG_CONFIG_HOME/taler.conf"
        ];
        configData."taler.conf" = {
          text = talerConf;
          path = "taler.conf";
        };
        # Taler keeps its data and cache files below `$HOME`.
        # Use the state directory of the component.
        environment.HOME = "/var/lib/merchant-${name}";
        # `taler-merchant-depositcheck` finds other programs in `PATH`.
        packages = [ pkgs.taler-merchant ];
      };
    } extraConfig;
in
{
  apps.taler = {
    displayName = "GNU Taler";
    description = "Privacy-preserving electronic payment system. This app runs the merchant backend with its web interface.";
    categories = with forge-lib.categories; [ Network ];
    usage = ''
      GNU Taler is an electronic payment system. Customers pay with a wallet. The exchange keeps the payments anonymous for the customer, but the merchant income is visible to tax authorities.

      This app runs the merchant backend. A shop uses the merchant backend to make orders and to receive payments.

      It runs as a web service. The merchant web interface is available on [http://localhost:${webPort}/webui/](http://localhost:${webPort}/webui/).
      Log in to the instance `admin` with the password `admin-password`.

      The backend uses the test currency `KUDOS`. To receive payments, add a bank account to the instance and connect to an exchange for `KUDOS`.

      This configuration is for evaluation only. Before you use the merchant backend in production, change the administrator password and configure TLS, a real currency and a bank account.
    '';

    icon = ./icon.svg;

    links = {
      website = "https://taler.net";
      source = "https://git.taler.net/merchant.git";
      docs = "https://docs.taler.net/taler-merchant-manual.html";
    };

    ngi.grants = {
      Entrust = [ "GNUTaler-LocalCurrencies" ];
      Review = [
        "GNUTaler"
        "GNUTaler-KYC"
      ];
    };

    services = {
      components = {
        # The HTTP server. It also makes the database tables and the `admin` instance.
        merchant-httpd = mkMerchantComponent "httpd" {
          # `taler-merchant-dbinit` runs `psql`.
          process.packages = [
            pkgs.taler-merchant
            pkgs.postgresql
          ];
          process.preStart = ''
            ${lib.getExe' pkgs.taler-merchant "taler-merchant-dbinit"} -c "$XDG_CONFIG_HOME/taler.conf"

            # Make the `admin` instance with a demo password.
            # The `taler-merchant-passwd` command makes this instance if it does not exist.
            # The password is an argument, because the `TALER_MERCHANT_PASSWORD` variable does not work in version 1.3.0.
            ${lib.getExe' pkgs.taler-merchant "taler-merchant-passwd"} -c "$XDG_CONFIG_HOME/taler.conf" -i admin admin-password
          '';
          endpoints.web.port = port;
          healthcheck = {
            enable = true;
            test = [
              "curl"
              "--fail"
              "--silent"
              "http://localhost:${toString port}/config"
            ];
            packages = [ pkgs.curl ];
            interval = "3s";
            timeout = "3s";
            retries = 20;
          };
        };
      }
      # The background processes. They start after `merchant-httpd` is healthy,
      # thus after the database tables exist.
      // lib.genAttrs' [ "webhook" "wirewatch" "depositcheck" "exchangekeyupdate" ] (
        name:
        lib.nameValuePair "merchant-${name}" (
          mkMerchantComponent name {
            dependsOn = [ "merchant-httpd" ];
          }
        )
      );

      resources.database.nixosConfig = {
        services.postgresql = {
          enable = true;
          ensureDatabases = [ dbName ];
          ensureUsers = [
            {
              name = dbName;
              ensureDBOwnership = true;
            }
          ];
        };
      };

      runtimes = {
        container = {
          enable = true;
          resources.database.nixosConfig = {
            services.postgresql.enableTCPIP = true;
            services.postgresql.authentication = ''
              host all all 0.0.0.0/0 trust
              host all all ::0/0 trust
            '';
          };
        };
        nixos = {
          enable = true;
          nixosConfig = {
            services.postgresql.authentication = ''
              local all all trust
              host all all 127.0.0.1/32 trust
              host all all ::1/128 trust
            '';
          };
        };
      };
    };

    # The container test loads one image for each component.
    # The default disk of the test machine is too small for these images.
    test.services.nixosConfig.virtualisation.diskSize = lib.mkForce 8192;

    test.services.script = ''
      curl="curl --retry 10 --retry-max-time 120 --retry-all-errors"

      $curl --fail localhost:8083/config | grep "taler-merchant" >/dev/null
      $curl --fail --location localhost:8083/webui/ | grep -i "taler" >/dev/null
      $curl --fail --user admin:admin-password --json '{"scope":"readonly"}' \
        localhost:8083/private/token | grep "access_token" >/dev/null
    '';
  };
}
