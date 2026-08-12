# `br2-external/` — the project tree, outside Buildroot

Everything that belongs to *this project* rather than to Buildroot: the configuration, the
board files, and the three packages that Buildroot has no idea about. Buildroot itself stays a
pristine git checkout, which is the whole point — updating it is a `git pull`, not a merge.

```
BR2_EXTERNAL=$(pwd)/br2-external make bootlin_defconfig
```

`external.desc` names the tree `FOOBAR`, so every path below is written against
`$(BR2_EXTERNAL_FOOBAR_PATH)` and nothing depends on where the tree is checked out.

## The configuration

[`configs/bootlin_defconfig`](configs/bootlin_defconfig) — 40 lines, generated with
`make savedefconfig`, describing the whole system:

| | |
|---|---|
| Target | ARM Cortex-A7, EABIhf — STM32MP157A-DK1 |
| Toolchain | External **Bootlin** armv7-eabihf glibc, downloaded by Buildroot |
| Kernel | **6.12.47** + two out-of-tree patches, custom config, `st/stm32mp157a-dk1` DTB |
| Bootloader | **U-Boot 2025.07**, Kconfig build system, `stm32mp15_basic` + SPL |
| Packages | `ninvaders`, `bar`, `libfoo`, `myapp`, evtest, libconfig, Dropbear |
| Image | ext4 rootfs assembled into a full `sdcard.img` by **genimage** |
| Identity | hostname `stm32mp1-dk1`, custom login banner |

The kernel image, DTB and `extlinux.conf` all live **in the root partition**
(`BR2_LINUX_KERNEL_INSTALL_TARGET`), so the SD card needs no separate FAT boot partition —
four partitions instead of five.

## What migrating to BR2_EXTERNAL actually changed

Before the move, the same options pointed into the Buildroot tree — and one of them had leaked
an absolute path from my machine:

```diff
-BR2_GLOBAL_PATCH_DIR="board/bootlin/stm32mp1/patches/"
-BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="/home/<user>/.../buildroot/board/bootlin/stm32mp1/linux-stm32mp1.config"
+BR2_GLOBAL_PATCH_DIR="$(BR2_EXTERNAL_FOOBAR_PATH)/board/bootlin/stm32mp1/patches/"
+BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="$(BR2_EXTERNAL_FOOBAR_PATH)/board/bootlin/stm32mp1/linux-stm32mp1.config"
```

That absolute path is exactly the class of bug BR2_EXTERNAL removes: the defconfig is now
portable, and the project files are versioned separately from the 3000-package tree they plug
into.

## Board files

**[`build_id_creator.sh`](board/bootlin/stm32mp1/build_id_creator.sh)** — post-build script.
Buildroot passes `$(TARGET_DIR)` as `$1`, and the script stamps the Buildroot commit and the
build date into `/etc/build-id` on the target, so a running board can say which build it is.

**[`genimage.cfg`](board/bootlin/stm32mp1/genimage.cfg)** — the SD card, described declaratively:
a GPT image with `u-boot-spl.stm32` in both `fsbl1` and `fsbl2`, `u-boot.img` in `ssbl`, and the
ext4 rootfs marked bootable. This replaces the whole manual `parted` + `dd` + `mkfs` ritual with
one `sdcard.img` that `dd`s straight onto the card.

**[`rootfs-overlay/`](board/bootlin/stm32mp1/rootfs-overlay/)** — files dropped into the target
at the end of every build, so reflashing never loses them:

| Path | What it does |
|---|---|
| `boot/extlinux/extlinux.conf` | Tells U-Boot's distro-boot where the kernel, DTB and root (`/dev/mmcblk0p4`) are |
| `etc/network/interfaces` | Static `192.168.1.100` on `eth0` |
| `etc/init.d/S41network-fix` | Sets the same address directly with `ip`, right after `S40network` |

**[`linux-stm32mp1.config.delta.diff`](board/bootlin/stm32mp1/linux-stm32mp1.config.delta.diff)** —
my kernel configuration change, saved with `make linux-update-defconfig`, shown as a delta
against the Bootlin-provided base config (which is lab data, not mine):

```diff
+CONFIG_INPUT_JOYSTICK=y
+CONFIG_JOYSTICK_WIICHUCK=y
```

Two lines, and `wiichuck.c` gets built into the kernel — the driver for the I²C Wii Nunchuk
declared by the Device Tree patch.

## Packages

Three packages, each chosen to exercise a different corner of the packaging infrastructure:

| Package | Infrastructure | What it demonstrates |
|---|---|---|
| [`libfoo`](package/libfoo/) | `autotools-package` | GitHub download, `AUTORECONF`, staging install, post-install hook, Kconfig sub-option |
| [`bar`](package/bar/) | `autotools-package` | Mandatory + optional dependency, hashes, source patch |
| [`myapp`](package/myapp/) | `generic-package` | `local` site method — develop in your own tree, let Buildroot build it |

