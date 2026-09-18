{ config, lib, pkgs, ... }:

let
  # Python runtime used by MogLedger.
  # Package versions are pinned indirectly through this repo's flake.lock.
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    aiohttp
    aiosqlite
    xlsxwriter
  ]);

  homeDir = config.home.homeDirectory;
  projectDir = "${homeDir}/Documents/MogLedger";
  dbPath = "${homeDir}/Documents/uni_watch.db";

  # Explicit PATHs keep systemd services independent of the interactive shell.
  backupPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.restic
  ];

  alertPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.libnotify
    pkgs.systemd
  ];
in
{
  # ---------------------------------------------------------------------------
  # MogLedger runtime dependencies
  # ---------------------------------------------------------------------------

  # Available interactively as well as to the systemd services.
  home.packages = [
    pythonEnv
    pkgs.restic
    pkgs.libnotify
  ];

  # ---------------------------------------------------------------------------
  # Failure notification
  # ---------------------------------------------------------------------------

  # Called by OnFailure= whenever one of the MogLedger jobs fails.
  systemd.user.services."mogledger-alert@" = {
    Unit = {
      Description = "MogLedger failure alert for %i";

      # Skip cleanly until the MogLedger repo exists.
      ConditionPathExists = "${projectDir}/alert_failure.sh";
    };

    Service = {
      Type = "oneshot";

      Environment = [
        "PATH=${alertPath}"
      ];

      ExecStart =
        "${pkgs.bash}/bin/bash ${projectDir}/alert_failure.sh %i";
    };
  };

  # ---------------------------------------------------------------------------
  # Fetch + aggregate
  # ---------------------------------------------------------------------------

  systemd.user.services.mogledger-fetch = {
    Unit = {
      Description = "MogLedger — fetch and aggregate";

      # Notify the user if the job exits unsuccessfully.
      OnFailure = [ "mogledger-alert@%n.service" ];

      # On a fresh install the timer may exist before MogLedger itself has
      # been cloned. Skip cleanly instead of generating a failure.
      ConditionPathExists = "${projectDir}/uni_watch.py";
    };

    Service = {
      Type = "oneshot";
      WorkingDirectory = projectDir;

      Environment = [
        "UNI_DB=${dbPath}"
        "UNI_PYTHON=${pythonEnv}/bin/python"
        "PYTHONUNBUFFERED=1"
      ];

      # systemd runs these sequentially.
      # Aggregate only runs if fetch succeeds.
      ExecStart = [
        "${pythonEnv}/bin/python ${projectDir}/uni_watch.py fetch"
        "${pythonEnv}/bin/python ${projectDir}/uni_watch.py aggregate"
      ];
    };
  };

  systemd.user.timers.mogledger-fetch = {
    Unit.Description = "Run MogLedger fetch 3x daily";

    Timer = {
      # 08:00, 14:00, and 20:00 every day.
      OnCalendar = "*-*-* 08,14,20:00:00";

      # Run a missed job after the next login/startup.
      Persistent = true;
    };

    Install.WantedBy = [ "timers.target" ];
  };

  # ---------------------------------------------------------------------------
  # Daily full pipeline
  # ---------------------------------------------------------------------------

  systemd.user.services.mogledger-daily = {
    Unit = {
      Description = "MogLedger — full daily pipeline";
      OnFailure = [ "mogledger-alert@%n.service" ];

      # Skip cleanly until the application exists on this machine.
      ConditionPathExists = "${projectDir}/update_uni_watch.py";
    };

    Service = {
      Type = "oneshot";
      WorkingDirectory = projectDir;

      Environment = [
        "UNI_DB=${dbPath}"
        "UNI_PYTHON=${pythonEnv}/bin/python"
        "PYTHONUNBUFFERED=1"
      ];

      ExecStart =
        "${pythonEnv}/bin/python ${projectDir}/update_uni_watch.py";
    };
  };

  systemd.user.timers.mogledger-daily = {
    Unit.Description = "Run MogLedger full pipeline at 9pm";

    Timer = {
      OnCalendar = "*-*-* 21:00:00";
      Persistent = true;
    };

    Install.WantedBy = [ "timers.target" ];
  };

  # ---------------------------------------------------------------------------
  # Backblaze B2 backup
  # ---------------------------------------------------------------------------

  systemd.user.services.mogledger-backup = {
    Unit = {
      Description = "MogLedger — Backblaze database backup";
      OnFailure = [ "mogledger-alert@%n.service" ];

      # Only attempt backups once both the script and the secret env file exist.
      # This keeps a fresh machine quiet until Backblaze is configured.
      ConditionPathExists = [
        "${projectDir}/backup_db.sh"
        "${homeDir}/.config/mogledger/backup.env"
      ];
    };

    Service = {
      Type = "oneshot";
      WorkingDirectory = projectDir;

      Environment = [
        "UNI_DB=${dbPath}"
        "UNI_PYTHON=${pythonEnv}/bin/python"
        "PATH=${backupPath}"
      ];

      # backup_db.sh reads the actual Backblaze credentials from:
      # ~/.config/mogledger/backup.env
      #
      # That file intentionally stays outside Git/Nix because it contains
      # secrets.
      ExecStart =
        "${pkgs.bash}/bin/bash ${projectDir}/backup_db.sh";
    };
  };

  systemd.user.timers.mogledger-backup = {
    Unit.Description = "Run MogLedger Backblaze backup nightly";

    Timer = {
      OnCalendar = "*-*-* 02:30:00";
      Persistent = true;
    };

    Install.WantedBy = [ "timers.target" ];
  };
}
