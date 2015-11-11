# OBO Purls Makefile
# 2015-11-06
# James A. Overton <james@overton.ca>
#
# This file contains code for working with
# Open Biomedical Ontoloiges (OBO)
# Persistent Uniform Resource Locators (PURLs).
#
# WARNING: This file contains significant whitespace!
# Make sure that your text editor distinguishes tabs from spaces.
#
# Required software:
#
# - [GNU Make](http://www.gnu.org/software/make/) to run this file
# - [kwalify](http://www.kuwata-lab.com/kwalify/) for YAML validation
# - [Python 3](https://www.python.org/downloads/) to run scripts
# - [PyYAML](http://pyyaml.org/wiki/PyYAML) for translation to Apache


### Configuration

# Run operations on these ontologies.
ONTOLOGY_IDS := obi

# Default goal: Generate an .htaccess file for each id in ONTOLOGY_IDS.
all: clean validate build

build: www/obo

clean:
	rm -rf tests validations www/obo

# Use awk with tabs
AWK := awk -F "	" -v "OFS=	"

# Do not automatically delete intermediate files.
.SECONDARY:

# These goals do not correspond to files.
.PHONY: all clean validate test test-production fetch migrate


### Validate YAML Config
#
# Use kwalify and the config/config.schema.yml
# to validate YAML configuration file format.
validations:
	mkdir -p $@

# Validate a single YAML configuration file.
validations/%.txt: config/%.yml config/config.schema.yml validations
	kwalify -f config/config.schema.yml $< > $@
	@cat $@

# Validate configuration for all ontologies in ONTOLOGY_IDS.
# If any INVALID results are found, print them and exit with an error.
validate: validations/obo.txt $(foreach o,$(ONTOLOGY_IDS),validations/$o.txt)
	@grep -v 'valid.$$' validations/* && exit 1 || exit 0
	@grep 'INVALID' validations/* && exit 1 || exit 0


### Generate Apache Config
#
# Convert the YAML configuration files
# to Apache .htaccess files with RedirectMatch directives.
www/obo/%/.htaccess: config/%.yml
	mkdir -p www/obo/$*
	echo '# DO NOT EDIT THIS FILE!' > $@
	echo '# Automatically generated from $< on' $$(date) >> $@
	echo '' >> $@
	scripts/translate.py /obo/$* < $< >> $@

# Convert the special global OBO configuration file.
www/obo/.htaccess: config/obo.yml
	mkdir -p www/obo
	echo '# DO NOT EDIT THIS FILE!' > $@
	echo '# Automatically generated from $< on' $$(date) >> $@
	echo '' >> $@
	scripts/translate.py /obo < $< >> $@

# Convert configuration for all ontologies in ONTOLOGY_IDS.
www/obo: www/obo/.htaccess $(foreach o,$(ONTOLOGY_IDS),www/obo/$o/.htaccess)


### Test Development Apache Config
#
# Make HTTP HEAD requests against a local development server
# to ensure that redirects are working properly.
DEVELOPMENT := 172.16.100.10

tests/development:
	mkdir -p $@

# Run tests for a single YAML configuration file.
# against the developmentelopment server,
# making requests every 0.01 seconds.
tests/development/%.tsv: config/%.yml tests/development
	< $< \
	scripts/test.py $(DEVELOPMENT) /obo/$* 0.01 \
	> $@

tests/development/obo.tsv: config/obo.yml tests/development
	< $< \
	scripts/test.py $(DEVELOPMENT) /obo 0.01 \
	> $@

# Run tests for all ontologies in ONTOLOGY_IDS and write a report.
tests/development/failed.tsv: tests/development/obo.tsv $(foreach o,$(ONTOLOGY_IDS),tests/development/$o.tsv)
	< $< \
	head -n1 \
	| sed 's/^Result/File	Result/' \
	> $@
	@grep '^FAIL' tests/development/* \
	| sed 's/:/	/' \
	>> $@

# If there is more than one line in failed.tsv, then there were errors.
test: tests/development/failed.tsv
	@test $$(wc -l < $<) -eq 1 || (echo 'Errors found; see $<'; exit 1)


### Test Production Apache Config
#
# Make HTTP HEAD requests against the production server
# to ensure that redirects are working properly.
PRODUCTION := purl.obolibrary.org

tests/production:
	mkdir -p $@

# Run tests for a single YAML configuration file
# against the production server,
# making requests every 1 second.
tests/production/%.tsv: config/%.yml tests/production
	< $< \
	scripts/test.py $(PRODUCTION) /obo/$* 1 \
	> $@

# Run tests for all ontologies in ONTOLOGY_IDS and write a report.
tests/production/failed.tsv: tests/production/obo.tsv $(foreach o,$(ONTOLOGY_IDS),tests/production/$o.tsv)
	< $< \
	head -n1 \
	| sed 's/^Result/File	Result/' \
	> $@
	@grep '^FAIL' tests/production/* \
	| sed 's/:/	/' \
	>> $@

# If there is more than one line in failed.tsv, then there were errors.
test-production: tests/production/failed.tsv
	@test $$(wc -l < $<) -eq 1 || (echo 'Errors found; see $<'; exit 1)


### Fetch from OCLC
#
# Fetch records from OCLC in XML format.
migrations:
	mkdir -p $@

OCLC_XML = https://purl.org/admin/purl/?target=&seealso=&maintainers=&explicitmaintainers=&tombstone=false&p_id=

# Fetch first 100 PURLs for a given path from OCLC in XML format.
migrations/%.xml: migrations
	sleep 5
	curl -o $@ "$(OCLC_XML)/obo/$*/*"

# Fetch XML for all ontologies in the ONTOLOGY_IDS list.
fetch: $(foreach o,$(ONTOLOGY_IDS),migrations/$o.xml)


### Migrate Configuration from OCLC
#
# Translate OCLC XML files into YAML files.
# This should be a one-time migration.
# WARN: Don't overwrite newer configuration files!
config:
	mkdir -p $@

# Use xmlstarlet to convert XML to YAML format,
# then tweak the results with sed.
# Require XML file to be fetched manually.
# Do not overwrite existing config file.
config/%.yml:
	@test -s migrations/$*.xml || (echo 'Run "make migrations/$*.xml" first'; exit 1)
	@test ! -s $@ || (echo 'Refusing to overwrite $@'; exit 1)
	scripts/migrate.py /obo/$* < migrations/$*.xml > $@

# Migrate XML to YAML for all ontologies in the ONTOLOGY_IDS list.
migrate: $(foreach o,$(ONTOLOGY_IDS),config/$o.yml)

