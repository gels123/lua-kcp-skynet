LUA_VERSION =       5.4
TARGET1 =           ../../luaclib/lutil.so
TARGET2 =           ../../luaclib/lkcp.so
TARGET3 =           ../../luaclib/lkcpsn.so
PREFIX =            /usr/local
CFLAGS =            -g -O2 -Wall -rdynamic -pedantic -DNDEBUG -std=gnu99 -Wformat
LUA_INCLUDE_DIR =   ../../skynet/3rd/lua
SKYNET_INCLUDE_DIR = ../../skynet/skynet-src

LNX_LDFLAGS = -shared -L./ -Wl,-rpath ./
MAC_LDFLAGS = -bundle -undefined dynamic_lookup -L./ -Wl,-rpath ./

CC = gcc
LDFLAGS = $(MYLDFLAGS)

BUILD_CFLAGS =       -fPIC -I$(LUA_INCLUDE_DIR) -I$(SKYNET_INCLUDE_DIR)
OBJS1 =              lutil.o
OBJS2 =              lkcp.o  ikcp.o
OBJS3 =              lkcpsn.o  ikcp.o

all:
	@echo "Usage: $(MAKE) <platform>"
	@echo "  * linux"
	@echo "  * macosx"
	@echo "  * clean"

.c.o:
	$(CC) -c $(CFLAGS) $(BUILD_CFLAGS) -o $@ $<

linux:
	@$(MAKE) $(TARGET1) MYLDFLAGS="$(LNX_LDFLAGS)"
	@$(MAKE) $(TARGET2) MYLDFLAGS="$(LNX_LDFLAGS)"
	@$(MAKE) $(TARGET3) MYLDFLAGS="$(LNX_LDFLAGS)"

macosx:
	@$(MAKE) $(TARGET1) MYLDFLAGS="$(MAC_LDFLAGS)"
	@$(MAKE) $(TARGET2) MYLDFLAGS="$(MAC_LDFLAGS)"
	@$(MAKE) $(TARGET3) MYLDFLAGS="$(MAC_LDFLAGS)"

$(TARGET1): $(OBJS1)
	$(CC) $(LDFLAGS) -o $@ $(OBJS1)

$(TARGET2): $(OBJS2)
	$(CC) $(LDFLAGS) -o $@ $(OBJS2)

$(TARGET3): $(OBJS3)
	$(CC) $(LDFLAGS) -o $@ $(OBJS3)

clean:
	rm -rf *.o *.a *.so

