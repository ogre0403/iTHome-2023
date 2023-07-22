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




# functuon create dynamic ovn logical switch 
# arg1: logical switch name
# arg2: subnet cidr 
# arg3: default gw
function create-ovn-ls {
    if [ $# -lt 3 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> <subnet_cidr>"
        return 1
    fi

    mac_addr=$(generate-mac)

    sw=$1
    ovn-nbctl ls-add $sw 
    ovn-nbctl set logical_switch $sw other_config:subnet="$2" 

    UUID=$(ovn-nbctl create dhcp_options cidr=$2 options="\"lease_time\"=\"3600\" \"router\"=\"$3\" \"server_id\"=\"$3\" \"server_mac\"=\"$mac_addr\"")

    echo $UUID
}




# create ovn logical switch and logical port
# arg1: logical switch name
# arg2: dhcp_option uuid
# arg3: list of namespace name
function create-dynamic-lsp {

    if [ $# -lt 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> <dhcp_option_uuid> [<list of namespace name>]"
        return 1
    fi  

    sw=$1
    shift

    dhcp_uuid=$1
    shift

    for ns in "$@"; do
        ovn-nbctl lsp-add $sw $sw-$ns
        mac=$(ip netns exec $ns ip link show eth0 |grep link/ether | awk '{print $2}')
        ovn-nbctl lsp-set-addresses $sw-$ns "$mac dynamic"
        ovn-nbctl lsp-set-dhcpv4-options $sw-$ns $dhcp_uuid
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


# teardown logical switch
# arg1: logical switch name
function teardown-ovn-ls {
    hypervisor_list=(192.168.33.10 192.168.33.20)

    ovn-nbctl ls-del $1


    for hypervisor in ${hypervisor_list[@]}; do
        ns_list=$(ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ip netns list | cut -d ' ' -f 1)
        for ns in $ns_list; do
            ssh -oStrictHostKeyChecking=no vagrant@$hypervisor sudo ovs-vsctl --if-exists --with-iface del-port br-int veth-$ns-br
        done
    done

    for dhcp in $(ovn-nbctl  dhcp-options-list) ; do
        ovn-nbctl destroy dhcp_options $dhcp
    done
    
}

# teardown multipe namespaces
# arg1: list of namespace name
function teardown-ns {
    for i in $@; do
        ip netns del $i
    done
}