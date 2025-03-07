#!rsc by RouterOS
# RouterOS script: global-wait
# Copyright (c) 2020-2024 Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# requires RouterOS, version=7.12
#
# wait for global-functions to finish
# https://git.eworm.de/cgit/routeros-scripts/about/doc/global-wait.md

:local 0 [ :jobname ];
:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }
