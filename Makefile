PREFIX ?= $(HOME)/.local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1

SWIFT = swiftc
SWIFTFLAGS = -O -framework Cocoa -framework Foundation

TARGET = ybar
SOURCE = src/main.swift
MANPAGE = man/ybar.1
MANPAGE_TEMPLATE = man/ybar.1.in

.PHONY: all clean install uninstall

all: $(TARGET) $(MANPAGE)

$(TARGET): $(SOURCE)
	$(SWIFT) $(SWIFTFLAGS) $(SOURCE) -o $(TARGET)

$(MANPAGE): $(MANPAGE_TEMPLATE) AUTHORS
	@awk 'BEGIN{auth=0} /^\.SH AUTHORS/{auth=1; print; while(getline < "AUTHORS"){if($$0 != ""){print ".br"; print $$0}} next} /^\.SH SEE ALSO/{auth=0} auth==0{print}' $(MANPAGE_TEMPLATE) > $(MANPAGE)

clean:
	rm -f $(TARGET) $(MANPAGE)

install: $(TARGET) $(MANPAGE)
	install -d $(BINDIR)
	install -m 755 $(TARGET) $(BINDIR)/$(TARGET)
	install -d $(MANDIR)
	install -m 644 $(MANPAGE) $(MANDIR)/ybar.1

uninstall:
	rm -f $(BINDIR)/$(TARGET)
	rm -f $(MANDIR)/ybar.1

.DEFAULT_GOAL := all
