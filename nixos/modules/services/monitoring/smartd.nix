{ config, lib, options, pkgs, ... }:

with lib;

let

  host = config.networking.fqdnOrHostName;

  cfg = config.services.smartd;
  opt = options.services.smartd;

  nm = cfg.notifications.mail;
  ns = cfg.notifications.systembus-notify;
  nw = cfg.notifications.wall;
  nx = cfg.notifications.x11;

  smartdNotify = pkgs.writeScript "smartd-notify.sh" ''
    #! ${pkgs.runtimeShell}
    ${optionalString nm.enable ''
      {
      ${pkgs.coreutils}/bin/cat << EOF
      From: smartd on ${host} <${nm.sender}>
      To: ${nm.recipient}
      Subject: $SMARTD_SUBJECT

      $SMARTD_FULLMESSAGE
      EOF

      ${pkgs.smartmontools}/sbin/smartctl -a -d "$SMARTD_DEVICETYPE" "$SMARTD_DEVICE"
      } | ${nm.mailer} -i "${nm.recipient}"
    ''}
    ${optionalString ns.enable ''
      ${pkgs.dbus}/bin/dbus-send --system \
        / net.nuetzlich.SystemNotifications.Notify \
        "string:Problem detected with disk: $SMARTD_DEVICESTRING" \
        "string:Warning message from smartd is: $SMARTD_MESSAGE"
    ''}
    ${optionalString nw.enable ''
      {
      ${pkgs.coreutils}/bin/cat << EOF
      Problem detected with disk: $SMARTD_DEVICESTRING
      Warning message from smartd is:

      $SMARTD_MESSAGE
      EOF
      } | ${pkgs.util-linux}/bin/wall 2>/dev/null
    ''}
    ${optionalString nx.enable ''
      export DISPLAY=${nx.display}
      {
      ${pkgs.coreutils}/bin/cat << EOF
      Problem detected with disk: $SMARTD_DEVICESTRING
      Warning message from smartd is:

      $SMARTD_FULLMESSAGE
      EOF
      } | ${pkgs.xorg.xmessage}/bin/xmessage -file - 2>/dev/null &
    ''}
  '';

  notifyOpts = optionalString (nm.enable || nw.enable || nx.enable)
    ("-m <nomailer> -M exec ${smartdNotify} " + optionalString cfg.notifications.test "-M test ");

  smartdConf = pkgs.writeText "smartd.conf" ''
    # Autogenerated smartd startup config file
    DEFAULT ${notifyOpts}${cfg.defaults.monitored}

    ${concatMapStringsSep "\n" (d: "${d.device} ${d.options}") cfg.devices}

    ${optionalString cfg.autodetect
       "DEVICESCAN ${notifyOpts}${cfg.defaults.autodetected}"}
  '';

  smartdDeviceOpts = { ... }: {

    options = {

      device = mkOption {
        example = "/dev/sda";
        type = types.str;
        description = "Location of the device.";
      };

      options = mkOption {
        default = "";
        example = "-d sat";
        type = types.separatedString " ";
        description = "Options that determine how smartd monitors the device.";
      };

    };

  };

in

{
  ###### interface

  options = {

    services.smartd = {

      enable = mkEnableOption "smartd daemon from `smartmontools` package";

      autodetect = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Whenever smartd should monitor all devices connected to the
          machine at the time it's being started (the default).

          Set to false to monitor the devices listed in
          {option}`services.smartd.devices` only.
        '';
      };

      extraOptions = mkOption {
        default = [];
        type = types.listOf types.str;
        example = ["-A /var/log/smartd/" "--interval=3600"];
        description = ''
          Extra command-line options passed to the `smartd`
          daemon on startup.

          (See `man 8 smartd`.)
        '';
      };

      notifications = {

        mail = {
          enable = mkOption {
            default = config.services.mail.sendmailSetuidWrapper != null;
            defaultText = literalExpression "config.services.mail.sendmailSetuidWrapper != null";
            type = types.bool;
            description = "Whenever to send e-mail notifications.";
          };

          sender = mkOption {
            default = "root";
            example = "example@domain.tld";
            type = types.str;
            description = ''
              Sender of the notification messages.
              Acts as the value of `email` in the emails' `From: ...` field.
            '';
          };

          recipient = mkOption {
            default = "root";
            type = types.str;
            description = "Recipient of the notification messages.";
          };

          mailer = mkOption {
            default = "/run/wrappers/bin/sendmail";
            type = types.path;
            description = ''
              Sendmail-compatible binary to be used to send the messages.

              You should probably enable
              {option}`services.postfix` or some other MTA for
              this to work.
            '';
          };
        };

        systembus-notify = {
          enable = mkOption {
            default = false;
            type = types.bool;
            description = ''
              Whenever to send systembus-notify notifications.

              WARNING: enabling this option (while convenient) should *not* be done on a
              machine where you do not trust the other users as it allows any other
              local user to DoS your session by spamming notifications.

              To actually see the notifications in your GUI session, you need to have
              `systembus-notify` running as your user, which this
              option handles by enabling {option}`services.systembus-notify`.
            '';
          };
        };

        wall = {
          enable = mkOption {
            default = true;
            type = types.bool;
            description = "Whenever to send wall notifications to all users.";
          };
        };

        x11 = {
          enable = mkOption {
            default = config.services.xserver.enable;
            defaultText = literalExpression "config.services.xserver.enable";
            type = types.bool;
            description = "Whenever to send X11 xmessage notifications.";
          };

          display = mkOption {
            default = ":${toString config.services.xserver.display}";
            defaultText = literalExpression ''":''${toString config.services.xserver.display}"'';
            type = types.str;
            description = "DISPLAY to send X11 notifications to.";
          };
        };

        test = mkOption {
          default = false;
          type = types.bool;
          description = "Whenever to send a test notification on startup.";
        };

      };

      defaults = {
        monitored = mkOption {
          default = "-a";
          type = types.separatedString " ";
          example = "-a -o on -s (S/../.././02|L/../../7/04)";
          description = ''
            Common default options for explicitly monitored (listed in
            {option}`services.smartd.devices`) devices.

            The default value turns on monitoring of all the things (see
            `man 5 smartd.conf`).

            The example also turns on SMART Automatic Offline Testing on
            startup, and schedules short self-tests daily, and long
            self-tests weekly.
          '';
        };

        autodetected = mkOption {
          default = cfg.defaults.monitored;
          defaultText = literalExpression "config.${opt.defaults.monitored}";
          type = types.separatedString " ";
          description = ''
            Like {option}`services.smartd.defaults.monitored`, but for the
            autodetected devices.
          '';
        };
      };

      devices = mkOption {
        default = [];
        example = [ { device = "/dev/sda"; } { device = "/dev/sdb"; options = "-d sat"; } ];
        type = with types; listOf (submodule smartdDeviceOpts);
        description = "List of devices to monitor.";
      };

    };

  };


  ###### implementation

  config = mkIf cfg.enable {

    assertions = [ {
      assertion = cfg.autodetect || cfg.devices != [];
      message = "smartd can't run with both disabled autodetect and an empty list of devices to monitor.";
    } ];

    systemd.services.smartd = {
      description = "S.M.A.R.T. Daemon";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.smartmontools}/sbin/smartd ${lib.concatStringsSep " " cfg.extraOptions} --no-fork --configfile=${smartdConf}";
      };
    };

    services.systembus-notify.enable = mkDefault ns.enable;

  };

}
