#!/bin/bash

# Copyright (c) 2015, Excentis nv
# All rights reserved.
#
# Author: Tim De Backer <tim.debacker@excentis.com>
#
# This script will configure the impairment node.
#
# It applies impairment configurations between two interfaces of a specified 'bypassX', by doing the following:
#   * Create a VLAN tagged interface on both interfaces (or work with the native interface if no VLAN is specified).
#   * Bridge the virtual interfaces with equal VLAN IDs on the two interfaces (or the interfaces themselves) together.
#   * Apply the specified configuration to the incoming traffic.
#
# If no configuration is specified, all impairment configurations are parsed from 'tc.conf'.
# If a configuration is specified, only that impairment is applied.
#
##

# Set the management interface of this impairment node
manif="eth5"

########################
### Input validation ###
########################

SCRIPTDIR=$(dirname $0)

# Test argument count
if test $# -lt 2; then
    echo "Error: Wrong number of arguments (2 to apply tc.conf or clear, 3 to apply explicit conf)"
    echo "  syntax: tc.sh apply <bypass0|1> [<impconf>]"
    echo "  syntax: tc.sh clear <bypass0|1>"
    exit 1
fi

# Saving argument values to variables
action=$1
shift
bypass=$1
shift

# Test if known action
if test "$action" != "apply" -a "$action" != "clear" ; then
    echo "Error: Invalid arguments, action '$action' unknown"
    echo "  syntax: tc.sh apply <bypass0|1> [<impconf>]"
    echo "  syntax: tc.sh clear <bypass0|1>"
    exit 1
fi

# Test if known bypass
if test "$bypass" = "bypass0"; then
    ifds="eth0"
    ifus="eth1"
elif test "$bypass" = "bypass1"; then
    ifds="eth2"
    ifus="eth3"
else
    echo "Error: Invalid arguments, bypass '$bypass' unknown"
    echo "  syntax: tc.sh apply <bypass0|1> [<impconf>]"
    echo "  syntax: tc.sh clear <bypass0|1>"
    exit 1
fi

# Test if running as root
if test $UID -ne 0 ; then
    echo "Error: This script should be executed as a superuser"
    exit 1
fi

#######################################
### Clear impairment configuration  ###
#######################################

echo "Clearing previous configuration"

echo -n " - Removing all $bypass bridges..."
bridges=`ifconfig -a | grep -E "^$bypass" | cut --delimiter=' '  -f1`
for bridge in $bridges
do
    ifconfig $bridge down
    brctl delbr $bridge >/dev/null 2>&1
done
echo "done"

echo -n " - Removing all existing impairment configurations on the (virtual) $bypass interfaces..."
interfaces=`ifconfig -a | grep -E "^(${ifds}|${ifus})" | cut --delimiter=' ' -f1`
for interface in $interfaces
do
    tc qdisc del dev $interface root >/dev/null 2>&1
done
echo "done"

echo -n " - Removing all virtual interfaces on the $bypass interfaces..."
vinterfaces=`ifconfig -a | grep -E "^(${ifds}|${ifus})\." | cut --delimiter=' ' -f1`
for vinterface in $vinterfaces
do
    ifconfig $vinterface down
    vconfig rem $vinterface >/dev/null >/dev/null 2>&1
done
echo "done"

echo -n " - Removing default (non-virtual) $bypass bridge..."
ifconfig $bypass down >/dev/null 2>&1
brctl delbr bypass0 >/dev/null 2>&1
echo "done"

echo -n " - Bringing $bypass interfaces down..."
ifconfig $ifds down >/dev/null 2>&1
ifconfig $ifus down >/dev/null 2>&1
echo "done"

if test "$action" = "clear" ; then
    echo -n "Restarting network..."
    /etc/init.d/networking restart >/dev/null
    echo "done"
    exit 0
fi

########################################
### Create impairment configuration  ###
########################################

echo -n "Creating ethernet bridge..."
brctl addbr $bypass
brctl addif $bypass $ifds
brctl addif $bypass $ifus
brctl setfd $bypass 0
brctl sethello $bypass 2
brctl setmaxage $bypass 12
brctl stp $bypass off
echo "done"

echo -n "Bringing default (non-virtual) $bypass bridge online..."
ifconfig $ifds up
ifconfig $ifus up
ifconfig $bypass up
echo "done"

if test "x$@" = "x"; then
    echo "Using provided impairment configuration tc.conf"
    impairments=`cat ${SCRIPTDIR}/tc.conf`
else
    echo "Using provided impairment configuration '$@'"
    impairments="$@"
fi

