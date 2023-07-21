#!/bin/bash

# create function accept two args
# arg1: namespace name
# arg2: ip address
# arg3: default gw ip address
function create-ns {

    if [ $# -lt 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <namespace name> <ip address> [<default gw ip address>]"
        return 1
    fi

    ip netns add $1
    ip link add veth-$1 type veth peer name veth-$1-br
    ip link set veth-$1-br up
    ip link set veth-$1 netns $1
    ip netns exec $1 ip link set veth-$1 name eth0
    ip netns exec $1 ip addr add local $2/24 dev eth0
    ip netns exec $1 ip link set eth0 up

    if [ $# -eq 3 ]; then
        ip netns exec $1 ip r add default via $3
    fi
}


# create ovn logical switch and logical port
# arg1: logical switch name
function create-ovn-ls-and-lsp {

    if [ $# -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> <list of namespace name>"
        return 1
    fi

    hypervisor_list=(192.168.33.10 192.168.33.20)

    ovn-nbctl ls-add $1

    for hypervisor in ${hypervisor_list[@]}; do
        ns_list=$(ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ip netns list | cut -d ' ' -f 1)
        for ns in $ns_list; do
            port_mac=$(ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ip netns exec $ns ip link show eth0 |grep link/ether | awk '{print $2}')
            ovn-nbctl lsp-add $1 $1-$ns
            ovn-nbctl lsp-set-addresses $1-$ns ${port_mac}
        done
    done
}

# function to assign interface to ovn logical switch
# arg1: logical switch name
# arg2: list of namespace name
function assign-iface-to-ovn-lsp {
    
    if [ $# -lt 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> <list of namespace name>"
        return 1
    fi

    sw=$1
    shift
    for ns in $@; do
        ovs-vsctl add-port br-int veth-$ns-br
        ovs-vsctl set Interface veth-$ns-br external_ids:iface-id=$sw-$ns
    done
}


# create localnet on a given logical switch
# arg1: logical switch name
# arg2: nwtwork name
function add-localnet-port {

    if [ $# -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical_switch_name> <network_name>"
        return 1
    fi

    localnet_port_name=$1-localnet 
    ovn-nbctl lsp-add $1 $localnet_port_name
    ovn-nbctl lsp-set-addresses $localnet_port_name unknown 
    ovn-nbctl lsp-set-type $localnet_port_name localnet 
    ovn-nbctl lsp-set-options $localnet_port_name network_name=$2

}

# crate 
# arg1: interface name
# arg2: network name
function add-bridge-mapping {

    if [ $# -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <interface_name> <network_name>"
        return 1
    fi

    br_name=br-$1
    ovs-vsctl add-br $br_name
    ovs-vsctl add-port $br_name $1
    ip link set $1 up 
    ovs-vsctl set Open_vSwitch . external-ids:ovn-bridge-mappings=$2:$br_name

}

# teardown logical switch
# arg1: logical switch name
# arg2: interface name
function teardown-ovn-ls {

    if [ $# -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> <interface_name>"
        return 1
    fi

    ovn-nbctl ls-del $1

    hypervisor_list=(192.168.33.10 192.168.33.20)

    for hypervisor in ${hypervisor_list[@]}; do
        ns_list=$(ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ip netns list | cut -d ' ' -f 1)
        for ns in $ns_list; do
            ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ovs-vsctl --if-exists --with-iface del-port br-int veth-$ns-br
        done
        ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ovs-vsctl del-br br-$2
    done
}

# teardown multipe namespaces
# arg1: list of namespace name
function teardown-ns {
    for i in $@; do
        ip netns del $i
    done
}


