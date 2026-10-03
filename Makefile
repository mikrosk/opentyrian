# BUILD SETTINGS ###############################################################

# UNIX, WIN32 or ATARI (cross-compiled with m68k-atari-mintelf-gcc)
ifneq ($(filter Msys Cygwin, $(shell uname -o)), )
    PLATFORM ?= WIN32
else
    PLATFORM ?= ATARI
endif

# ATARI only: 020 (68020-68060: TT, Falcon, CT60) or cf (ColdFire: FireBee);
# empty builds all of them
ATARI_TARGETS := 020 cf
ATARI_TARGET ?=

ifeq ($(PLATFORM), WIN32)
    TYRIAN_DIR = C:\\TYRIAN
else
    TYRIAN_DIR = $(gamesdir)/tyrian
endif

# true, false, or auto (true if pkg-config can find SDL_net)
ifeq ($(PLATFORM), ATARI)
    WITH_NETWORK := false
    WITH_NFM ?= auto
else
    WITH_NETWORK ?= auto
    WITH_NFM := false
endif

################################################################################

# see https://www.gnu.org/prep/standards/html_node/Makefile-Conventions.html

SHELL = /bin/sh

ifeq ($(PLATFORM)-$(ATARI_TARGET), ATARI-)

# Each Atari target links against its own multilib (with its own SDL and nFM
# flags), so every target is built by a separate make invocation.

DISTDIR := dist/opentyrian
SDL_URL := https://raw.githubusercontent.com/libsdl-org/SDL-1.2/main

.PHONY : all clean dist dist_common $(ATARI_TARGETS) $(ATARI_TARGETS:%=%_dist)

all : $(ATARI_TARGETS)

clean :
	rm -rf obj dist
	rm -f $(ATARI_TARGETS:%=ot_%.gtp) opentyrian.zip

$(ATARI_TARGETS) :
	$(MAKE) ATARI_TARGET=$@

# Text files get CR/LF line endings, as TOS text viewers expect.
dist_common :
	./get_data.sh data
	mkdir -p $(DISTDIR)/licenses
	cp -r data $(DISTDIR)/
	cp doc/atari.txt $(DISTDIR)/atari.txt
	cp README.md $(DISTDIR)/README.md
	cp COPYING $(DISTDIR)/COPYING.txt
	cp doc/tyrian-freeware-license.txt $(DISTDIR)/licenses/Tyrian.txt
	curl -fsSL -o $(DISTDIR)/licenses/SDL1.txt $(SDL_URL)/COPYING
	curl -fsSL -o $(DISTDIR)/README.SDL $(SDL_URL)/README.MiNT
	for f in atari.txt README.md README.SDL COPYING.txt licenses/SDL1.txt licenses/Tyrian.txt; do \
		sed -i 's/\r*$$/\r/' "$(DISTDIR)/$$f"; \
	done

$(ATARI_TARGETS:%=%_dist) : %_dist : % dist_common
	cp ot_$*.gtp $(DISTDIR)/

dist : $(ATARI_TARGETS:%=%_dist)
	rm -f opentyrian.zip
	cd dist && zip -r ../opentyrian.zip opentyrian

else # a single target (any platform)

ifeq ($(PLATFORM), ATARI)
    ifeq ($(ATARI_TARGET), 020)
        CPU := -m68020-60 -mtune=68060
    else ifeq ($(ATARI_TARGET), cf)
        CPU := -mcpu=5475
    else
        $(error Unknown ATARI_TARGET '$(ATARI_TARGET)', use one of: $(ATARI_TARGETS))
    endif
    # changes the ABI: SDL and nFM must be built for the same multilib
    CPU += -mfastcall
    CC := m68k-atari-mintelf-gcc
    # the wrapper picks the multilib from CFLAGS
    PKG_CONFIG ?= CFLAGS="$(CPU)" m68k-atari-mintelf-pkg-config
else
    CC ?= gcc
    PKG_CONFIG ?= pkg-config
endif
INSTALL ?= install
WINDRES ?= windres

VCS_IDREV ?= (git describe --tags || git rev-parse --short HEAD)

INSTALL_PROGRAM ?= $(INSTALL)
INSTALL_DATA ?= $(INSTALL) -m 644

prefix ?= /usr/local
exec_prefix ?= $(prefix)

bindir ?= $(exec_prefix)/bin
datarootdir ?= $(prefix)/share
datadir ?= $(datarootdir)
docdir ?= $(datarootdir)/doc/opentyrian
mandir ?= $(datarootdir)/man
man6dir ?= $(mandir)/man6
man6ext ?= .6
desktopdir ?= $(datarootdir)/applications
icondir ?= $(datarootdir)/icons

