#!/bin/bash


function generate-mac {
    printf '02:00:%02x:%02x:%02x:%02x\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]
}

# create function accept two args
# arg1: namespace name
# arg2: ip address
# arg3: default gw ip address
function create-ns {

    if [ $# -lt 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <namespace name> <ip address> [<default gw ip address>]"
        return 1
    fi

    ip netns add $1
    ip link add veth-$1 type veth peer name veth-$1-br
    ip link set veth-$1-br up
    ip link set veth-$1 netns $1
    ip netns exec $1 ip link set veth-$1 name eth0
    
    if [ $# -ge 2 ]; then
        ip netns exec $1 ip addr add local $2/24 dev eth0
    fi
    
    ip netns exec $1 ip link set eth0 up

    if [ $# -eq 3 ]; then
        ip netns exec $1 ip r add default via $3
    fi
}

# function to create bridge
# arg1: bridge name
function create-br {
    brctl addbr $1
    ip link set $1 up

}

# function to assign interface to bridge
# arg1: bridge name
function assign-iface-to-br {
    veth_pair=$(ip -o link show type veth | awk -F': ' '{print $2}' | cut -d @ -f 1)
    for i in $veth_pair; do
        brctl addif $1 $i
    done
}


# create ovn logical switch and assign interface
# arg1: logical switch name
function create-ovn-ls-and-lsp {
    ovn-nbctl ls-add $1

    ns_list=$(ip netns list | cut -d ' ' -f 1)
    for ns in $ns_list; do
        ovn-nbctl lsp-add $1 $1-$ns
        ovn-nbctl lsp-set-addresses $1-$ns $(ip netns exec $ns ip link show eth0 |grep link/ether | awk '{print $2}')
    done

}

# function to assign interface to ovn logical switch
# arg1: logical switch name
function assign-iface-to-ovn-lsp {
    ns_list=$(ip netns list | cut -d ' ' -f 1)

    for ns in $ns_list; do
        ovs-vsctl add-port br-int veth-$ns-br
        ovs-vsctl set Interface veth-$ns-br external_ids:iface-id=$1-$ns
    done
}


# teardown bridge
# arg1: bridge name
function teardown-br {
    ip link set $1 down
    brctl delbr $1
}

# teardown logical switch
# arg1: logical switch name
function teardown-ovn-ls {
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