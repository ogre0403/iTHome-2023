#!/bin/bash

# create function to generate random mac address
function generate-mac {
    printf '02:00:%02x:%02x:%02x:%02x\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]
}


# create function accept two args
# arg1: namespace name
# arg2: ip address
# arg3: default gw ip address
function create-ns {

    if [ $# -ne 3 ]; then
        echo "Usage: ${FUNCNAME[0]} <namespace name> <ip address> <default gw ip address>"
        return 1
    fi

    ip netns add $1
    ip link add veth-$1 type veth peer name veth-$1-br
    ip link set veth-$1-br up
    ip link set veth-$1 netns $1
    ip netns exec $1 ip link set veth-$1 name eth0
    ip netns exec $1 ip addr add local $2/24 dev eth0
    ip netns exec $1 ip link set eth0 up
    ip netns exec $1 ip r add default via $3
}


# create ovn logical switch and logical port
# arg1: logical switch name
# arg2: list of namespace name
function create-ovn-ls-and-lsp {

    if [ $# -lt 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> <list of namespace name>"
        return 1
    fi

    sw=$1
    ovn-nbctl ls-add $sw
    
    shift
    for ns in "$@"; do
        ovn-nbctl lsp-add $sw $sw-$ns
        ovn-nbctl lsp-set-addresses $sw-$ns $(ip netns exec $ns ip link show eth0 |grep link/ether | awk '{print $2}')
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

# create ovn logical router
# arg1: logical router name
function create-ovn-lr {

    if [ $# -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical router name>"
        return 1
    fi
    ovn-nbctl lr-add $1
}

# connect ovn logical router to ovn logical switch
# arg1: logical router name
# arg2: logical switch name
# arg3: gw ip address on logical router
function connect-ovn-lr-to-ls {

    if [ $# -ne 3 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical router name> <logical switch name> <gw ip address>"
        return 1
    fi
    
    # generate mac address for logical router port
    mac_addr=$(generate-mac)

    # logical router port
    ovn-nbctl lrp-add $1 $1-$2 $mac_addr $3/24

    # logical switch port
    ovn-nbctl lsp-add $2 $2-$1
    ovn-nbctl lsp-set-type $2-$1 router
    ovn-nbctl lsp-set-addresses $2-$1 "$mac_addr $3"
    ovn-nbctl lsp-set-options $2-$1 router-port=$1-$2
}


# teardown ovn logical router
# arg1: logical router name
function teardown-ovn-lr {

    if [ $# -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical router name>"
        return 1
    fi

    ovn-nbctl lr-del $1
}

# teardown logical switch
# arg1: logical switch name
function teardown-ovn-ls {

    if [ $# -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name>"
        return 1
    fi

    ovn-nbctl ls-del $1
    ns_list=$(ip netns list | cut -d ' ' -f 1)

    for ns in $ns_list; do
        ovs-vsctl --if-exists --with-iface del-port br-int veth-$ns-br
    done
}


# teardown multipe namespaces
# arg1: list of namespace name
function teardown-ns {
    for i in $@; do
        ip netns del $i
    done
}