# see https://www.pathname.com/fhs/pub/fhs-2.3.html

gamesdir ?= $(datadir)/games

###

TARGET := opentyrian
OBJDIR := obj
RES :=
ifeq ($(PLATFORM), ATARI)
    TARGET := ot_$(ATARI_TARGET).gtp
    OBJDIR := obj/$(ATARI_TARGET)
endif
ifeq ($(PLATFORM), WIN32)
    TARGET := opentyrian.exe
    # The icon, from the same resource script the Visual Studio build uses.
    RES := $(OBJDIR)/resources.o
endif

SRCS := $(wildcard src/*.c)
OBJS := $(SRCS:src/%.c=$(OBJDIR)/%.o)
DEPS := $(SRCS:src/%.c=$(OBJDIR)/%.d)

###

ifeq ($(WITH_NETWORK), auto)
    ifeq ($(shell $(PKG_CONFIG) --exists SDL_net 2>/dev/null && echo true), true)
        WITH_NETWORK := true
    else
        WITH_NETWORK := false
        $(info SDL_net not found; building without network support)
    endif
endif

ifeq ($(WITH_NETWORK), true)
    EXTRA_CPPFLAGS += -DWITH_NETWORK
endif

NFM_INCLUDEDIR := $(shell $(CC) -print-sysroot)/usr/include/nfm

# nFM is not built for ColdFire
ifneq ($(findstring 5475, $(CPU)), )
    WITH_NFM := false
endif

ifeq ($(WITH_NFM), auto)
    ifneq ($(wildcard $(NFM_INCLUDEDIR)/nfmcore.h), )
        WITH_NFM := true
    else
        WITH_NFM := false
        $(info nFM not found; building without OPL hardware support)
    endif
endif

ifeq ($(WITH_NFM), true)
    # nfmcore.h requires NFM_OPL_SHADOW_REG_WRITE_ENABLE to match the library
    # build; -isystem because its headers are not -pedantic clean
    EXTRA_CPPFLAGS += -DWITH_NFM \
                      -DNFM_OPL_SHADOW_REG_WRITE_ENABLE=1 \
                      -isystem $(NFM_INCLUDEDIR)
    NFM_LDLIBS := -lnfmcore -ldrvnokturnfm -ldrvisasb -ldrvoplxlpt -ldrvopl3duo -ldrvopllcart \
                  -ldrvopl3express -ldrvoplnull -ldrvcommon -lsyscore -lcontainers -lallocators -lm
endif

OPENTYRIAN_VERSION := $(shell $(VCS_IDREV) 2>/dev/null && \
                              touch src/opentyrian_version.h)
ifneq ($(OPENTYRIAN_VERSION), )
    EXTRA_CPPFLAGS += -DOPENTYRIAN_VERSION='"$(OPENTYRIAN_VERSION)"'
endif

# -Wno-format-truncation only exists in GCC; Clang rejects it under -Werror
ifeq ($(findstring clang, $(shell $(CC) --version 2>/dev/null)), )
    WNO_FORMAT_TRUNCATION := -Wno-format-truncation
endif

CPPFLAGS ?= -MMD
CPPFLAGS += -DNDEBUG
CFLAGS ?= -pedantic \
          -Wall \
          -Wextra \
          $(WNO_FORMAT_TRUNCATION) \
          -Wno-missing-field-initializers \
          -O2
LDFLAGS ?=
LDLIBS ?=

ifeq ($(PLATFORM), ATARI)
    CFLAGS += -fomit-frame-pointer $(CPU)
    LDFLAGS += -s -Wl,--msuper-memory -Wl,--stack,256k $(CPU)
endif

ifeq ($(WITH_NETWORK), true)
    SDL_CPPFLAGS := $(shell $(PKG_CONFIG) sdl SDL_net --cflags)
    SDL_LDFLAGS := $(shell $(PKG_CONFIG) sdl SDL_net --libs-only-L --libs-only-other)
    SDL_LDLIBS := $(shell $(PKG_CONFIG) sdl SDL_net --libs-only-l)
else
    SDL_CPPFLAGS := $(shell $(PKG_CONFIG) sdl --cflags)
    SDL_LDFLAGS := $(shell $(PKG_CONFIG) sdl --libs-only-L --libs-only-other)
    SDL_LDLIBS := $(shell $(PKG_CONFIG) sdl --libs-only-l)
endif

ALL_CPPFLAGS = -DTARGET_$(PLATFORM) \
               -DTYRIAN_DIR='"$(TYRIAN_DIR)"' \
               $(EXTRA_CPPFLAGS) \
               $(SDL_CPPFLAGS) \
               $(CPPFLAGS)
ALL_CFLAGS = -std=iso9899:1999 \
             $(CFLAGS)
ALL_LDFLAGS = $(SDL_LDFLAGS) \
              $(LDFLAGS)
ALL_LDLIBS = -lm \
             $(SDL_LDLIBS) \
             $(NFM_LDLIBS) \
             $(LDLIBS)

###

.PHONY : all
all : $(TARGET)

.PHONY : debug
debug : CPPFLAGS += -UNDEBUG
debug : CFLAGS += -Werror
debug : CFLAGS += -O0
debug : CFLAGS += -g3
debug : all

.PHONY : installdirs
installdirs :
	mkdir -p $(DESTDIR)$(bindir)
	mkdir -p $(DESTDIR)$(docdir)
	mkdir -p $(DESTDIR)$(man6dir)
	mkdir -p $(DESTDIR)$(desktopdir)
	mkdir -p $(DESTDIR)$(icondir)/hicolor/22x22/apps
	mkdir -p $(DESTDIR)$(icondir)/hicolor/24x24/apps
	mkdir -p $(DESTDIR)$(icondir)/hicolor/32x32/apps
	mkdir -p $(DESTDIR)$(icondir)/hicolor/48x48/apps
	mkdir -p $(DESTDIR)$(icondir)/hicolor/128x128/apps

.PHONY : install
install : $(TARGET) installdirs
	$(INSTALL_PROGRAM) $(TARGET) $(DESTDIR)$(bindir)/
	$(INSTALL_DATA) README.md $(DESTDIR)$(docdir)/
	$(INSTALL_DATA) linux/man/opentyrian.6 $(DESTDIR)$(man6dir)/opentyrian$(man6ext)
	$(INSTALL_DATA) linux/opentyrian.desktop $(DESTDIR)$(desktopdir)/
	$(INSTALL_DATA) linux/icons/tyrian-22.png $(DESTDIR)$(icondir)/hicolor/22x22/apps/opentyrian.png
	$(INSTALL_DATA) linux/icons/tyrian-24.png $(DESTDIR)$(icondir)/hicolor/24x24/apps/opentyrian.png
	$(INSTALL_DATA) linux/icons/tyrian-32.png $(DESTDIR)$(icondir)/hicolor/32x32/apps/opentyrian.png
	$(INSTALL_DATA) linux/icons/tyrian-48.png $(DESTDIR)$(icondir)/hicolor/48x48/apps/opentyrian.png
	$(INSTALL_DATA) linux/icons/tyrian-128.png $(DESTDIR)$(icondir)/hicolor/128x128/apps/opentyrian.png

.PHONY : uninstall
uninstall :
	rm -f $(DESTDIR)$(bindir)/$(TARGET)
	rm -f $(DESTDIR)$(docdir)/README.md
	rm -f $(DESTDIR)$(man6dir)/opentyrian$(man6ext)
	rm -f $(DESTDIR)$(desktopdir)/opentyrian.desktop
	rm -f $(DESTDIR)$(icondir)/hicolor/22x22/apps/opentyrian.png
	rm -f $(DESTDIR)$(icondir)/hicolor/24x24/apps/opentyrian.png
	rm -f $(DESTDIR)$(icondir)/hicolor/32x32/apps/opentyrian.png
	rm -f $(DESTDIR)$(icondir)/hicolor/48x48/apps/opentyrian.png
	rm -f $(DESTDIR)$(icondir)/hicolor/128x128/apps/opentyrian.png

.PHONY : clean
clean :
	rm -f $(OBJS)
	rm -f $(DEPS)
	rm -f $(RES)
	rm -f $(TARGET)

$(TARGET) : $(OBJS) $(RES)
	$(CC) $(ALL_CFLAGS) $(ALL_LDFLAGS) -o $@ $^ $(ALL_LDLIBS)

-include $(DEPS)

$(OBJDIR)/%.o : src/%.c
	@mkdir -p "$(dir $@)"
	$(CC) $(ALL_CPPFLAGS) $(ALL_CFLAGS) -c -o $@ $<

$(OBJDIR)/resources.o : visualc/resources.rc visualc/tyrian.ico
	@mkdir -p "$(dir $@)"
	$(WINDRES) --include-dir visualc -i $< -o $@

endif # a single target
