#!rsc by RouterOS
# RouterOS script: packages-update
# Copyright (c) 2019-2024 Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# requires RouterOS, version=7.12
#
# download packages and reboot for installation
# https://git.eworm.de/cgit/routeros-scripts/about/doc/packages-update.md

:local 0 [ :jobname ];
:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:global DownloadPackage;
:global Grep;
:global LogPrintExit2;
:global ParseKeyValueStore;
:global ScriptFromTerminal;
:global ScriptLock;
:global VersionToNum;

:global PackagesUpdateDeferReboot;

:local Schedule do={
  :global GetRandomNumber;
  :global LogPrintExit2;

  :global RebootForUpdate do={
    /system/reboot;
  }

  :local StartTime [ :tostr [ :totime (10800 + [ $GetRandomNumber 7200 ]) ] ];
  /system/scheduler/add name="_RebootForUpdate" start-time=$StartTime interval=1d \
      on-event=("/system/scheduler/remove \"_RebootForUpdate\"; " . \
      ":global RebootForUpdate; \$RebootForUpdate;");
  $LogPrintExit2 info $1 ("Scheduled reboot for update at " . $StartTime . \
      " local time (" . [ /system/clock/get time-zone-name ] . ").") true;
}

$ScriptLock $0;

:local Update [ /system/package/update/get ];

:if ([ :typeof ($Update->"latest-version") ] = "nothing") do={
  $LogPrintExit2 warning $0 ("Latest version is not known.") true;
}

:if ($Update->"installed-version" = $Update->"latest-version") do={
  $LogPrintExit2 info $0 ("Version " . $Update->"latest-version" . " is already installed.") true;
}

:local NumInstalled [ $VersionToNum ($Update->"installed-version") ];
:local NumLatest [ $VersionToNum ($Update->"latest-version") ];

:if ($NumInstalled < 0x070d0000 && $NumLatest > 0x070d0000) do={
  $LogPrintExit2 error $0 ("Migration to wireless/wifi package in RouterOS " . \
    ($Update->"latest-version") . " is pending. Please update manually!") true;
}

:local DoDowngrade false;
:if ($NumInstalled > $NumLatest) do={
  :if ([ $ScriptFromTerminal $0 ] = true) do={
    :put "Latest version is older than installed one. Want to downgrade? [y/N]";
    :if (([ /terminal/inkey timeout=60 ] % 32) = 25) do={
      :set DoDowngrade true;
    } else={
      :put "Canceled...";
    }
  } else={
    $LogPrintExit2 warning $0 ("Not installing downgrade automatically.") true;
  }
}

:foreach Package in=[ /system/package/find where !bundle ] do={
  :local PkgName [ /system/package/get $Package name ];
  :if ([ $DownloadPackage $PkgName ($Update->"latest-version") ] = false) do={
    $LogPrintExit2 error $0 ("Download for package " . $PkgName . " failed, update aborted.") true;
  }
}

:local RunOrder ({});
:foreach Script in=[ /system/script/find where source~("\n# provides: backup-script\\b") ] do={
  :local ScriptVal [ /system/script/get $Script ];
  :local Store [ $ParseKeyValueStore [ $Grep ($ScriptVal->"source") ("\23 provides: backup-script, ") ] ];

  :set ($RunOrder->($Store->"order" . "-" . $ScriptVal->"name")) ($ScriptVal->"name");
}

:foreach Order,Script in=$RunOrder do={
  :do {
    $LogPrintExit2 info $0 ("Running backup script " . $Script . " before update.") false;
    /system/script/run $Script;
  } on-error={
    $LogPrintExit2 warning $0 ("Running backup script " . $Script . " before update failed!") false;
    :if ([ $ScriptFromTerminal $0 ] = true) do={
      :put "Do you want to continue anyway? [y/N]";
      :if (([ /terminal/inkey timeout=60 ] % 32) = 25) do={
        $LogPrintExit2 info $0 ("User requested to continue anyway.") false;
      } else={
        $LogPrintExit2 info $0 ("Canceled update...") true;
      }
    } else={
      $LogPrintExit2 info $0 ("Canceled non-interactive update.") true;
    }
  }
}

:if ($DoDowngrade = true) do={
  $LogPrintExit2 info $0 ("Rebooting for downgrade.") false;
  :delay 1s;
  /system/package/downgrade;
}

:if ([ $ScriptFromTerminal $0 ] = true) do={
  :put "Do you want to (s)chedule reboot or (r)eboot now? [s/R]";
  :if (([ /terminal/inkey timeout=60 ] % 32) = 19) do={
    $Schedule $0;
  }
} else={
  :if ($PackagesUpdateDeferReboot = true) do={
    $Schedule $0;
  }
}

$LogPrintExit2 info $0 ("Rebooting for update.") false;
:delay 1s;
/system/reboot;
