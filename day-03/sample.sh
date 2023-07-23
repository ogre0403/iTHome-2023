#!/bin/bash

source helper.sh

create-ns ns1
create-ns ns2

uuid=$(create-dhcp-options 10.0.0.0/24 10.0.0.1)
create-ovn-ls-and-lsp ls0 $uuid 10.0.0.0/24
assign-iface-to-ovn-lsp ls0


ip netns exec ns1 dhclient
ip netns exec ns1 ip a

ip netns exec ns2 dhclient      
ip netns exec ns2 ip a


