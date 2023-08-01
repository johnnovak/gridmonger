# Makefile for Sphinx documentation

SPHINXOPTS   ?=
SPHINXBUILD  ?= sphinx-build
SOURCEDIR    = source
BUILDDIR     = build
SITEDIR      = ../docs
MANUALDIR    = ../Manual

.PHONY: clean

clean:
	@$(SPHINXBUILD) -M clean "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

html:
	@$(SPHINXBUILD) -M html "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

gen_html: clean generate_css html


build_site: gen_html
	cp "$(BUILDDIR)/html/index.html" "$(SITEDIR)/index.html"

	rm -rf "$(SITEDIR)/manual"
	mkdir "$(SITEDIR)/manual"
	cp "$(BUILDDIR)/html/"*html "$(SITEDIR)/manual"
	cp -R "$(BUILDDIR)/html/appendixes" "$(SITEDIR)/manual"

	rm -rf "$(SITEDIR)/_static"
	cp -R "$(BUILDDIR)/html/_static" "$(SITEDIR)/_static"
	cd "$(SITEDIR)/manual" && ln -s ../_static _static


build_manual: gen_html
	rm -rf "$(MANUALDIR)"
	mkdir -p "$(MANUALDIR)"
	cp "$(BUILDDIR)/html/"*html "$(MANUALDIR)"
	cp -R $(BUILDDIR)/html/appendixes "$(MANUALDIR)/appendixes"

	mkdir -p "$(MANUALDIR)/_static/css"
	cp -R "$(BUILDDIR)/html/_static/css/docs.css" "$(MANUALDIR)/_static/css"
	cp -R "$(BUILDDIR)/html/_static/css/glightbox.min.css" "$(MANUALDIR)/_static/css"

	cp -R "$(BUILDDIR)/html/_static/font" "$(MANUALDIR)/_static"
	cp -R "$(BUILDDIR)/html/_static/js" "$(MANUALDIR)/_static"

	mkdir "$(MANUALDIR)/_static/img"
	cp "$(BUILDDIR)/html/_static/img/"*.png "$(MANUALDIR)/_static/img"

	rm "$(MANUALDIR)/index.html"
	mv "$(MANUALDIR)/contents.html" "$(MANUALDIR)/index.html"

	cd "$(MANUALDIR)" && find . -type f -name '*.html' -exec sed -i 's|contents.html|index.html|g' {} +
	cd "$(MANUALDIR)" && find . -type f -name '*.html' -exec sed -i 's|<p>Hosted on <a href="https://pages.github.com/">GitHub Pages</a></p>||g' {} + 


generate_css:
	@echo "Generating CSS files..."
	sass --no-source-map source/_themes/gridmonger/sass/docs.scss:source/_themes/gridmonger/static/css/docs.css
	sass --no-source-map source/_themes/gridmonger/sass/frontpage.scss:source/_themes/gridmonger/static/css/frontpage.css

watch_docs_css:
	sass --watch --poll source/_themes/gridmonger/sass/docs.scss:build/html/_static/css/docs.css

watch_frontpage_css:
	sass --watch --poll source/_themes/gridmonger/sass/frontpage.scss:build/html/_static/css/frontpage.css

