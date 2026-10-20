PORTNAME=	repoc
DISTVERSION=	0.1
CATEGORIES=	sysutils
PKGNAMEPREFIX=	pfSense-
MASTER_SITES=	# empty
DISTFILES=	# empty
EXTRACT_ONLY=	# empty

MAINTAINER=	coreteam@pfsense.org
COMMENT=	pfSense repository settings tool (static stand-in)

LICENSE=	APACHE20

NO_BUILD=	yes
NO_ARCH=	yes

SUB_FILES=	pfSense-repoc
SUB_LIST=	PRODUCT_NAME=pfSense

PLIST_FILES=	sbin/pfSense-repoc \
		sbin/pfSense-repoc-static

do-extract:
	@${MKDIR} ${WRKSRC}

do-install:
	${MKDIR} ${STAGEDIR}${PREFIX}/sbin
	${INSTALL_SCRIPT} ${WRKDIR}/pfSense-repoc ${STAGEDIR}${PREFIX}/sbin/pfSense-repoc
	${LN} -sf pfSense-repoc ${STAGEDIR}${PREFIX}/sbin/pfSense-repoc-static

.include <bsd.port.mk>