# Parse config file
while IFS=';' read vlan tcconf1 tcconf2
do
    # Ignore comment lines
    echo "$vlan" | grep "^ *#" >/dev/null 2>&1 && continue
    # Ignore empty lines
    test -z "$vlan" -a -z "$tcconf1" -a -z "$tcconf2" && continue
    # Validate VLAN ID field
    if ! `echo "$vlan" | grep "^[0-9]*$" >/dev/null 2>&1` ; then
        echo "Warning: Invalid VLAN '$vlan', skipping this entry"
        continue
    fi

    if test -z "$tcconf2" ; then
        if test -n "$vlan"; then
            echo "Configuring VLAN $vlan with bidirectional impairment config:"
        else
            echo "Configuring native (non-VLAN) with bidirectional impairment config:"
        fi
        echo "   * '$tcconf1'"
        echo "   * '$tcconf1'"
        tcconfds=$tcconf1
        tcconfus=$tcconf1
    else
        if test -n "$vlan"; then
            echo "Configuring VLAN $vlan with unidirectional impairment config:"
        else
            echo "Configuring native (non-VLAN) with unidirectional impairment config:"
        fi
        echo "   * '$tcconf1'"
        echo "   * '$tcconf2'"
        tcconfds=$tcconf1
        tcconfus=$tcconf2
    fi

    if test -n "$vlan"; then
        echo -n " - Creating VLAN interfaces..."
        vconfig add $ifds $vlan > /dev/null
        vconfig add $ifus $vlan > /dev/null
        vlanifds="${ifds}.${vlan}"
        vlanifus="${ifus}.${vlan}"
        echo "done"

        echo -n " - Creating bridge between the VLAN interfaces..."
        vlanbr="${bypass}.${vlan}"
        brctl addbr $vlanbr
        brctl addif $vlanbr $vlanifds
        brctl addif $vlanbr $vlanifus
        brctl setfd $vlanbr 0
        brctl sethello $vlanbr 2
        brctl setmaxage $vlanbr 12
        brctl stp $vlanbr off
        echo "done"

        echo -n " - Bringing VLAN bridge online..."
        ifconfig $vlanifds up
        ifconfig $vlanifus up
        ifconfig $vlanbr up
       echo "done"
    else
        vlanifds="${ifds}"
        vlanifus="${ifus}"
    fi

    echo " - Applying impairment configuration:"
    # Create 2-class priority map, with all traffic redirected to the second class (id 1)
    echo -n "    * Constructing root handler..."
    tc qdisc add dev $vlanifds root handle 1: prio bands 2 priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
    tc qdisc add dev $vlanifus root handle 1: prio bands 2 priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1
    echo "done"

    # First class (prior, id 0) uses normal queuing (fifo)
    echo -n "    * Constructing non-impaired queue for dhcp, icmp and arp traffic..."
    tc qdisc add dev $vlanifds parent 1:1 handle 10: pfifo limit 1000
    tc qdisc add dev $vlanifus parent 1:1 handle 10: pfifo limit 1000
    echo "done"

    # Second class (default, id 1) uses the specific impairment configuration!
    # Note two chained impairments are allowed
    echo -n "    * Creating impaired queue for other downstream traffic..."
    qdiscds1=`echo "${tcconfds}," | cut -f1 -d','`
    tc qdisc add dev $vlanifds parent 1:2 handle 20: $qdiscds1
    echo "done"
    qdiscds2=`echo "${tcconfds}," | cut -f2 -d','`
    if test "$qdiscds2" ; then
        echo -n "    * Creating additional impaired queue for other downstream traffic..."
        tc qdisc add dev $vlanifds parent 20: handle 21: $qdiscds2
        echo "done"
    fi
    echo -n "    * Creating impaired queue for other upstream traffic..."
    qdiscus1=`echo "${tcconfus}," | cut -f1 -d','`
    tc qdisc add dev $vlanifus parent 1:2 handle 20: $qdiscus1
    echo "done"
    qdiscus2=`echo "${tcconfus}," | cut -f2 -d','`
    if test "$qdiscus2" ; then
        echo -n "    * Creating additional impaired queue for other upstream traffic..."
        tc qdisc add dev $vlanifus parent 20: handle 21: $qdiscus2
        echo "done"
    fi

    echo -n " - Applying traffic filters..."
    for vlanif in $vlanifds $vlanifus
    do
        # ARP
        tc filter add dev $vlanif parent 1: prio 1 protocol arp u32 \
            match u32 0 0 \
            flowid 1:1

        # ICMP
        tc filter add dev $vlanif parent 1: prio 2 protocol ip u32 \
            match ip protocol 1 0xff \
            flowid 1:1

        # IGMP
        tc filter add dev $vlanif parent 1: prio 3 protocol ip u32 \
            match ip protocol 2 0xff \
            flowid 1:1

        # DHCP
        tc filter add dev $vlanif parent 1: prio 4 protocol ip u32 \
            match ip protocol 17 0xff  \
            match ip dport 67 0xffff \
            flowid 1:1
        tc filter add dev $vlanif parent 1: prio 4 protocol ip u32 \
            match ip protocol 17 0xff  \
            match ip dport 68 0xffff \
            flowid 1:1

        # ICMPv6
        tc filter add dev $vlanif parent 1: prio 5 protocol ipv6 u32 \
            match ip6 protocol 58 0xff \
            flowid 1:1

        # ICMPv6 (after a 8-byte IPv6 header extension, which itself has next header field at byte 0)
        tc filter add dev $vlanif parent 1: prio 6 protocol ipv6 u32 \
            match u8 58 0xff at nexthdr+0 \
            flowid 1:1

        # DHCPv6
        tc filter add dev $vlanif parent 1: prio 7 protocol ipv6 u32 \
            match ip6 protocol 17 0xff  \
            match ip6 dport 546 0xffff \
            flowid 1:1
        tc filter add dev $vlanif parent 1: prio 7 protocol ipv6 u32 \
            match ip6 protocol 17 0xff  \
            match ip6 dport 547 0xffff \
            flowid 1:1
    done
    echo "done"
done << HERE
`echo "$impairments"`
HERE

echo -n "Restarting network..."
/etc/init.d/networking restart >/dev/null
echo "done"

exit 0
