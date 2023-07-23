#!/bin/bash

# import helper function from helper.sh
source helper.sh

create-ns ns1 192.168.1.1
create-ns ns2 192.168.1.2

create-ovn-ls-and-lsp ls0

assign-iface-to-ovn-lsp  ls0