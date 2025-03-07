#!rsc by RouterOS
# RouterOS script: netwatch-notify
# Copyright (c) 2020-2024 Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# requires RouterOS, version=7.12
#
# monitor netwatch and send notifications
# https://git.eworm.de/cgit/routeros-scripts/about/doc/netwatch-notify.md

:local 0 [ :jobname ];
:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:global NetwatchNotify;

:global EitherOr;
:global IfThenElse;
:global IsDNSResolving;
:global LogPrintExit2;
:global ParseKeyValueStore;
:global ScriptFromTerminal;
:global ScriptLock;
:global SendNotification2;
:global SymbolForNotification;

:local NetwatchNotifyHook do={
  :local Name  [ :tostr $1 ];
  :local Type  [ :tostr $2 ];
  :local State [ :tostr $3 ];
  :local Hook  [ :tostr $4 ];

  :global LogPrintExit2;
  :global ValidateSyntax;

  :if ([ $ValidateSyntax $Hook ] = true) do={
    :do {
      [ :parse $Hook ];
    } on-error={
      $LogPrintExit2 warning $0 ("The " . $State . "-hook for " . $Type . " '" . $Name . \
          "' failed to run.") false;
      :return ("The hook failed to run.");
    }
  } else={
    $LogPrintExit2 warning $0 ("The " . $State . "-hook for " . $Type . " '" . $Name . \
        "' failed syntax validation.") false;
    :return ("The hook failed syntax validation.");
  }

  $LogPrintExit2 info $0 ("Ran hook on " . $Type . " '" . $Name . "' " . $State . ": " . \
      $Hook) false;
  :return ("Ran hook:\n" . $Hook);
}

$ScriptLock $0;

:local ScriptFromTerminalCached [ $ScriptFromTerminal $0 ];

:if ([ :typeof $NetwatchNotify ] = "nothing") do={
  :set NetwatchNotify ({});
}

