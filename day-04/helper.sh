#!/bin/bash


# create function accept two args, this will run on EACH hypervisor
# arg1: namespace name
# arg2: ip address
function create-ns {
    ip netns add $1
    ip link add veth-$1 type veth peer name veth-$1-br
    ip link set veth-$1-br up
    ip link set veth-$1 netns $1
    ip netns exec $1 ip link set veth-$1 name eth0
    ip netns exec $1 ip addr add local $2/24 dev eth0
    ip netns exec $1 ip link set eth0 up
}


# create ovn logical switch and assign interface, this will run ONLY on controller
# arg1: logical switch name
function create-ovn-ls-and-lsp {
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


# function to assign interface to ovn logical switch, this will run on EACH hypervisor
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
    
}


# teardown multipe namespaces
# arg1: list of namespace name
function teardown-ns {
    for i in $@; do
        ip netns del $i
    done
}