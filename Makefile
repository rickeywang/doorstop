# Python settings
ifndef TRAVIS
	PYTHON_MAJOR := 3
	PYTHON_MINOR := 4
endif

# Project settings
PROJECT := Doorstop
PACKAGE := doorstop
SOURCES := Makefile setup.py $(shell find $(PACKAGE) -name '*.py')
YAML := $(shell find . -name '*.yml' -not -path '*/test/files/*')
EGG_INFO := $(subst -,_,$(PROJECT)).egg-info

# System paths
PLATFORM := $(shell python -c 'import sys; print(sys.platform)')
ifneq ($(findstring win32, $(PLATFORM)), )
	SYS_PYTHON_DIR := C:\\Python$(PYTHON_MAJOR)$(PYTHON_MINOR)
	SYS_PYTHON := $(SYS_PYTHON_DIR)\\python.exe
	SYS_VIRTUALENV := $(SYS_PYTHON_DIR)\\Scripts\\virtualenv.exe
	# https://bugs.launchpad.net/virtualenv/+bug/449537
	export TCL_LIBRARY=$(SYS_PYTHON_DIR)\\tcl\\tcl8.5
else
	SYS_PYTHON := python$(PYTHON_MAJOR)
	ifdef PYTHON_MINOR
		SYS_PYTHON := $(SYS_PYTHON).$(PYTHON_MINOR)
	endif
	SYS_VIRTUALENV := virtualenv
endif

# virtualenv paths
ENV := env
ifneq ($(findstring win32, $(PLATFORM)), )
	BIN := $(ENV)/Scripts
	OPEN := cmd /c start
else
	BIN := $(ENV)/bin
	ifneq ($(findstring cygwin, $(PLATFORM)), )
		OPEN := cygstart
	else
		OPEN := open
	endif
endif

# virtualenv executables
PYTHON := $(BIN)/python
PIP := $(BIN)/pip
EASY_INSTALL := $(BIN)/easy_install
RST2HTML := $(PYTHON) $(BIN)/rst2html.py
PDOC := $(PYTHON) $(BIN)/pdoc
PEP8 := $(BIN)/pep8
PEP8RADIUS := $(BIN)/pep8radius
PEP257 := $(BIN)/pep257
PYLINT := $(BIN)/pylint
PYREVERSE := $(BIN)/pyreverse
NOSE := $(BIN)/nosetests
PYTEST := $(BIN)/py.test
COVERAGE := $(BIN)/coverage

# Flags for PHONY targets
DEPENDS_CI := $(ENV)/.depends-ci
DEPENDS_DEV := $(ENV)/.depends-dev
ALL := $(ENV)/.all

# Main Targets ###############################################################

.PHONY: all
all: depends $(ALL)
$(ALL): $(SOURCES) $(YAML)
	$(MAKE) doc pep8 pep257
	touch $(ALL)  # flag to indicate all setup steps were successful

.PHONY: ci
ci: doorstop pep8 pep257 test tests tutorial

# Development Installation ###################################################

.PHONY: env
env: .virtualenv $(EGG_INFO)
$(EGG_INFO): Makefile setup.py
	VIRTUAL_ENV=$(ENV) $(PYTHON) setup.py develop
	touch $(EGG_INFO)  # flag to indicate package is installed

.PHONY: .virtualenv
.virtualenv: $(PIP)
$(PIP):
	$(SYS_VIRTUALENV) --python $(SYS_PYTHON) $(ENV)

.PHONY: depends
depends: depends-ci depends-dev

.PHONY: depends-ci
depends-ci: env Makefile $(DEPENDS_CI)
$(DEPENDS_CI): Makefile
	$(PIP) install --upgrade pep8 pep257 pylint nose coverage
	touch $(DEPENDS_CI)  # flag to indicate dependencies are installed

.PHONY: depends-dev
depends-dev: env Makefile $(DEPENDS_DEV)
$(DEPENDS_DEV): Makefile
	$(PIP) install --upgrade pep8radius pygments docutils pdoc wheel sphinx
	touch $(DEPENDS_DEV)  # flag to indicate dependencies are installed

# Development Usage ##########################################################

.PHONY: doorstop
doorstop: env
	$(BIN)/doorstop --warn-all --error-all --quiet

.PHONY: gui
gui: env
	$(BIN)/doorstop-gui

.PHONY: serve
serve: env
	$(SUDO) $(BIN)/doorstop-server --debug --launch --port 80

# Documentation ##############################################################

.PHONY: doc
doc: readme reqs uml apidocs sphinx

.PHONY: pages
pages: reqs-html sphinx
	cp -r docs/gen/ pages/reqs/
	cp -r docs/sphinx/_build pages/docs/

.PHONY: readme
readme: depends-dev README-github.html README-pypi.html
README-github.html: README.md
	pandoc -f markdown_github -t html -o README-github.html README.md
README-pypi.html: README.rst
	$(RST2HTML) README.rst README-pypi.html
README.rst: README.md
	pandoc -f markdown_github -t rst -o README.rst README.md

