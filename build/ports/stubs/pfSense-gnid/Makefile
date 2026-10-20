PORTNAME=	pfSense-gnid
DISTVERSION=	0.21
CATEGORIES=	security
MASTER_SITES=	# empty
DISTFILES=	# empty
EXTRACT_ONLY=	# empty

MAINTAINER=	coreteam@pfsense.org
COMMENT=	Unique system ID tool (stand-in)

LICENSE=	APACHE20

NO_BUILD=	yes
NO_ARCH=	yes

PLIST_FILES=	/usr/sbin/gnid

do-extract:
	@${MKDIR} ${WRKSRC}

do-install:
	${MKDIR} ${STAGEDIR}/usr/sbin
	${INSTALL_SCRIPT} ${FILESDIR}/gnid ${STAGEDIR}/usr/sbin/gnid

.include <bsd.port.mk>
