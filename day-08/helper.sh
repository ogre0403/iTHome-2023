#!/bin/bash


add_veth_port() {
    name=$1
    mac=$2
    ip=$3
    iface_id=$4

    ip netns add $name
    ip link add veth-$name type veth peer name veth-$name-br
    ip link set veth-$name-br up
    ip link set veth-$name netns $name
    ip netns exec $name ip link set veth-$name name eth0
    ip netns exec $name ip addr add local $ip/24 dev eth0
    ip netns exec $name ip link set eth0 address $mac
    ip netns exec $name ip link set eth0 up
    ovs-vsctl add-port br-int veth-$name-br
    ovs-vsctl set Interface veth-$name-br external_ids:iface-id=$iface_id
}

