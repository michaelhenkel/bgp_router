#!/bin/bash
. read_ini.sh
read_ini $1 main
name=${INI__main__name}
as=${INI__main__as}
routerid=${INI__main__routerid}
bgp_conf="hostname $name"$'\n'
bgp_conf+="log stdout"$'\n'
bgp_conf+="password zebra"$'\n'
bgp_conf+="enable password zebra"$'\n'
bgp_conf+="router bgp $as"$'\n'
bgp_conf+=" bgp router-id $routerid"$'\n'
bgp_conf+=" redistribute connected"$'\n'
bgp_conf+=" maximum-paths 2"$'\n'
read_ini $1 neighbors
for i in ${INI__ALL_VARS}
do
  neighbor=`echo ${i} | awk -F"__" '{print $3}'|tr '_' '.'`
  bgp_conf+=" neighbor $neighbor remote-as ${!i}"$'\n'
done
bgp_conf+=" exit"$'\n'
bgp_conf+="line vty"$'\n'
echo "$bgp_conf"
if [ ! -d "/etc/quagga/${name}" ]; then
  mkdir /etc/quagga/${name}
fi
echo "$bgp_conf" > /etc/quagga/${name}/bgpd.conf
cat <<EOF > /etc/quagga/${name}/zebra.conf
hostname Router
password zebra
enable password zebra
EOF
cat <<EOF > /etc/quagga/${name}/vtysh.conf
service integrated-vtysh-config
username root nopassword
EOF
chown quagga:quagga /etc/quagga/${name}
chown quagga:quagga /etc/quagga/${name}/bgpd.conf
chown quagga:quagga /etc/quagga/${name}/zebra.conf
chown quagga:quaggavty /etc/quagga/${name}/vtysh.conf

if [ -f /var/run/netns/${name} ]; then
  for i in `ip netns pids ${name}`
  do
    kill -9 $i
  done
  ip netns del ${name}
fi
for i in `ps -efa |grep /usr/lib/quagga/bgpd |grep -v grep |grep ${name}|awk '{print $2}'`
do
  kill -9 $i
done

ip netns add ${name}

read_ini $1 interfaces
for i in ${INI__ALL_VARS}
do
  interface=`echo ${i} | awk -F"__" '{print $3}'`
  ip link sh dev ${name}-${interface}-h 2> /dev/null
  if [ $? -eq 0 ];then
    ip link del ${name}-${interface}-h
  fi
  ip link add ${name}-${interface} type veth peer name ${name}-${interface}-h
  ip link set ${name}-${interface} netns ${name}
  ip link set ${name}-${interface}-h up
  ip netns exec ${name} ip link set ${name}-${interface} up
  ip netns exec ${name} ip addr add ${!i} dev ${name}-${interface}
  brctl addif cable ${name}-${interface}-h
done
ip netns exec ${name} /usr/lib/quagga/zebra -d -f /etc/quagga/${name}/zebra.conf -i /etc/quagga/${name}/zebra.pid -z /etc/quagga/${name}/zebra.socket 
ip netns exec ${name} /usr/lib/quagga/bgpd -d -f /etc/quagga/${name}/bgpd.conf -i /etc/quagga/${name}/bgpd.pid -z /etc/quagga/${name}/zebra.socket
