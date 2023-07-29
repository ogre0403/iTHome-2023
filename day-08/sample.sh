source helper.sh


ovn-nbctl ls-add ls0

ovn-nbctl lsp-add ls0       ls0-ns1
ovn-nbctl lsp-set-addresses ls0-ns1 "00:00:00:aa:bb:10"

ovn-nbctl lsp-add ls0       ls0-ns2
ovn-nbctl lsp-set-addresses ls0-ns2 "00:00:00:aa:bb:20"

ovn-nbctl lsp-add ls0       ls0-ns3
ovn-nbctl lsp-set-addresses ls0-ns3 "00:00:00:aa:bb:30"
ovn-nbctl lsp-set-type      ls0-ns3 localport



# On controller
add_veth_port ns1 00:00:00:aa:bb:10 10.0.1.10 ls0-ns1
add_veth_port ns3 00:00:00:aa:bb:30 10.0.1.30 ls0-ns3

# On hypervisor
add_veth_port ns2 00:00:00:aa:bb:20 10.0.1.20 ls0-ns2
add_veth_port ns3 00:00:00:aa:bb:30 10.0.1.30 ls0-ns3



