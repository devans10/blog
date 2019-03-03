+++
title = "The Life of a Network Packet in Linux"
date = "2018-09-15T00:00:00Z"
draft = false
tags = ["networking", "linux"]
+++
I have encountered this problem numerous times, and every time I am told "There is something wrong with the network!!"

What I really need is someone much more creative than me to write a children's song similar to Schoolhouse Rock's "I'm Just a Bill", except for network packets

### Scenario

There are 2 servers.  Each server has 2 network interfaces that all have listening addresses in separate subnets. The Default route for each server is via eth0.

###### ServerA:

> eth0: 
> IP: 10.1.0.100/24
> Gateway: 10.1.0.1

> eth1:
> IP: 10.2.0.100/24
> Gateway: 10.2.0.1

route table:
|Destination |Gateway   |Genmask       |Iface |
|------------|----------|--------------|------|
| default    | 10.1.0.1 |0.0.0.0       | eth0 |
| 10.1.0.0   | 10.1.0.1 |255.255.255.0 | eth0 |
| 10.2.0.0   | 10.2.0.1 |255.255.255.0 | eth1 |


###### ServerB:

> eth0: 
> IP: 10.3.0.100/24
> Gateway: 10.1.0.1

> eth1:
> IP: 10.4.0.100/24
> Gateway: 10.2.0.1

route table:
|Destination |Gateway   |Genmask       |Iface |
|------------|----------|--------------|------|
| default    | 10.3.0.1 |0.0.0.0       | eth0 |
| 10.3.0.0   | 10.3.0.1 |255.255.255.0 | eth0 |
| 10.4.0.0   | 10.4.0.1 |255.255.255.0 | eth1 |


### The Problem
In this scenario, as it is currently setup, you will *NOT* be able to make a network connection from ServerA:eth1 to ServerB:eth1.

### The Reason

So we are going to deal with a simple Ping packet, and follow it through the its path.  However, the same process can be assumed for an initial SYN packet being sent to establish a TCP connection.  I'm not going to talk about the network here too much. We will assume the switches and routers the servers are connected to are setup properly, because as I have stated **the network is *not* the problem**

So we issue the following command from ServerA:

``$ ping -I eth1 10.4.0.100``

The packet is generated, it is given a ``destIP`` of 10.4.0.100 and a ``srcIP`` of 10.2.0.100, and is sent out via eth1, since that was specified in the command.  It goes to the 10.2.0.1 gateway which routes to the 10.4.0.1 gateway, and is then sent to the eth1 interface on ServerB.  So far this is exactly what you would expect to happen.

Now the fun begins...

ServerB receives the ping and begins to craft the reply packet.  It sets the ``destIP`` to 10.2.0.100.  Since this server was not explicitly told which interface to use, like ServerA was when we initiated the ``ping``, it must look at its route table to determine which interface to use.  The only route that matches is the ``Default`` route. So the server decides to send the packet out eth0 and gives the packet a ``srcIP`` of 10.3.0.100.  the packet is then sent out to the 10.3.0.1 gateway, which routes it to the 10.2.0.1 gateway, and is finally delivered to the 10.2.0.100 interface.

The problem is the packet that is received by eth1 on ServerA has a ``srcIP`` of 10.3.0.100, but ServerA was waiting for a reply from 10.4.0.100.  So ServerA believes in never received a reply and reports a connection failure.

### The Solution(s)

There are a couple solutions to this problem, but they all involve settings on the servers.  If anyone know of additional solutions, please let me know.  I would love to have another way to solve this.

#### Set static routes between networks

Creating a route on each server specifying which gateway should be used to reach the destination.

On ServerA:
```bash
$ ip route add 10.4.0.0/24 via 10.2.0.1 dev eth1
```

On ServerB:
```bash
$ ip route add 10.2.0.0/24 via 10.4.0.1 dev eth1
```

After these routes are added the new route tables on each server:

ServerA:
|Destination |Gateway   |Genmask       |Iface |
|------------|----------|--------------|------|
| default    | 10.1.0.1 |0.0.0.0       | eth0 |
| 10.1.0.0   | 10.1.0.1 |255.255.255.0 | eth0 |
| 10.2.0.0   | 10.2.0.1 |255.255.255.0 | eth1 |
| 10.4.0.0   | 10.2.0.1 |255.255.255.0 | eth1 |

ServerB:
|Destination |Gateway   |Genmask       |Iface |
|------------|----------|--------------|------|
| default    | 10.3.0.1 |0.0.0.0       | eth0 |
| 10.3.0.0   | 10.3.0.1 |255.255.255.0 | eth0 |
| 10.4.0.0   | 10.4.0.1 |255.255.255.0 | eth1 |
| 10.2.0.0   | 10.4.0.1 |255.255.255.0 | eth1 |

After these changes, when doing the initial ``ping`` you know longer need to specify ``-I eth1``, the server will use eth1 because of the decision made by its route table.  Now when ServerB is crafting the reply, it will find 10.2.0.0/24 in its route table and see it is supposed to use eth1 and send to gateway 10.4.0.1.  It will now set the ``srcIP`` to 10.4.0.100. When ServerA receives the reply, it will be from the correct address, and the ping will succeed.

#### Adding a secondary route table

Another way to accomplish the same end result as above is to add a secondary route table.  With this solution, you can create rules and routes that will send reply packets back out the same interface they came in through.

ServerA:
```bash
$ echo 200 eth1 >> /etc/iproute2/rt_tables
$ ip rule add from 10.2.0.100 dev eth1 table eth1
$ ip route add default via 10.2.0.1 dev eth1 table eth1
```

ServerB:
```bash
$ echo 200 eth1 >> /etc/iproute2/rt_tables
$ ip rule add from 10.4.0.100 dev eth1 table eth1
$ ip route add default via 10.4.0.1 dev eth1 table eth1
```

These rules and routes can be persisted by creating a ``rule-eth1`` and ``route-eth1`` files in the /etc/sysconfig/network-scripts (on RHEL derivative systems or /etc/sysconfig/network on Debian derivative systems.
These files will add the rules and routes on interface startup.

#### IPTables rules

I am sure there are also ways to accomplish this using ``iptables`` rules, but in my opinion this is a much worse ways to get the desired result.  I believe this is a case where the ends do not justify the means.

### Conclusion

I hope that there are other solutions to this that I am unaware of.  I started to look at some EC2 servers on AWS as an example. Those servers can have a public IP address in one subnet and a private IP address in your VPC subnet.  However, if you look into it, the EC2 instance only has a listening interface on the private IP.  I could speculate on how Amazon is doing this, but I haven't dug into it, so I won't do that now.  Needless to say, its not the same situation.

A use case for this setup is wanting to use a dedicated replication network that is separate from your normal data access network.  For example, an Oracle Database DataGuard.  If your replica is in a different Data Center, and on a different subnet, and you want this traffic to go across a dedicated interface so it does not interfere with you primary data access network.

I have often run into these situation when setting up systems and architectures for Disaster Recovery.  I often have seen people give up, blame "those idiot network administrators" for not setting it up right, and just use the primary interfaces.  However, using the secondary network interfaces usually serves a legitimate purpose, such as network segmentation.

Hopefully this will help someone when they hit these situations.
