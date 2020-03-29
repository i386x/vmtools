# vmtools

*vmtools*, or virtual machine tools, is a set of scripts for managing virtual
machines and images. Its purpose is to help with testing software and features
on operating systems without touching the host.

## Requirements

* `qemu-kvm`
* `genisoimage`
* `netstat` (from `net-tools`) or `ss` (from `iproute`)
* `wget`
* `ssh`
* [`clishe`](https://github.com/i386x/clishe) v0.02 or later

## Installation

```
PREFIX=<prefix, default is /usr/local> make install
```

## How to Use

First, setup *vmtools* at your home:
```
vmtools-setup
```

Then, you can adjust your configuration:
```
vmtools-config
```

Next, let get some images:
```
vmtools-getimage URL MyImage.qcow2
```

Now, get to directory that work as your testing lab and initialize your first
virtual machine here:
```
cd testlab
vminit myfirstvm
```

Configure your `myfirstvm` and apply the changes with `vmupdate`:
```
vmconfig myfirstvm
vmupdate myfirstvm
```

Finally, lets launch it!
```
vmstart myfirstvm
```

You can check the SSH connection with `vmping` or you can connect to
`myfirstvm` directly:
```
vmping myfirstvm
vmssh myfirstvm
```

Have fun!
