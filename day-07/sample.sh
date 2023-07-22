#!/bin/bash

source helper.sh

create-ns ns1
create-ns ns2

uuid=$(create-ovn-ls ls0 10.0.0.0/24 10.0.0.1)

create-dynamic-lsp ls0 $uuid ns1
create-dynamic-lsp ls0 $uuid ns2

assign-iface-to-ovn-lsp ls0 ns1
assign-iface-to-ovn-lsp ls0 ns2

ip netns exec ns1 dhclient
ip netns exec ns1 ip a

ip netns exec ns2 dhclient      
ip netns exec ns2 ip a


