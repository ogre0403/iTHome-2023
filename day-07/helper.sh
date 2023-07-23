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



# functuon create dhcp options for logical switch 
# arg1: subnet cidr 
# arg2: default gw
function create-dhcp-options {

    if [ $# -ne 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <subnet_cidr> <default_gw>"
        return 1
    fi  

    mac_addr=$(generate-mac)

    UUID=$(ovn-nbctl create dhcp_options cidr=$1 options="\"lease_time\"=\"3600\" \"router\"=\"$2\" \"server_id\"=\"$2\" \"server_mac\"=\"$mac_addr\"")

    echo $UUID
}


# create ovn logical switch and assign interface
# arg1: logical switch name
# arg2: dhcp_option uuid
# arg3: subnet cidr 
function create-ovn-ls-and-lsp {

    if [ $# -lt 1 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> [<dhcp_option_uuid> <subnet_cidr>]"
        return 1
    fi  

    if [ $# -eq 2 ]; then
        echo "Usage: ${FUNCNAME[0]} <logical switch name> [<dhcp_option_uuid> <subnet_cidr>]"
        return 1
    fi  

    ovn-nbctl ls-add $1

    if [ $# -eq 3 ]; then
        ovn-nbctl set logical_switch $1 other_config:subnet="$3" 
    fi

    ns_list=$(ip netns list | cut -d ' ' -f 1)
    for ns in $ns_list; do
        ovn-nbctl lsp-add $1 $1-$ns
        mac=$(ip netns exec $ns ip link show eth0 |grep link/ether | awk '{print $2}')

        if [ $# -eq 1 ]; then
            ovn-nbctl lsp-set-addresses $1-$ns "$mac"
        fi

        if [ $# -eq 3 ]; then
            ovn-nbctl lsp-set-addresses $1-$ns "$mac dynamic"
            ovn-nbctl lsp-set-dhcpv4-options $1-$ns $2
        fi

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