LIBFOO_VERSION = 0.1
LIBFOO_SOURCE = libfoo-$(LIBFOO_VERSION).tar.gz
LIBFOO_SITE = $(call github,tpetazzoni,libfoo,v$(LIBFOO_VERSION))
LIBFOO_AUTORECONF = YES
LIBFOO_INSTALL_STAGING = YES

define LIBFOO_TARGET_REMOVE_BINARIES
	rm -f $(TARGET_DIR)/usr/bin/libfoo-example1
endef

ifeq ($(BR2_PACKAGE_LIBFOO_DEBUG),y)
	LIBFOO_CONF_OPTS += --enable-debug-output
else
	LIBFOO_CONF_OPTS += --disable-debug-output
endif

LIBFOO_POST_INSTALL_TARGET_HOOKS += LIBFOO_TARGET_REMOVE_BINARIES

$(eval $(autotools-package))