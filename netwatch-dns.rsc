#!rsc by RouterOS
# RouterOS script: netwatch-dns
# Copyright (c) 2022-2024 Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# requires RouterOS, version=7.12
#
# monitor and manage dns/doh with netwatch
# https://git.eworm.de/cgit/routeros-scripts/about/doc/netwatch-dns.md

:local 0 [ :jobname ];
:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:global CertificateAvailable;
:global EitherOr;
:global LogPrintExit2;
:global ParseKeyValueStore;
:global ScriptLock;

$ScriptLock $0;

:local SettleTime (5m30s - [ /system/resource/get uptime ]);
:if ($SettleTime > 0s) do={
  $LogPrintExit2 info $0 ("System just booted, giving netwatch " . $SettleTime . " to settle.") true;
}

:local DnsServers ({});
:local DnsFallback ({});
:local DnsCurrent [ /ip/dns/get servers ];

:foreach Host in=[ /tool/netwatch/find where comment~"\\bdns\\b" status="up" ] do={
  :local HostVal [ /tool/netwatch/get $Host ];
  :local HostInfo [ $ParseKeyValueStore ($HostVal->"comment") ];

  :if ($HostInfo->"disabled" != true) do={
    :if ($HostInfo->"dns" = true) do={
      :set DnsServers ($DnsServers, $HostVal->"host");
    }
    :if ($HostInfo->"dns-fallback" = true) do={
      :set DnsFallback ($DnsFallback, $HostVal->"host");
    }
  }
}

:if ([ :len $DnsServers ] > 0) do={
  :if ($DnsServers != $DnsCurrent) do={
    $LogPrintExit2 info $0 ("Updating DNS servers: " . [ :tostr $DnsServers ]) false;
    /ip/dns/set servers=$DnsServers;
    /ip/dns/cache/flush;
  }
} else={
  :if ([ :len $DnsFallback ] > 0) do={
    :if ($DnsFallback != $DnsCurrent) do={
      $LogPrintExit2 info $0 ("Updating DNS servers to fallback: " . \
          [ :tostr $DnsFallback ]) false;
      /ip/dns/set servers=$DnsFallback;
      /ip/dns/cache/flush;
    }
  }
}

:local DohCurrent [ /ip/dns/get use-doh-server ];
:local DohServers ({});

:foreach Host in=[ /tool/netwatch/find where comment~"\\bdoh\\b" status="up" ] do={
  :local HostVal [ /tool/netwatch/get $Host ];
  :local HostInfo [ $ParseKeyValueStore ($HostVal->"comment") ];
  :local HostName [ /ip/dns/static/find where name address=($HostVal->"host") \
      (!type or type="A" or type="AAAA") !disabled !dynamic ];
  :if ([ :len $HostName ] > 0) do={
    :set HostName [ /ip/dns/static/get ($HostName->0) name ];
  }

  :if ($HostInfo->"doh" = true && $HostInfo->"disabled" != true) do={
    :if ([ :len ($HostInfo->"doh-url") ] = 0) do={
      :set ($HostInfo->"doh-url") ("https://" . [ $EitherOr $HostName ($HostVal->"host") ] . "/dns-query");
    }

    :if ($DohCurrent = $HostInfo->"doh-url") do={
      $LogPrintExit2 debug $0 ("Current DoH server is still up: " . $DohCurrent) true;
    }

    :set ($DohServers->[ :len $DohServers ]) $HostInfo;
  }
}

:if ([ :len $DohCurrent ] > 0) do={
  $LogPrintExit2 info $0 ("Current DoH server is down, disabling: " . $DohCurrent) false;
  /ip/dns/set use-doh-server="";
  /ip/dns/cache/flush;
}

:foreach DohServer in=$DohServers do={
  :if ([ :len ($DohServer->"doh-cert") ] > 0) do={
    :if ([ $CertificateAvailable ($DohServer->"doh-cert") ] = false) do={
      $LogPrintExit2 warning $0 ("Downloading certificate failed, trying without.") false;
    }
  }

  :local Data false;
  :do {
    :set Data ([ /tool/fetch check-certificate=yes-without-crl output=user \
      http-header-field=({ "accept: application/dns-message" }) \
      url=(($DohServer->"doh-url") . "?dns=" . [ :convert to=base64 ([ :rndstr length=2 ] . \
      "\01\00" . "\00\01" . "\00\00" . "\00\00" . "\00\00" . "\09doh-check\05eworm\02de\00" . \
      "\00\10" . "\00\01") ]) as-value ]->"data");
  } on-error={
    $LogPrintExit2 warning $0 ("Request to DoH server failed (network or certificate issue): " . \
      ($DohServer->"doh-url")) false;
  }

  :if ($Data != false) do={
    :if ([ :typeof [ :find $Data "doh-check-OK" ] ] = "num") do={
      /ip/dns/set use-doh-server=($DohServer->"doh-url") verify-doh-cert=yes;
      /ip/dns/cache/flush;
      $LogPrintExit2 info $0 ("Setting DoH server: " . ($DohServer->"doh-url")) true;
    } else={
      $LogPrintExit2 warning $0 ("Received unexpected response from DoH server: " . \
        ($DohServer->"doh-url")) false;
    }
  }
}
