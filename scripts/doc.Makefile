SOURCES=$(shell find content/ -name '*.md')
HTML_FILES := $(patsubst %.md,%.html,$(SOURCES))
TARGETS := $(addprefix _site/, $(HTML_FILES:content/%=%))


.PHONY: all
all: $(TARGETS) \
	_site/robots.txt _site/humans.txt _site/.well-known/security.txt \
	curiosity.7 cty.1 \
	_site/documentation/clis/curiosity.7.html \
	_site/documentation/clis/cty.1.html


_site/%.html: content/%.md scripts/template.html
	mkdir -p $(dir $@)
	pandoc --standalone \
		--toc \
		--section-divs \
		--to html5 \
		--template scripts/template.html \
		--output $@ \
		$<

_site/documentation/clis/%.1.html: %.1
	mkdir -p $(dir $@)
	mandoc -T html $< > $@

_site/documentation/clis/%.7.html: %.7
	mkdir -p $(dir $@)
	mandoc -T html $< > $@

%.1: man/%.1.md
	pandoc --standalone --to man $< -o $@

%.7: man/%.7.md
	pandoc --standalone --to man $< -o $@

_site/robots.txt: content/robots.txt
	cp $< $@

_site/humans.txt: content/humans.txt
	cp $< $@

_site/.well-known/security.txt: content/.well-known/security.txt
	mkdir -p $(dir $@)
	cp $< $@

entr:
	find content/ -name '*.md' \
		| entr -c bash -c 'make -f scripts/doc.Makefile'
