#!rsc by RouterOS
# RouterOS script: gps-track
# Copyright (c) 2018-2024 Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# requires RouterOS, version=7.12
#
# track gps data by sending json data to http server
# https://git.eworm.de/cgit/routeros-scripts/about/doc/gps-track.md

:local 0 [ :jobname ];
:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:global GpsTrackUrl;
:global Identity;

:global LogPrintExit2;
:global ScriptLock;
:global WaitFullyConnected;

$ScriptLock $0;
$WaitFullyConnected;

:local CoordinateFormat [ /system/gps/get coordinate-format ];
:local Gps [ /system/gps/monitor once as-value ];

:if ($Gps->"valid" = true) do={
  :do {
    /tool/fetch check-certificate=yes-without-crl $GpsTrackUrl output=none \
      http-method=post http-header-field=({ "Content-Type: application/json" }) \
      http-data=("{" . \
        "\"lat\":\"" . ($Gps->"latitude") . "\"," . \
        "\"lon\":\"" . ($Gps->"longitude") . "\"," . \
        "\"identity\":\"" . $Identity . "\"" . \
      "}") as-value;
    $LogPrintExit2 debug $0 ("Sending GPS data in " . $CoordinateFormat . " format: " . \
      "lat: " . ($Gps->"latitude") . " " . \
      "lon: " . ($Gps->"longitude")) false;
  } on-error={
    $LogPrintExit2 warning $0 ("Failed sending GPS data!") false;
  }
} else={
  $LogPrintExit2 debug $0 ("GPS data not valid.") false;
}
