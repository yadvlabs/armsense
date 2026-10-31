#!/bin/sh
#
# armsense: run the QEMU guest agent when the hypervisor offers it a channel.
#
#   QEMU/libvirt/Proxmox   virtio-serial port named org.qemu.guest_agent.0
#                          -> /dev/vtcon/org.qemu.guest_agent.0
#   Apple Virtualization   the second virtio serial console (MacVisor's
#   (MacVisor)             guest-agent port) -> /dev/ttyV1.0
#
# rc.start_packages runs every /usr/local/etc/rc.d/*.sh with "start" at boot;
# this wraps the FreeBSD rc script of the qemu-guest-agent package so no
# rc.conf entry is needed.  Usage: qemu-guest-agent.sh start|stop|status
#
rc_script=/usr/local/etc/rc.d/qemu-guest-agent
[ -x /usr/local/bin/qemu-ga ] && [ -x "$rc_script" ] || exit 0

if [ -e /dev/vtcon/org.qemu.guest_agent.0 ]; then
	channel="-m virtio-serial -p /dev/vtcon/org.qemu.guest_agent.0"
elif [ -e /dev/ttyV1.0 ]; then
	channel="-m isa-serial -p /dev/ttyV1.0"
else
	# No channel: nothing to do (not an error on bare metal or other hypervisors).
	case ${1:-start} in start) exit 0 ;; esac
	channel=""
fi

qemu_guest_agent_enable=YES
qemu_guest_agent_flags="-d -l /var/log/qemu-ga.log $channel"
export qemu_guest_agent_enable qemu_guest_agent_flags
exec "$rc_script" "${1:-start}"
