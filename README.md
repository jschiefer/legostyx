# legostyx
Resurrecting the Styx-on-a-Brick project, originally created by Chris Locke and
Nigel Roles, with help from Kekoa Proudfoot.

A [paper about this project](http://doc.cat-v.org/inferno/4th_edition/styx-on-a-brick/) 
was published in June 2000. The contents of this repository are the contents of 
the `legostyx.tar` file described in the paper.

I have made no contributions to the code other than to archive it and add this
README.

## Prerequisites
You need a Lego RCX 2.0 brick and a Lego IR (infrared) tower. Linux
has kernel support for the IR tower since version 2.6, and (at least
in the 3.13 kernel that I am running), it is still there. When you 
plug in the USB connection to the tower, it should automatically
load the right driver (check with `dmesg`). Where the device file
will end up depends on your system. On my Ubuntu 14.04-derived system,
it is in `/dev/usb/legousbtower2`. If the permssions on the device are
too restrictive, you may neeed to add a `udev` entry. I just added a 
file `/etc/udev/rules.d/16-legousb.rules` with the contents:
```
# lego usb ir tower
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0694", ATTRS{idProduct}=="0001", MODE:="0666"
```
This will set the permissions to `rw-rw-rw-` when the tower is plugged in.

## Downloading the firmware
To download the RCX firmware from Linux, you have to get a hold of the program `firmdl3`,
which is a tool that comes with BrickOS. BrickOS is a multitasking operating 
system with development environment for use as an alternative to the standard LEGO(r) 
Mindstorms RCX firmware. As this software can be a little hard to figure out, I have included
a Linux x86_64 binary of the `firmdl3` program in the `bin/` directory of this repo. 

If you don't trust this binary (and really, you shouldn't), there is a clone of the 
original Sourceforge BrickOS source available [in Github](https://github.com/jschiefer/BrickOS).
Building this stuff requires a cross-compiler for
the Hitachi H8 processor. Good resources on how to get this going are available
[on the web](https://symbolicdomain.wordpress.com/2016/05/29/brickos/).

Now that we have all the bits and pieces assembled, we can finally load the firmware
onto the RCX. Turn on the RCX and line it up so it can "see" the IR tower. Run the
`firmdl3` command, adjusting command line parameters as necessary:
```
firmdl3 --tty=/dev/usb/legousbtower2 ./styx.srec
```
After a while of noodling, the RCX will display the "running person" icon and the 
number 0000 on the display.

This is as far as I got with this for the moment.