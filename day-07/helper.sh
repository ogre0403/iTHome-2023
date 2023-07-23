#!/bin/bash


function generate-mac {
    printf '02:00:%02x:%02x:%02x:%02x\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256] $[RANDOM%256]
}

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
# arg2: list of namespace name
function create-ovn-ls-and-lsp {

    if [ $# -lt 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> [<list of namespace name>]"
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

    # assign ip to bridge, otherwise it will not be able to communicate with external network
    # https://medium.com/@john.lin/%E9%80%8F%E9%81%8E-ovs-bridge-%E5%8F%8A-docker-%E8%A6%AA%E6%89%8B%E6%89%93%E9%80%A0-sdn-%E5%AF%A6%E9%A9%97%E7%B6%B2%E8%B7%AF-%E5%9B%9B-%E8%A8%AD%E5%AE%9A%E5%A4%96%E9%83%A8%E9%80%A3%E7%B6%B2-b0e96d9d2ee1
    ifconfig $1 0
    dhclient $br_name
}

#arg1: logical router name
#arg2: external switch name
#arg3: external node name
#arg4: external gateway ip address
function set_outgoing_chassis {
    CHASSIS=`ovn-sbctl --columns=name -f json  find chassis hostname=$3 | jq -r .data[][]`
    ovn-nbctl lrp-set-gateway-chassis $1-$2 ${CHASSIS}
    ovn-nbctl lr-route-add $1 "0.0.0.0/0" $4
}

#arg1: logical router name
#arg2: internal network CIDR
#arg3: external ip address
function set_snat_rule {
    # CHASSIS=`ovn-sbctl --columns=name -f json  find chassis hostname=$3 | jq -r .data[][]`
    # ovn-nbctl lrp-set-gateway-chassis $1-$2 ${CHASSIS}
    ovn-nbctl -- --id=@nat create nat type="snat" logical_ip=$2 external_ip=$3 -- add logical_router $1 nat @nat
}


# arg1: logical router name
# arg2: internal ip address
# arg3: external ip address
function set_dnat_rule {
    ovn-nbctl -- --id=@nat create nat type="dnat_and_snat" logical_ip=$2 external_ip=$3 -- add logical_router $1 nat @nat
}


# teardown logical switch
# arg1: logical switch name
# arg2: interface name
function teardown-ovn-ls {

    if [ $# -lt 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> [<interface_name>]"
        return 1
    fi

    ovn-nbctl ls-del $1

    hypervisor_list=(192.168.33.10 192.168.33.20)

    for hypervisor in ${hypervisor_list[@]}; do
        ns_list=$(ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ip netns list | cut -d ' ' -f 1)
        for ns in $ns_list; do
            ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ovs-vsctl --if-exists --with-iface del-port br-int veth-$ns-br
        done

        if [ $# -eq 2 ]; then
            ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ovs-vsctl del-br br-$2
        fi
    done
}

function teardown-ovn-lr {
    if [ $# -ne 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical router name>"
        return 1
    fi

    ovn-nbctl lr-del $1
}

# teardown multipe namespaces
# arg1: list of namespace name
function teardown-ns {
    for i in $@; do
        ip netns del $i
    done
}