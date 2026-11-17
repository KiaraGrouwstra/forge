{
  forge-lib,
  config,
  pkgs,
  lib,
  ...
}:
let
  app = config.apps.forgejo;
  webPort = toString app.services.components.forgejo.endpoints.web.forwardedPort;

  forgejo = pkgs.forgejo;
  httpPort = 3000;
  stateDir = app.services.components.forgejo.process.stateDir;
  customDir = "${stateDir}/custom";

  settingsFormat = pkgs.formats.ini { };
  settings = {
    DEFAULT = {
      RUN_MODE = "prod";
      WORK_PATH = stateDir;
    };
    database = {
      DB_TYPE = "sqlite3";
      PATH = "${stateDir}/data/forgejo.db";
    };
    repository.ROOT = "${stateDir}/repositories";
    server = {
      DOMAIN = "localhost";
      HTTP_PORT = httpPort;
      ROOT_URL = "http://localhost:${webPort}/";
      # The app has no SSH endpoint.
      DISABLE_SSH = true;
    };
    session.COOKIE_NAME = "session";
    security = {
      INSTALL_LOCK = true;
      SECRET_KEY_URI = "file:${customDir}/conf/secret_key";
      INTERNAL_TOKEN_URI = "file:${customDir}/conf/internal_token";
    };
    oauth2.JWT_SECRET_URI = "file:${customDir}/conf/jwt_secret";
    service.DISABLE_REGISTRATION = true;
  };
in
{
  apps.forgejo = {
    displayName = "Forgejo";
    description = "Self-hosted software forge with Git hosting, code review, issues and CI.";
    categories = with forge-lib.categories; [ Development ];
    usage = ''
      Forgejo is a software forge. It hosts Git repositories and gives code review, issue tracking, package registries and CI with Forgejo Actions.

      It runs as a web service. The web interface is available on [http://localhost:${webPort}](http://localhost:${webPort}).
      Log in with the user `demo` and the password `demo1234`. This user is an administrator.

      This configuration is for evaluation only. Before you use Forgejo in production, change the administrator password and configure TLS and the server domain.
    '';

    icon = ./icon.svg;

    links = {
      website = "https://forgejo.org";
      source = "https://codeberg.org/forgejo/forgejo";
      docs = "https://forgejo.org/docs/latest/";
    };

    ngi.grants = {
      Entrust = [
        "Forgejo"
        "Federated-Forgejo"
      ];
      Commons = [ "Forgejo-workflow" ];
    };

    services = {
      components.forgejo = {
        process = {
          command = forgejo;
          argv = [ "web" ];
          environment = {
            HOME = stateDir;
            FORGEJO_WORK_DIR = stateDir;
            FORGEJO_CUSTOM = customDir;
          };
          configData."app.ini" = {
            source = settingsFormat.generate "app.ini" settings;
            path = "app.ini";
          };
          # Forgejo reads the configuration from `$FORGEJO_CUSTOM/conf/app.ini`.
          # It must be a file that Forgejo can write.
          preStart = ''
            umask 027
            mkdir --parents ${customDir}/conf ${stateDir}/data ${stateDir}/log

            for secret in SECRET_KEY INTERNAL_TOKEN JWT_SECRET; do
              file=${customDir}/conf/''${secret,,}
              if [ ! -s "$file" ]; then
                (umask 077; ${lib.getExe forgejo} generate secret "$secret" > "$file")
              fi
            done

            install --mode=0640 "$XDG_CONFIG_HOME/app.ini" ${customDir}/conf/app.ini

            ${lib.getExe forgejo} migrate
            ${lib.getExe forgejo} admin regenerate hooks

            # Make the demo administrator.
            if ! ${lib.getExe forgejo} admin user list --admin | ${lib.getExe pkgs.gnugrep} -qw demo; then
              ${lib.getExe forgejo} admin user create --admin --username demo --password demo1234 \
                --email demo@localhost --must-change-password=false
            fi
          '';
          packages = [
            forgejo
            pkgs.git
            pkgs.gnupg
          ];
        };
        endpoints.web.port = httpPort;
      };

      runtimes = {
        container.enable = true;
        nixos.enable = true;
      };
    };

    test.services.script = ''
      curl="curl --retry 10 --retry-max-time 120 --retry-all-errors"

      $curl --fail localhost:3000/user/login | grep -i "forgejo" >/dev/null
      $curl --fail --user demo:demo1234 localhost:3000/api/v1/user | grep '"login":"demo"' >/dev/null
    '';
  };
}
