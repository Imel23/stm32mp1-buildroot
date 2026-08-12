MYAPP_SITE = $(TOPDIR)/../myapp
MYAPP_SITE_METHOD = local
MYAPP_DEPENDENCIES = libconfig

define MYAPP_BUILD_CMDS
	$(TARGET_CC) -o $(@D)/myapp $(@D)/myapp.c $(shell $(HOST_DIR)/bin/pkg-config --cflags --libs libconfig) -g
endef

define MYAPP_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/myapp $(TARGET_DIR)/usr/bin/myapp
endef

$(eval $(generic-package))
