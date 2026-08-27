EMACS ?= emacs
PACKAGE = org-gcal-view

.PHONY: test compile clean check

check: compile test

test:
	$(EMACS) -Q --batch -L . -l ert -l $(PACKAGE).el \
		-l test/$(PACKAGE)-test.el \
		-f ert-run-tests-batch-and-exit

compile:
	$(EMACS) -Q --batch -L . \
		--eval "(setq byte-compile-error-on-warn t)" \
		-f batch-byte-compile $(PACKAGE).el

clean:
	rm -f $(PACKAGE).elc
