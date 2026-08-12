# `package/ninvaders/` — a package for the official Buildroot tree

An **in-tree** Buildroot package for [nInvaders](https://ninvaders.sourceforge.net/), a curses
Space Invaders clone from 2003. It lives here rather than in
[`br2-external/`](../../br2-external/) on purpose: `bar`, `libfoo` and `myapp` are
project-specific, but nInvaders is publicly available open source, so the right home for it is
`package/ninvaders/` in Buildroot itself, submittable upstream.

## Install into a Buildroot checkout

```sh
cp -r package/ninvaders /path/to/buildroot/package/
# then register it in the "Games" menu of package/Config.in:
#   source "package/ninvaders/Config.in"
```

## What each piece is for

**[`ninvaders.mk`](ninvaders.mk)** — `generic-package`, because upstream is a plain hand-written
`Makefile`: no autotools, no CMake, nothing to configure.

Three problems had to be solved to make a 2003 codebase cross-compile and install:

**1. It needs ncurses.** The first build failed on a missing `ncurses.h`. The dependency is
declared in both places Buildroot needs it — `select BR2_PACKAGE_NCURSES` in
[`Config.in`](Config.in) so the option is switched on, and `NINVADERS_DEPENDENCIES` so ncurses is
built first:

```make
NINVADERS_DEPENDENCIES = ncurses
```

The link flags come from `pkg-config` at build time rather than a hardcoded `-lncurses`, which is
what keeps it correct against the target sysroot:

```make
LDLIBS="`$(PKG_CONFIG_HOST_BINARY) --libs ncurses`"
```

**2. It predates gcc 10.** Several compilation units define the same symbols, and the link failed
with `multiple definition of 'skill_level'`. gcc up to 9 tolerated this; gcc 10 turned
`-fno-common` on by default. Rather than patch a dozen files, the package asks the compiler for
the old behaviour — while still honouring Buildroot's own target flags:

```make
NINVADERS_CFLAGS = $(TARGET_CFLAGS) -fcommon
```

**3. Its Makefile has no `install:` rule.** So the package installs the binary itself:

```make
define NINVADERS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/nInvaders $(TARGET_DIR)/usr/bin/nInvaders
endef
```

Without this step the build succeeds and the binary simply never reaches the image — the
package looks fine and the target has nothing on it.

**[`ninvaders.hash`](ninvaders.hash)** — SHA-256 and MD5 of the 0.1.1 tarball, so anyone building
this package gets a verified `ninvaders 0.1.1 Extracting` step rather than trusting whatever
SourceForge serves.

## Playing it with the Nunchuk

Bootlin provides a patch that teaches nInvaders to read the kernel joystick interface
(`/dev/input/js0`) in addition to the keyboard, so the game can be driven by the Wii Nunchuk.
That patch is lab data and is not reproduced here; dropping it into this directory is enough for
Buildroot to apply it at the *Patching* step.

It needs one more kernel option than the driver itself: `CONFIG_JOYSTICK_WIICHUCK` gives the
Nunchuk an `/dev/input/event0` node (`CONFIG_INPUT_EVDEV` is already on in the base config, which
is what `evtest` reads), but `js0` only appears with **`CONFIG_INPUT_JOYDEV`** as well. The
[kernel config delta](../../br2-external/board/bootlin/stm32mp1/linux-stm32mp1.config.delta.diff)
in this repository enables the driver but not `JOYDEV`, so driving the game with the joystick
needs that option switched on too.

## Note on package removal

Disabling the package in `menuconfig` and rebuilding does **not** remove `nInvaders` from
`output/target/` — Buildroot never uninstalls, it only ever adds to the target directory. Only a
full `make clean` (or a fresh output directory) gives a target that reflects the configuration.
Worth knowing before trusting an incrementally-built image.

## Attribution

nInvaders itself is third-party GPL software, and the joystick patch is **Bootlin** training
material. The packaging in this directory is mine.
