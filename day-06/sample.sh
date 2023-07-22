#!/bin/bash

source helper.sh

export EXTERNAL_GW=10.0.2.2
export FLOATING_IP=10.0.2.200
export EXTERNAL_IP=10.0.2.100

create-ns ns1 192.168.100.100 192.168.100.254
create-ovn-ls-and-lsp   ls0 ns1
assign-iface-to-ovn-lsp ls0 ns1


create-ovn-ls-and-lsp   ls-out
add-localnet-port ls-out flat0

# run on hypervisor
add-bridge-mapping eth0 flat0


create-ovn-lr r0
connect-ovn-lr-to-ls r0 ls0   192.168.100.254
connect-ovn-lr-to-ls r0 ls-out ${EXTERNAL_IP}


#arg1: logical router name
#arg2: external switch name
#arg3: external node name
#arg4: external gateway ip address
set_outgoing_chassis  r0 ls-out hypervisor ${EXTERNAL_GW}


#arg1: logical router name
#arg2: internal network CIDR
#arg3: external ip address
set_snat_rule r0 192.168.100.0/24 ${EXTERNAL_IP}


# arg1: logical router name
# arg2: internal ip address
# arg3: external ip address
set_dnat_rule r0 192.168.100.100 ${FLOATING_IP}