:foreach Host in=[ /tool/netwatch/find where comment~"\\bnotify\\b" !disabled status!="unknown" ] do={
  :local HostVal [ /tool/netwatch/get $Host ];
  :local Type [ $IfThenElse ($HostVal->"type" ~ "^(https?-get|tcp-conn)\$") "service" "host" ];
  :local HostInfo [ $ParseKeyValueStore ($HostVal->"comment") ];
  :local HostDetails ($HostVal->"host" . \
      [ $IfThenElse ([ :len ($HostInfo->"resolve") ] > 0) (", " . $HostInfo->"resolve") ]);

  :if ($HostInfo->"notify" = true && $HostInfo->"disabled" != true) do={
    :local Name [ $EitherOr ($HostInfo->"name") ($HostVal->"name") ];

    :local Metric { "count-down"=0; "count-up"=0; "notified"=false; "resolve-failcnt"=0 };
    :if ([ :typeof ($NetwatchNotify->$Name) ] = "array") do={
      :set $Metric ($NetwatchNotify->$Name);
    }

    :if ([ :typeof ($HostInfo->"resolve") ] = "str") do={
      :if ([ $IsDNSResolving ] = true) do={
        :do {
          :local Resolve [ :resolve ($HostInfo->"resolve") ];
          :if ($Resolve != $HostVal->"host" and \
               [ :len [ /ip/dns/cache/find where name=($HostInfo->"resolve") data=[ :tostr ($HostVal->"host") ] ] ] = 0) do={
             $LogPrintExit2 info $0 ("Name '" . $HostInfo->"resolve" . [ $IfThenElse \
                 ($HostInfo->"resolve" != $HostInfo->"name") ("' for " . $Type . " '" . \
                 $HostInfo->"name") "" ] . "' resolves to different address " . $Resolve . \
                 ", updating.") false;
            /tool/netwatch/set host=$Resolve $Host;
            :set ($Metric->"resolve-failcnt") 0;
          }
        } on-error={
          :set ($Metric->"resolve-failcnt") ($Metric->"resolve-failcnt" + 1);
          :if ($Metric->"resolve-failcnt" = 3) do={
            $LogPrintExit2 warning $0 ("Resolving name '" . $HostInfo->"resolve" . [ $IfThenElse \
                ($HostInfo->"resolve" != $HostInfo->"name") ("' for " . $Type . " '" . \
                $HostInfo->"name") "" ] . "' failed.") false;
          }
        }
      }
    }

    :if ($HostVal->"status" = "up") do={
      :local CountDown ($Metric->"count-down");
      :if ($CountDown > 0) do={
        $LogPrintExit2 info $0 \
            ("The " . $Type . " '" . $Name . "' (" . $HostDetails . ") is up.") false;
        :set ($Metric->"count-down") 0;
      }
      :set ($Metric->"count-up") ($Metric->"count-up" + 1);
      :if ($Metric->"notified" = true) do={
        :local Message ("The " . $Type . " '" . $Name . "' (" . $HostDetails . \
            ") is up since " . $HostVal->"since" . ".\n" . \
            "It was down for " . $CountDown . " checks since " . ($Metric->"since") . ".");
        :if ([ :typeof ($HostInfo->"note") ] = "str") do={
          :set Message ($Message . "\n\nNote:\n" . ($HostInfo->"note"));
        }
        :if ([ :typeof ($HostInfo->"up-hook") ] = "str") do={
          :set Message ($Message . "\n\n" . [ $NetwatchNotifyHook $Name $Type "up" \
              ($HostInfo->"up-hook") ]);
        }
        $SendNotification2 ({ origin=[ $EitherOr ($HostInfo->"origin") $0 ]; silent=($HostInfo->"silent"); \
          subject=([ $SymbolForNotification "white-heavy-check-mark" ] . "Netwatch Notify: " . $Name . " up"); \
          message=$Message });
      }
      :set ($Metric->"notified") false;
      :set ($Metric->"parent") ($HostInfo->"parent");
      :set ($Metric->"since");
    } else={
      :set ($Metric->"count-down") ($Metric->"count-down" + 1);
      :set ($Metric->"count-up") 0;
      :set ($Metric->"parent") ($HostInfo->"parent");
      :set ($Metric->"since") ($HostVal->"since");
      :local CountDown [ $IfThenElse ([ :tonum ($HostInfo->"count") ] > 0) ($HostInfo->"count") 5 ];
      :local Parent ($HostInfo->"parent");
      :local ParentUp false;
      :while ([ :len $Parent ] > 0) do={
        :set CountDown ($CountDown + 1);
        :set Parent ($NetwatchNotify->$Parent->"parent");
      }
      :set Parent ($HostInfo->"parent");
      :local ParentNotified false;
      :while ($ParentNotified = false && [ :len $Parent ] > 0) do={
        :set ParentNotified [ $IfThenElse (($NetwatchNotify->$Parent->"notified") = true) \
            true false ];
        :set ParentUp ($NetwatchNotify->$Parent->"count-up");
        :if ($ParentNotified = false) do={
          :set Parent ($NetwatchNotify->$Parent->"parent");
        }
      }
      :if ($Metric->"notified" = false || $Metric->"count-down" % 120 = 0 || \
           $ScriptFromTerminalCached = true) do={
        $LogPrintExit2 [ $IfThenElse ($HostInfo->"no-down-notification" != true) info debug ] $0 \
            ("The " . $Type . " '" . $Name . "' (" . $HostDetails . ") is down for " . \
            $Metric->"count-down" . " checks, " . [ $IfThenElse ($ParentNotified = false) [ $IfThenElse \
            ($Metric->"notified" = true) ("already notified.") ($CountDown - $Metric->"count-down" . \
            " to go.") ] ("parent " . $Type . " " . $Parent . " is down.") ]) false;
      }
      :if ((($CountDown * 2) - ($Metric->"count-down" * 3)) / 2 = 0 && \
           [ :typeof ($HostInfo->"pre-down-hook") ] = "str") do={
        $NetwatchNotifyHook $Name $Type "pre-down" ($HostInfo->"pre-down-hook");
      }
      :if ($ParentNotified = false && $Metric->"count-down" >= $CountDown && \
           ($ParentUp = false || $ParentUp > 2) && $Metric->"notified" != true) do={
        :local Message ("The " . $Type . " '" . $Name . "' (" . $HostDetails . \
            ") is down since " . $HostVal->"since" . ".");
        :if ([ :typeof ($HostInfo->"note") ] = "str") do={
          :set Message ($Message . "\n\nNote:\n" . ($HostInfo->"note"));
        }
        :if ([ :typeof ($HostInfo->"down-hook") ] = "str") do={
          :set Message ($Message . "\n\n" . [ $NetwatchNotifyHook $Name $Type "down" \
              ($HostInfo->"down-hook") ]);
        }
        :if ($HostInfo->"no-down-notification" != true) do={
          $SendNotification2 ({ origin=[ $EitherOr ($HostInfo->"origin") $0 ]; silent=($HostInfo->"silent"); \
            subject=([ $SymbolForNotification "cross-mark" ] . "Netwatch Notify: " . $Name . " down"); \
            message=$Message });
        }
        :set ($Metric->"notified") true;
      }
    }
    :set ($NetwatchNotify->$Name) {
      "count-down"=($Metric->"count-down");
      "count-up"=($Metric->"count-up");
      "notified"=($Metric->"notified");
      "parent"=($Metric->"parent");
      "resolve-failcnt"=($Metric->"resolve-failcnt");
      "since"=($Metric->"since") };
  }
}
