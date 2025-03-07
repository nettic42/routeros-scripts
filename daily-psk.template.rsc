#!rsc by RouterOS
# RouterOS script: daily-psk%TEMPL%
# Copyright (c) 2013-2024 Christian Hesse <mail@eworm.de>
#                         Michael Gisbers <michael@gisbers.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# requires RouterOS, version=7.12
#
# update daily PSK (pre shared key)
# https://git.eworm.de/cgit/routeros-scripts/about/doc/daily-psk.md
#
# !! This is just a template to generate the real script!
# !! Pattern '%TEMPL%' is replaced, paths are filtered.

:local 0 [ :jobname ];
:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:global DailyPskMatchComment;
:global DailyPskQrCodeUrl;
:global Identity;

:global FormatLine;
:global LogPrintExit2;
:global ScriptLock;
:global SendNotification2;
:global SymbolForNotification;
:global UrlEncode;
:global WaitForFile;
:global WaitFullyConnected;

$ScriptLock $0;
$WaitFullyConnected;

# return pseudo-random string for PSK
:local GeneratePSK do={
  :local Date [ :tostr $1 ];

  :global DailyPskSecrets;

  :global ParseDate;

  :set Date [ $ParseDate $Date ];

  :local A ((14 - ($Date->"month")) / 12);
  :local B (($Date->"year") - $A);
  :local C (($Date->"month") + 12 * $A - 2);
  :local WeekDay (7000 + ($Date->"day") + $B + ($B / 4) - ($B / 100) + ($B / 400) + ((31 * $C) / 12));
  :set WeekDay ($WeekDay - (($WeekDay / 7) * 7));

  :return (($DailyPskSecrets->0->(($Date->"day") - 1)) . \
    ($DailyPskSecrets->1->(($Date->"month") - 1)) . \
    ($DailyPskSecrets->2->$WeekDay));
}

:local Seen ({});
:local Date [ /system/clock/get date ];
:local NewPsk [ $GeneratePSK $Date ];

:foreach AccList in=[ /caps-man/access-list/find where comment~$DailyPskMatchComment ] do={
:foreach AccList in=[ /interface/wifi/access-list/find where comment~$DailyPskMatchComment ] do={
:foreach AccList in=[ /interface/wifiwave2/access-list/find where comment~$DailyPskMatchComment ] do={
:foreach AccList in=[ /interface/wireless/access-list/find where comment~$DailyPskMatchComment ] do={
  :local SsidRegExp [ /caps-man/access-list/get $AccList ssid-regexp ];
  :local SsidRegExp [ /interface/wifi/access-list/get $AccList ssid-regexp ];
  :local SsidRegExp [ /interface/wifiwave2/access-list/get $AccList ssid-regexp ];
  :local Configuration ([ /caps-man/configuration/find where ssid~$SsidRegExp ]->0);
  :local Configuration ([ /interface/wifi/configuration/find where ssid~$SsidRegExp ]->0);
  :local Configuration ([ /interface/wifiwave2/configuration/find where ssid~$SsidRegExp ]->0);
  :local Ssid [ /caps-man/configuration/get $Configuration ssid ];
  :local Ssid [ /interface/wifi/configuration/get $Configuration ssid ];
  :local Ssid [ /interface/wifiwave2/configuration/get $Configuration ssid ];
  :local OldPsk [ /caps-man/access-list/get $AccList private-passphrase ];
  :local OldPsk [ /interface/wifi/access-list/get $AccList passphrase ];
  :local OldPsk [ /interface/wifiwave2/access-list/get $AccList passphrase ];
  # /caps-man/ /interface/wifi/ /interface/wifiwave2/ above - /interface/wireless/ below
  :local IntName [ /interface/wireless/access-list/get $AccList interface ];
  :local Ssid [ /interface/wireless/get $IntName ssid ];
  :local OldPsk [ /interface/wireless/access-list/get $AccList private-pre-shared-key ];
  :local Skip 0;

  :if ($NewPsk != $OldPsk) do={
    $LogPrintExit2 info $0 ("Updating daily PSK for " . $Ssid . " to " . $NewPsk . " (was " . $OldPsk . ")") false;
    /caps-man/access-list/set $AccList private-passphrase=$NewPsk;
    /interface/wifi/access-list/set $AccList passphrase=$NewPsk;
    /interface/wifiwave2/access-list/set $AccList passphrase=$NewPsk;
    /interface/wireless/access-list/set $AccList private-pre-shared-key=$NewPsk;

    :if ([ :len [ /caps-man/actual-interface-configuration/find where configuration.ssid=$Ssid !disabled ] ] > 0) do={
    :if ([ :len [ /interface/wifi/actual-configuration/find where configuration.ssid=$Ssid ] ] > 0) do={
    :if ([ :len [ /interface/wifiwave2/actual-configuration/find where configuration.ssid=$Ssid ] ] > 0) do={
    :if ([ :len [ /interface/wireless/find where name=$IntName !disabled ] ] = 1) do={
      :if ($Seen->$Ssid = 1) do={
        $LogPrintExit2 debug $0 ("Already sent a mail for SSID " . $Ssid . ", skipping.") false;
      } else={
        :local Link ($DailyPskQrCodeUrl . \
            "?scale=8&level=1&ssid=" . [ $UrlEncode $Ssid ] . "&pass=" . [ $UrlEncode $NewPsk ]);
        $SendNotification2 ({ origin=$0; \
          subject=([ $SymbolForNotification "calendar" ] . "daily PSK " . $Ssid); \
          message=("This is the daily PSK on " . $Identity . ":\n\n" . \
            [ $FormatLine "SSID" $Ssid ] . "\n" . \
            [ $FormatLine "PSK" $NewPsk ] . "\n" . \
            [ $FormatLine "Date" $Date ] . "\n\n" . \
            "A client device specific rule must not exist!"); link=$Link });
        :set ($Seen->$Ssid) 1;
      }
    }
  }
}
