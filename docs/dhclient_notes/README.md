Policy Based Routing
===

This directory contains debugging information for policy based routing on
CentOS 8.2.  See
https://github.com/openinfrastructure/terraform-google-multinic/issues/10

The following script intercepts calls to the `ip` command to create a checklist
to see which commands break the policy based routing.

```
#! /bin/bash
#
read -a st < /proc/$$/stat
read -a ppid < /proc/${st[3]}/stat
file=$(printf '/tmp/%06d_' $$)
/jeff/ip route list table all > ${file}_01_before.txt
echo "ip $@" > ${file}_02_command.txt
/jeff/ip "$@"
rval=$?
echo "rval=${rval}" > ${file}_03_rval.txt
/jeff/ip route list table all > ${file}_04_after.txt

# Write the checklist
echo " * [ ] \`$0 $*\` (rval=${rval}) [PPID=${st[3]} ${ppid[1]}]" >> /tmp/jeff.txt

exit $rval
```
