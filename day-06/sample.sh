#!/bin/bash

source helper.sh

# MUST use 192.168.10.0/24
create-ns ns1 192.168.10.100
create-ovn-ls-and-lsp   ls0
assign-iface-to-ovn-lsp ls0 ns1

add-localnet-port ls0 flat0

# MUST use eth2
add-bridge-mapping eth2 flat0
