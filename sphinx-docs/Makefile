# Makefile for Sphinx documentation

SPHINX_OPTS  ?=
SPHINX_BUILD ?= sphinx-build
SED          ?= sed

SOURCE_DIR   = source
BUILD_DIR    = build
MANUAL_DIR   = ../Manual
WEBSITE_DIR  ?= ../docs

.PHONY: clean

clean:
	@$(SPHINX_BUILD) -M clean "$(SOURCE_DIR)" "$(BUILD_DIR)" $(SPHINX_OPTS) $(O)

html:
	@$(SPHINX_BUILD) -M html "$(SOURCE_DIR)" "$(BUILD_DIR)" $(SPHINX_OPTS) $(O)

gen_html: clean generate_css html


build_website: gen_html
	cp "$(BUILD_DIR)/html/index.html" "$(WEBSITE_DIR)/index.html"

	rm -rf "$(WEBSITE_DIR)/manual"
	mkdir "$(WEBSITE_DIR)/manual"
	cp -R "$(BUILD_DIR)/html/"* "$(WEBSITE_DIR)/manual"

	rm -rf "$(WEBSITE_DIR)/_static"
	mv "$(WEBSITE_DIR)/manual/_static" "$(WEBSITE_DIR)/_static"
	cd "$(WEBSITE_DIR)/manual" && ln -s ../_static _static

build_manual: gen_html
	rm -rf "$(MANUAL_DIR)"
	mkdir -p "$(MANUAL_DIR)"
	cp -R "$(BUILD_DIR)/html/"* "$(MANUAL_DIR)"

	rm "$(MANUAL_DIR)/index.html"
	mv "$(MANUAL_DIR)/contents.html" "$(MANUAL_DIR)/index.html"

	cd "$(MANUAL_DIR)" && find . -type f -name '*.html' -exec $(SED) -i 's|contents.html|index.html|g' {} +
	cd "$(MANUAL_DIR)" && find . -type f -name '*.html' -exec $(SED) -i 's|<p>Hosted on <a href="https://pages.github.com/">GitHub Pages</a></p>||g' {} +


generate_css:
	@echo "Generating CSS files..."
	sass --no-source-map source/_themes/gridmonger/sass/docs.scss:source/_themes/gridmonger/static/css/docs.css
	sass --no-source-map source/_themes/gridmonger/sass/frontpage.scss:source/_themes/gridmonger/static/css/frontpage.css

watch_docs_css:
	sass --watch --poll source/_themes/gridmonger/sass/docs.scss:build/html/_static/css/docs.css

watch_frontpage_css:
	sass --watch --poll source/_themes/gridmonger/sass/frontpage.scss:build/html/_static/css/frontpage.css