### `libfoo` — hooks and sub-options

```make
LIBFOO_SITE = $(call github,tpetazzoni,libfoo,v$(LIBFOO_VERSION))
LIBFOO_AUTORECONF = YES
LIBFOO_INSTALL_STAGING = YES
```

The GitHub tarball ships no `configure` script, hence `AUTORECONF`. `INSTALL_STAGING` is what
makes `foo.h` and `libfoo.so` visible to the cross-compiler — without it the library lands on
the target but nothing can link against it.

Upstream also installs a `libfoo-example1` demo binary that has no business being in a product
image, so a **post-install target hook** deletes it:

```make
define LIBFOO_TARGET_REMOVE_BINARIES
	rm -f $(TARGET_DIR)/usr/bin/libfoo-example1
endef
LIBFOO_POST_INSTALL_TARGET_HOOKS += LIBFOO_TARGET_REMOVE_BINARIES
```

[`Config.in`](package/libfoo/Config.in) adds a `BR2_PACKAGE_LIBFOO_DEBUG` sub-option guarded by
`if BR2_PACKAGE_LIBFOO`, wired to `--enable-debug-output` / `--disable-debug-output`. Passing
the negative form explicitly matters: it stops the configure script from picking up whatever it
happens to autodetect.

### `bar` — the two kinds of dependency

A *mandatory* dependency is declared twice, in Kconfig and in the makefile, and Buildroot needs
both — `select` guarantees the option is on, `DEPENDENCIES` guarantees the build order:

```make
BAR_DEPENDENCIES = libfoo host-pkgconf
```

An *optional* dependency gets no Kconfig option of its own; it reacts to whatever else is
enabled in the configuration:

```make
ifeq ($(BR2_PACKAGE_LIBCONFIG),y)
	BAR_CONF_OPTS += --with-libconfig
	BAR_DEPENDENCIES += libconfig
else
	BAR_CONF_OPTS += --without-libconfig
endif
```

Enabling `libconfig` then exposed a genuine upstream bug — `error: unknown type name 'config_t'`,
because `src/main.c` uses libconfig without including its header. Editing
`output/build/bar-1.1/` fixes it until the next `make clean`, so the fix is carried as a proper
patch instead: [`0001-Fix-missing-libconfig.h-include.patch`](package/bar/0001-Fix-missing-libconfig.h-include.patch),
generated with `git format-patch` off a `buildroot` branch of upstream's repository. Buildroot
applies it at the *Patching* step, so `make bar-dirclean all` now works from scratch.

[`bar.hash`](package/bar/bar.hash) pins the 1.1 tarball by SHA-256.

### `myapp` — my own application, built by Buildroot

```make
MYAPP_SITE = $(TOPDIR)/../myapp
MYAPP_SITE_METHOD = local
```

The `local` site method rsyncs the source from a directory on disk instead of downloading a
tarball, which is what you want for code you are actively writing: edit, `make myapp-rebuild`,
and Buildroot re-syncs and rebuilds. `$(TOPDIR)` keeps the reference relative to the Buildroot
checkout rather than hardcoding a home directory.

The build command asks `pkg-config` for the libconfig flags rather than guessing them, and keeps
`-g` so the binary can be debugged on the target with `gdbserver` and the cross gdb:

```make
$(TARGET_CC) -o $(@D)/myapp $(@D)/myapp.c \
	$(shell $(HOST_DIR)/bin/pkg-config --cflags --libs libconfig) -g
```

## Assembling a working tree

Three files this build needs are **not mine** and so are not in this repository. Drop them in
before building:

| Missing file | Where it comes from |
|---|---|
| `board/bootlin/stm32mp1/linux-stm32mp1.config` | Bootlin lab data (`buildroot-basic/`), then apply the `.delta.diff` above |
| `board/bootlin/stm32mp1/patches/linux/000{1,2}-*.patch` | Bootlin lab data — the Nunchuk driver and the DK1 Device Tree node |
| `board/bootlin/stm32mp1/genimage.sh` | A copy of Buildroot's own `support/scripts/genimage.sh` |

Then, from an out-of-tree build directory:

```sh
make -C /path/to/buildroot O=$(pwd) BR2_EXTERNAL=/path/to/br2-external bootlin_defconfig
make 2>&1 | tee build.log
sudo dd if=images/sdcard.img of=/dev/mmcblk0 bs=1M conv=fdatasync
```

## Attribution

The Buildroot package infrastructure, the `bar` / `libfoo` / `myapp` upstream sources and the
Linux kernel patches are **Bootlin** training material (© 2004-2026 Bootlin, CC BY-SA).
The `genimage.sh` helper is Buildroot's own script. Everything in this directory —
the packaging, the configuration, the board files and the overlay — is mine.
