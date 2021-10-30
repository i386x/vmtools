# vmtools

*vmtools*, or virtual machine tools, is a set of scripts for managing virtual
machines and images. Its purpose is to help with testing software and features
on operating systems without touching the host. Virtual machines are running in
*snapshot* mode, which means that after halting every change is forgotten.

## Requirements

* `qemu-kvm`
* `mkisofs`
* `netstat` (from `net-tools`) or `ss` (from `iproute`)
* `curl`
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
vmtools-getimage <URL> MyImage
```

Now, create your first virtual machine:
```
vminit myfirstvm
```

Configure your `myfirstvm`:
```
vmconfig myfirstvm
```

To ensure that `myfirstvm` start, you must set `VMCFG_IMAGE` to the image name
previously pulled with `vmtools-getimage`:
```bash
VMCFG_IMAGE="MyImage"
```

Apply the changes made by `vmconfig` (if you just provided image name, you do
not need to run `vmupdate`):
```
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

Or you can halt it if you are done with it:
```
vmstop myfirstvm
```

There are plenty of other useful commands:
* `vmkill` to send a signal to the process running the virtual machine
* `vmstatus` to check whether virtual machine is active or halted
* `vmplay` to run a set of Ansible playbooks
* `vmsetup` to setup the virtual machine

Have fun!
