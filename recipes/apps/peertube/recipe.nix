{
  forge-lib,
  config,
  lib,
  pkgs,
  ...
}:
let
  app = config.apps.peertube;
  webPort = toString app.services.components.peertube.endpoints.web.forwardedPort;
  stateDir = "/var/lib/peertube";

  # Settings as in the NixOS module `services.peertube`.
  configFile = (pkgs.formats.json { }).generate "production.json" {
    listen = {
      # Accept connections from outside the container.
      hostname = "0.0.0.0";
      port = 9000;
    };
    webserver = {
      https = false;
      hostname = "localhost";
      port = 9000;
    };
    database = {
      hostname = "database";
      port = 5432;
      name = "peertube";
      username = "peertube";
      password = "";
    };
    redis = {
      hostname = "redis";
      port = 6379;
    };
    # For evaluation only: this secret is in the world-readable Nix store.
    # In production, use a secret that is not in the Nix store.
    secrets.peertube = "demo-secret-do-not-use-in-production";
    storage = lib.genAttrs' [
      "tmp"
      "tmp_persistent"
      "bin"
      "avatars"
      "logs"
      "web_videos"
      "streaming_playlists"
      "original_video_files"
      "redundancy"
      "thumbnails"
      "storyboards"
      "previews"
      "captions"
      "torrents"
      "cache"
      "plugins"
      "client_overrides"
      "well_known"
      "uploads"
    ] (name: lib.nameValuePair name "${stateDir}/storage/${lib.replaceStrings [ "_" ] [ "-" ] name}/");
    import.videos.http.youtube_dl_release.python_path = lib.getExe pkgs.python3;
  };
in
{
  apps.peertube = {
    displayName = "PeerTube";
    description = "Decentralized video platform that uses ActivityPub and peer-to-peer streaming.";
    categories = with forge-lib.categories; [ Video ];
    usage = ''
      PeerTube is a video platform. PeerTube instances connect to each other with ActivityPub.

      It runs as a web service. The web interface is available on [http://localhost:${webPort}](http://localhost:${webPort}).
      Log in with the user `root` and the password `peertube`.

      This configuration is for evaluation only. Before you use PeerTube in production, change the root password, replace the secrets and configure TLS, a reverse proxy, SMTP and the server host name.
    '';

    icon = ./icon.svg;

    links = {
      website = "https://joinpeertube.org";
      source = "https://github.com/Chocobozzz/PeerTube";
      docs = "https://docs.joinpeertube.org";
    };

    ngi.grants = {
      Commons = [
        "PeerTube-for-Institutions"
        "PeerTube-Scalability"
      ];
      Entrust = [
        "PeerTube-mobile"
        "Peertube-Transcode"
      ];
      Review = [
        "PeerTube"
        "PeerTubeSearch"
      ];
    };

    services = {
      components.peertube = {
        process = {
          command = pkgs.writeShellScriptBin "peertube" ''
            set -e
            export PATH=${
              lib.makeBinPath [
                pkgs.peertube.nodejs
                pkgs.ffmpeg-headless
                pkgs.openssl
                pkgs.coreutils
              ]
            }:$PATH

            # PeerTube writes changes from the administration interface to this directory.
            mkdir --parents ${stateDir}/config
            ln --symbolic --force ${pkgs.peertube}/config/default.yaml ${stateDir}/config/default.yaml
            ln --symbolic --force ${configFile} ${stateDir}/config/production.json

            cd ${pkgs.peertube}
            exec node dist/server
          '';
          environment = {
            NODE_CONFIG_DIR = "${stateDir}/config";
            NODE_ENV = "production";
            NODE_EXTRA_CA_CERTS = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            HOME = stateDir;
            XDG_CACHE_HOME = "${stateDir}/cache";
            NPM_CONFIG_CACHE = "${stateDir}/cache/npm";
            NPM_CONFIG_PREFIX = "${pkgs.peertube}";
            HF_HOME = "${stateDir}/cache/huggingface";
            # For evaluation only: set a known password for the `root` user.
            # PeerTube uses it only when it creates the `root` user.
            PT_INITIAL_ROOT_PASSWORD = "peertube";
          };
        };
        endpoints.web.port = 9000;
      };

      # PeerTube connects as the owner of the `peertube` database.
      # Thus, it can create the `pg_trgm` and `unaccent` extensions.
      resources.database.nixosConfig = {
        services.postgresql = {
          enable = true;
          ensureDatabases = [ "peertube" ];
          ensureUsers = [
            {
              name = "peertube";
              ensureDBOwnership = true;
            }
          ];
        };
      };

      resources.redis.nixosConfig = {
        services.redis.servers.peertube = {
          enable = true;
          port = 6379;
        };
      };

      runtimes.container = {
        enable = true;
        # PeerTube runs commands such as `ffmpeg` through `/bin/sh`.
        # The NixOS runtime has `/bin/sh`, but the component image does not.
        components.peertube.packages = [ pkgs.bash ];
        # The component connects from a different container.
        resources.database.nixosConfig = {
          services.postgresql.enableTCPIP = true;
          services.postgresql.authentication = ''
            host all all 0.0.0.0/0 trust
            host all all ::0/0 trust
          '';
        };
        resources.redis.nixosConfig = {
          services.redis.servers.peertube = {
            bind = null;
            settings.protected-mode = "no";
          };
        };
      };

      runtimes.nixos = {
        enable = true;
        nixosConfig = {
          services.postgresql.authentication = ''
            host all all 127.0.0.1/32 trust
            host all all ::1/128 trust
          '';
        };
      };
    };

    # The PeerTube container image (about 2.4 GiB) is too large for the default disk of the test VM.
    test.services.nixosConfig.virtualisation.diskSize = lib.mkForce 16384;

    test.services.script = ''
      curl="curl --retry 10 --retry-max-time 120 --retry-all-errors"

      $curl --fail localhost:9000/api/v1/config | grep '"name":"PeerTube"' >/dev/null

      client=$($curl --fail localhost:9000/api/v1/oauth-clients/local)
      client_id=$(echo "$client" | sed -E 's/.*"client_id":"([^"]*)".*/\1/')
      client_secret=$(echo "$client" | sed -E 's/.*"client_secret":"([^"]*)".*/\1/')

      $curl --fail localhost:9000/api/v1/users/token \
        --data client_id="$client_id" \
        --data client_secret="$client_secret" \
        --data grant_type=password \
        --data username=root \
        --data password=peertube \
        | grep access_token >/dev/null
    '';
  };
}