apidocs: depends-dev apidocs/$(PACKAGE)/index.html
apidocs/$(PACKAGE)/index.html: $(SOURCES)
	$(PDOC) --html --overwrite $(PACKAGE) --html-dir apidocs

.PHONY: sphinx
sphinx: depends-dev docs/sphinx/_build
docs/sphinx/_build: $(SOURCES)
	$(BIN)/sphinx-apidoc -o docs/sphinx/ doorstop
	$(BIN)/sphinx-build -b html docs/sphinx docs/sphinx/_build
	touch docs/sphinx/_build  # flag to indicate sphinx docs generated

.PHONY: reqs
reqs: doorstop reqs-html reqs-md reqs-txt

.PHONY: reqs-html
reqs-html: env docs/gen/*.html
docs/gen/*.html: $(YAML)
	$(BIN)/doorstop publish all docs/gen --html

.PHONY: reqs-md
reqs-md: env docs/gen/*.md
docs/gen/*.md: $(YAML)
	$(BIN)/doorstop publish all docs/gen --markdown

.PHONY: reqs-txt
reqs-txt: env docs/gen/*.txt
docs/gen/*.txt: $(YAML)
	$(BIN)/doorstop publish all docs/gen --text

.PHONY: uml
uml: depends-dev docs/*.png
docs/*.png: $(SOURCES)
	$(PYREVERSE) $(PACKAGE) -p $(PACKAGE) -f ALL -o png --ignore test
	- mv -f classes_$(PACKAGE).png docs/classes.png
	- mv -f packages_$(PACKAGE).png docs/packages.png

.PHONY: read
read: doc
	$(OPEN) docs/gen/index.html
	$(OPEN) apidocs/$(PACKAGE)/index.html
	$(OPEN) docs/sphinx/_build/index.html
	$(OPEN) README-pypi.html
	$(OPEN) README-github.html

# Static Analysis ############################################################

.PHONY: check
check: pep8 pep257 pylint

.PHONY: pep8
pep8: depends-ci
	# E501: line too long (checked by PyLint)
	$(PEP8) $(PACKAGE) --ignore=E501

.PHONY: pep257
pep257: depends-ci
	# D102: docstring missing (checked by PyLint)
	# D202: No blank lines allowed *after* function docstring
	$(PEP257) $(PACKAGE) --ignore=D102,D202

.PHONY: pylint
pylint: depends-ci
	$(PYLINT) $(PACKAGE) --rcfile=.pylintrc

.PHONY: fix
fix: depends-dev
	$(PEP8RADIUS) --docformatter --in-place

# Testing ####################################################################

.PHONY: test
test: depends-ci
	$(NOSE) --config=.noserc

.PHONY: tests
tests: depends-ci
	TEST_INTEGRATION=1 $(NOSE) --config=.noserc --cover-package=$(PACKAGE) -xv

.PHONY: tutorial
tutorial: env
	$(PYTHON) $(PACKAGE)/cli/test/test_tutorial.py

# Cleanup ####################################################################

.PHONY: clean
clean: .clean-dist .clean-test .clean-doc .clean-build
	rm -rf $(ALL)

.PHONY: clean-env
clean-env: clean
	rm -rf $(ENV)

.PHONY: clean-all
clean-all: clean clean-env .clean-workspace

.PHONY: .clean-build
.clean-build:
	find $(PACKAGE) -name '*.pyc' -delete
	find $(PACKAGE) -name '__pycache__' -delete
	rm -rf $(EGG_INFO)

.PHONY: .clean-doc
.clean-doc:
	rm -rf apidocs README*.html README.rst docs/*.png docs/gen
	rm -rf docs/sphinx/modules.rst docs/sphinx/doorstop*.rst docs/sphinx/_build
	rm -rf pages/docs/ pages/reqs/

.PHONY: .clean-test
.clean-test:
	rm -rf .coverage

.PHONY: .clean-dist
.clean-dist:
	rm -rf dist build

.PHONY: .clean-workspace
.clean-workspace:
	rm -rf *.sublime-workspace

# Release ####################################################################

.PHONY: register
register: doc
	$(PYTHON) setup.py register

.PHONY: dist
dist: check doc test tests
	$(PYTHON) setup.py sdist
	$(PYTHON) setup.py bdist_wheel
	$(MAKE) read

.PHONY: upload
upload: .git-no-changes doc
	$(PYTHON) setup.py register sdist upload
	$(PYTHON) setup.py bdist_wheel upload

.PHONY: .git-no-changes
.git-no-changes:
	@if git diff --name-only --exit-code;         \
	then                                          \
		echo Git working copy is clean...;        \
	else                                          \
		echo ERROR: Git working copy is dirty!;   \
		echo Commit your changes and try again.;  \
		exit -1;                                  \
	fi;

# System Installation ########################################################

.PHONY: develop
develop:
	$(SYS_PYTHON) setup.py develop

.PHONY: install
install:
	$(SYS_PYTHON) setup.py install

.PHONY: download
download:
	pip install $(PROJECT)
