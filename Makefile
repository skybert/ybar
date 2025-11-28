PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1

SWIFT = swiftc
SWIFTFLAGS = -O -framework Cocoa -framework Foundation

TARGET = ybar
SOURCE = src/main.swift

.PHONY: all clean install uninstall

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(SWIFT) $(SWIFTFLAGS) $(SOURCE) -o $(TARGET)

clean:
	rm -f $(TARGET)

install: $(TARGET) man/ybar.1
	install -d $(BINDIR)
	install -m 755 $(TARGET) $(BINDIR)/$(TARGET)
	install -d $(MANDIR)
	install -m 644 man/ybar.1 $(MANDIR)/ybar.1

uninstall:
	rm -f $(BINDIR)/$(TARGET)
	rm -f $(MANDIR)/ybar.1

.DEFAULT_GOAL := all
