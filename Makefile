VERBOSE ?= 0

.PHONY: rwoLwt
rwoLwt:
	ocamlbuild -verbose $(VERBOSE) src/rwoLwt.native

.PHONY: merlin
merlin:
	opam config subst .merlin

.PHONY: clean
clean:
	ocamlbuild -clean

.PHONY: distclean
distclean: clean
	rm -f .merlin
