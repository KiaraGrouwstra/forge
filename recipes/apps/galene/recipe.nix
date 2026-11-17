{
  forge-lib,
  config,
  pkgs,
  ...
}:
let
  app = config.apps.galene;
  inherit (app.services.components.galene.process) stateDir;
  webPort = toString app.services.components.galene.endpoints.web.forwardedPort;

  # Directory with the group definitions.
  # Galene reads one JSON file for each group.
  groupsDir = pkgs.writeTextDir "demo.json" (
    builtins.toJSON {
      description = "Demo group";
      public = true;
      users.demo = {
        password = "demo";
        permissions = "op";
      };
    }
  );
in
{
  apps.galene = {
    displayName = "Galene";
    description = "Videoconference server that is easy to deploy and that needs few server resources.";
    categories = with forge-lib.categories; [ Network ];
    usage = ''
      Galene is a videoconference server. It supports video, audio, screen sharing, chat and recording.

      It runs as a web service. The web interface is available on [http://localhost:${webPort}](http://localhost:${webPort}).
      Open the group `demo` on [http://localhost:${webPort}/group/demo/](http://localhost:${webPort}/group/demo/).
      Log in with the user `demo` and the password `demo`. This user is an operator of the group.

      The web interface uses plain HTTP. Most web browsers let you use the camera and the microphone only on `localhost`.

      This configuration is for evaluation only. Before you use Galene in production, change the password and configure TLS.
    '';

    icon = ./icon.svg;

    links = {
      website = "https://galene.org";
      source = "https://github.com/jech/galene";
      docs = "https://galene.org/galene-install.html";
    };

    ngi.grants = {
      Core = [ "Galene" ];
      Commons = [ "Galene-UX" ];
    };

    services = {
      components.galene = {
        process = {
          command = "${pkgs.galene}/bin/galene";
          # These are the arguments that the NixOS module `services.galene` uses.
          argv = [
            "-insecure"
            "-http"
            ":8443"
            "-turn"
            "auto"
            "-data"
            "${stateDir}/data"
            "-groups"
            "${groupsDir}"
            "-recordings"
            "${stateDir}/recordings"
            "-static"
            "${pkgs.galene.static}/static"
          ];
          preStart = ''
            mkdir --parents ${stateDir}/data ${stateDir}/recordings
          '';
          packages = [ pkgs.coreutils ];
        };
        endpoints = {
          web.port = 8443;
        };
      };

      runtimes = {
        container.enable = true;
        nixos.enable = true;
      };
    };

    test.services.script = ''
      curl="curl --retry 10 --retry-max-time 120 --retry-all-errors"

      $curl --fail localhost:8443/ | grep "<title>Gal" >/dev/null
      $curl --fail localhost:8443/public-groups.json | grep '"demo"' >/dev/null
      $curl --fail localhost:8443/group/demo/.status | grep '"name":"demo"' >/dev/null
    '';
  };
}
