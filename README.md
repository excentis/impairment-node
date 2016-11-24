# impairment-node
Rigorously testing a network device or distributed service requires complex, realistic network test environments. Linux Traffic Control (tc) with Network Emulation (netem) provides the building blocks to create an impairment node that simulates such networks.

This script and config file is our quick-and-dirty implementation of a layer 2 impairment node, based on Linux Traffic Control technology.

It was released under a permissive [license](./LICENSE) as part of a blog post series called '*[Use Linux Traffic Control as impairment node in a test environment](https://www.excentis.com/blog/use-linux-traffic-control-impairment-node-test-environment-part-1)*' on Excentis' [company blog](https://www.excentis.com/blog).

The [third part](https://www.excentis.com/blog/use-linux-traffic-control-impairment-node-test-environment-part-3) of that series contains the rationale and documentation for this implementation script.

We've been using it to test our [ByteBlower](https://www.excentis.com/products/byteblower) traffic generator/analyzer in impaired circumstances and to demonstrate how it operates in real-life, non-ideal network conditions to our customers.

February 2015

Tim De Backer, Excentis nv

