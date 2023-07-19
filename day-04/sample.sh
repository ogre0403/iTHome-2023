#!/bin/bash

source helper.sh

create-ns ns1 192.168.1.1 192.168.1.254
create-ns ns2 192.168.1.2 192.168.1.254
create-ns ns3 10.10.0.1 10.10.0.254

create-ovn-ls-and-lsp sw1 ns1 ns2
assign-iface-to-ovn-lsp sw1 ns1 ns2

create-ovn-ls-and-lsp sw2 ns3
assign-iface-to-ovn-lsp sw2 ns3

create-ovn-lr lr1
connect-ovn-lr-to-ls lr1 sw1 192.168.1.254
connect-ovn-lr-to-ls lr1 sw2 10.10.0.254
