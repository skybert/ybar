PREFIX ?= $(HOME)/.local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1

SWIFT = swiftc
SWIFTFLAGS = -O -framework Cocoa -framework Foundation

TARGET = ybar
SOURCE = src/main.swift
VERSION_FILE = src/version.swift
MANPAGE = man/ybar.1
MANPAGE_TEMPLATE = man/ybar.1.in

# Get version from git
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "unknown")

.PHONY: all clean install uninstall

all: $(TARGET) $(MANPAGE)

$(VERSION_FILE):
	@echo 'let VERSION = "$(VERSION)"' > $(VERSION_FILE)

$(TARGET): $(SOURCE) $(VERSION_FILE)
	$(SWIFT) $(SWIFTFLAGS) $(SOURCE) $(VERSION_FILE) -o $(TARGET)

$(MANPAGE): $(MANPAGE_TEMPLATE) AUTHORS
	@awk 'BEGIN{auth=0} /^\.SH AUTHORS/{auth=1; print; while(getline < "AUTHORS"){if($$0 != ""){print ".br"; print $$0}} next} /^\.SH SEE ALSO/{auth=0} auth==0{print}' $(MANPAGE_TEMPLATE) > $(MANPAGE)

clean:
	rm -f $(TARGET) $(MANPAGE) $(VERSION_FILE)

install: $(TARGET) $(MANPAGE)
	install -d $(BINDIR)
	install -m 755 $(TARGET) $(BINDIR)/$(TARGET)
	install -d $(MANDIR)
	install -m 644 $(MANPAGE) $(MANDIR)/ybar.1

uninstall:
	rm -f $(BINDIR)/$(TARGET)
	rm -f $(MANDIR)/ybar.1

.DEFAULT_GOAL := all
