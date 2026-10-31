PORTNAME=	pfSense-ce
DISTVERSION=	${PRODUCT_VERSION}
CATEGORIES=	security

MAINTAINER=	coreteam@pfsense.org
COMMENT=	pfSense CE additional packages.
WWW=		https://www.pfsense.org/

LICENSE=	APACHE20

RUN_DEPENDS=	pfSense-pkg-System_Patches>0:sysutils/pfSense-pkg-System_Patches
# armsense: QEMU guest agent, started by /usr/local/etc/rc.d/qemu-guest-agent.sh
# when the hypervisor offers a channel (QEMU/libvirt port or MacVisor's serial port).
RUN_DEPENDS+=	qemu-guest-agent>0:emulators/qemu@guestagent

USES=		metaport

.include <bsd.port.pre.mk>

# The DRM kernel modules only matter for x86 consoles.
.if ${ARCH} == "amd64"
RUN_DEPENDS+=	drm-61-kmod>0:graphics/drm-61-kmod
.endif

.include <bsd.port.post.mk>
