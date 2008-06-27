
.PHONY: all default images

default: manual.html images
all: default

manual.html: manual.txt manual.conf gzl-rtn-graph Makefile
	asciidoc -a toc -a toclevels=3 -a icons -a iconsdir=. manual.txt

images:
	mkdir -p images && cp -f /usr/share/asciidoc/images/*.png images

clean:
	rm -rf *.png *.html images
