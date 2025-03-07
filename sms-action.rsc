#!rsc by RouterOS
# RouterOS script: sms-action
# Copyright (c) 2018-2024 Christian Hesse <mail@eworm.de>
# https://git.eworm.de/cgit/routeros-scripts/about/COPYING.md
#
# requires RouterOS, version=7.12
#
# run action on received SMS
# https://git.eworm.de/cgit/routeros-scripts/about/doc/sms-action.md

:local 0 [ :jobname ];
:global GlobalFunctionsReady;
:while ($GlobalFunctionsReady != true) do={ :delay 500ms; }

:global SmsAction;

:global LogPrintExit2;
:global ValidateSyntax;

:local Action $action;

:if ([ :typeof $Action ] = "nothing") do={
  $LogPrintExit2 error $0 ("This script is supposed to run from SMS hook with action=...") true;
}

:local Code ($SmsAction->$Action);
:if ([ $ValidateSyntax $Code ] = true) do={
  :log info ("Acting on SMS action '" . $Action . "': " . $Code);
  :delay 1s;
  [ :parse $Code ];
} else={
  $LogPrintExit2 warning $0 ("The code for action '" . $Action . "' failed syntax validation!") false;
}
