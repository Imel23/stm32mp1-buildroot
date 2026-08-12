BAR_SITE = https://bootlin.com/~thomas/bar
BAR_VERSION = 1.1
BAR_SOURCE = bar-$(BAR_VERSION).tar.gz
BAR_DEPENDENCIES = libfoo host-pkgconf

ifeq ($(BR2_PACKAGE_LIBCONFIG),y)
	BAR_CONF_OPTS += --with-libconfig
	BAR_DEPENDENCIES += libconfig
else
	BAR_CONF_OPTS += --without-libconfig
endif

$(eval $(autotools-package))
