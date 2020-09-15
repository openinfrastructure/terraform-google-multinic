NetworkManager-dispatcher-routing-rules
===

Copy these files into their location below.  Note the pre-up.d and no-wait.d
files are symlinks to `../no-wait.d/10-ifcfg-rh-routes.sh`

See [15.6. Creating static routes configuration files in key-value-format when
using the legacy network scripts][routescript] for the "new" format of the
`/etc/sysconfig/network-scripts/route-eth{0,1}` files.

NOTE: This multinic solution uses the alternative format, which passes the line
directly to the ip command.

The files in this directory are copied from the
[NetworkManager-dispatcher-routing-rules-1:1.22.8-5.el8_2.noarch][rpm].  They
are included here to optionally avoid having to execute `yum` to configure a
multinic instance.  The intent is to speed up auto-healing and support multinic
instances which lack connectivity to online package repositories.

```
# sudo rpm -qil NetworkManager-dispatcher-routing-rules-1:1.22.8-5.el8_2.noarch
Name        : NetworkManager-dispatcher-routing-rules
Epoch       : 1
Version     : 1.22.8
Release     : 5.el8_2
Architecture: noarch
Install Date: Tue 15 Sep 2020 03:13:37 AM UTC
Group       : System Environment/Base
Size        : 3840
License     : GPLv2+ and LGPLv2+
Signature   : RSA/SHA256, Fri 07 Aug 2020 10:45:54 PM UTC, Key ID 05b555b38483c65d
Source RPM  : NetworkManager-1.22.8-5.el8_2.src.rpm
Build Date  : Tue 21 Jul 2020 06:02:31 PM UTC
Build Host  : aarch64-04.mbox.centos.org
Relocations : (not relocatable)
Packager    : CentOS Buildsys <bugs@centos.org>
Vendor      : CentOS
URL         : http://www.gnome.org/projects/NetworkManager/
Summary     : NetworkManager dispatcher file for advanced routing rules
Description :
This adds a NetworkManager dispatcher file to support networking
configurations using "/etc/sysconfig/network-scripts/rule-NAME" files
(eg, to do policy-based routing).
/usr/lib/NetworkManager/dispatcher.d/10-ifcfg-rh-routes.sh
/usr/lib/NetworkManager/dispatcher.d/no-wait.d/10-ifcfg-rh-routes.sh
/usr/lib/NetworkManager/dispatcher.d/pre-up.d/10-ifcfg-rh-routes.sh
```

[routescript]: https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/configuring-a-static-route_configuring-and-managing-networking#creating-static-routes-configuration-files-in-key-value-format-when-using-the-legacy-network-scripts_configuring-a-static-route
