Initial commands
================

[⬅️ Go back to main README](README.md)

> ⚠️ **Warning**: These command are inteneded for initial setup. If you are
> not aware of the procedure please follow
> [the long way in detail](README.md#the-long-way-in-detail).

Run the complete base installation:

    {
      /tool/fetch "https://git.eworm.de/cgit/routeros-scripts/plain/certs/E1.pem" dst-path="letsencrypt-E1.pem" as-value;
      :delay 1s;
      /certificate/import file-name=letsencrypt-E1.pem passphrase="";
      :if ([ :len [ /certificate/find where fingerprint="46494e30379059df18be52124305e606fc59070e5b21076ce113954b60517cda" or fingerprint="69729b8e15a86efc177a57afb7171dfc64add28c2fca8cf1507e34453ccb1470" ] ] != 2) do={
        :error "Something is wrong with your certificates!";
      };
      /file/remove "letsencrypt-E1.pem";
      :delay 1s;
      /system/script/set name=("global-config-overlay-" . [ /system/clock/get date ] . "-" . [ /system/clock/get time ]) [ find where name="global-config-overlay" ];
      :foreach Script in={ "global-config"; "global-config-overlay"; "global-functions" } do={
        /system/script/remove [ find where name=$Script ];
        /system/script/add name=$Script owner=$Script source=([ /tool/fetch check-certificate=yes-without-crl ("https://git.eworm.de/cgit/routeros-scripts/plain/" . $Script . ".rsc") output=user as-value]->"data");
      };
      /system/script { run global-config; run global-functions; };
      /system/scheduler/remove [ find where name="global-scripts" ];
      /system/scheduler/add name="global-scripts" start-time=startup on-event="/system/script { run global-config; run global-functions; }";
      :global CertificateNameByCN;
      $CertificateNameByCN "E1";
      $CertificateNameByCN "ISRG Root X2";
    };

Then continue setup with
[scheduled automatic updates](README.md#scheduled-automatic-updates) or
[editing configuration](README.md#editing-configuration).

## Fix existing installation

The [initial commands](#initial-commands) above allow to fix an existing
installation in case it ever breaks. If `global-config-overlay` did exist
before it is renamed with a date and time suffix (like
`global-config-overlay-2024-01-25-09:33:12`). Make sure to restore the
configuration overlay if required.

---
[⬅️ Go back to main README](README.md)  
[⬆️ Go back to top](#top)
