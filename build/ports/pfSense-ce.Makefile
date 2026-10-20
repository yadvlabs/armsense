PORTNAME=	pfSense-ce
DISTVERSION=	${PRODUCT_VERSION}
CATEGORIES=	security

MAINTAINER=	coreteam@pfsense.org
COMMENT=	pfSense CE additional packages.
WWW=		https://www.pfsense.org/

LICENSE=	APACHE20

RUN_DEPENDS=	pfSense-pkg-System_Patches>0:sysutils/pfSense-pkg-System_Patches

USES=		metaport

.include <bsd.port.pre.mk>

# The DRM kernel modules only matter for x86 consoles.
.if ${ARCH} == "amd64"
RUN_DEPENDS+=	drm-61-kmod>0:graphics/drm-61-kmod
.endif

.include <bsd.port.post.mk>
