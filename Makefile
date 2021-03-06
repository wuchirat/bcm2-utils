CC ?= gcc
CXX ?= g++
LIBS ?=
VERSION = $(shell git describe --always)
CFLAGS += -Wall -g -DVERSION=\"$(VERSION)\"
CXXFLAGS += $(CFLAGS) -std=c++14 -Wnon-virtual-dtor
PREFIX ?= /usr/local
UNAME ?= $(shell uname)

ifeq ($(UNAME), Linux)
	LIBS += -lssl -lcrypto
endif

ifeq ($(UNAME), Darwin)
	CFLAGS +=
endif

bcm2dump_OBJ = io.o rwx.o interface.o ps.o bcm2dump.o \
	util.o progress.o mipsasm.o profile.o profiledef.o
bcm2cfg_OBJ = util.o nonvol2.o bcm2cfg.o nonvoldef.o \
	gwsettings.o profile.o profiledef.o crypto.o

t_nonvol_OBJ = util.o nonvol2.o t_nonvol.o

.PHONY: all clean bcm2cfg.exe

all: bcm2dump bcm2cfg t_nonvol

release: clean bcm2cfg bcm2dump
	strip bcm2cfg
	strip bcm2dump
	zip bcm2utils-$(VERSION).zip README.md bcm2cfg bcm2dump

bcm2cfg: $(bcm2cfg_OBJ)
	$(CXX) $(CXXFLAGS) $(bcm2cfg_OBJ) -o $@ $(LIBS)

bcm2cfg.exe:
	UNAME=Wine CC=winegcc CXX=wineg++ CFLAGS=-m32 make bcm2cfg

bcm2dump: $(bcm2dump_OBJ)
	$(CXX) $(CXXFLAGS) $(bcm2dump_OBJ) -o $@ 

t_nonvol: $(t_nonvol_OBJ)
	$(CXX) $(CXXFLAGS) $(t_nonvol_OBJ) -o $@

%.o: %.c %.h
	$(CC) -c $(CFLAGS) $< -o $@

%.o: %.cc %.h
	$(CXX) -c $(CXXFLAGS) $< -o $@

check: t_nonvol
	./t_nonvol

clean:
	rm -f bcm2cfg bcm2cfg.exe bcm2dump t_nonvol *.o

install: all
	install -m 755 bcm2cfg $(PREFIX)/bin
	install -m 755 bcm2dump $(PREFIX)/bin
