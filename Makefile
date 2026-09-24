.PHONY: pipeline build validate push vm dry-run clean lint

HOST            ?= chris@donnager-linux
REGISTRY_REF    ?=
VM_NAME         ?=
RUN_NOTES       ?=

PIPELINE := scripts/pipeline.sh
EXTRA_ARGS :=

ifdef REGISTRY_REF
EXTRA_ARGS += --registry-ref $(REGISTRY_REF)
endif
ifdef VM_NAME
EXTRA_ARGS += --vm-name $(VM_NAME)
endif

pipeline:
	$(PIPELINE) --host $(HOST) $(EXTRA_ARGS)

build:
	$(PIPELINE) --host $(HOST) $(EXTRA_ARGS) --dry-run

validate:
	scripts/hardening-verify.sh --phase all --verbose

push:
	$(PIPELINE) --host $(HOST) $(EXTRA_ARGS)

vm:
	$(PIPELINE) --host $(HOST) $(EXTRA_ARGS)

dry-run:
	$(PIPELINE) --host $(HOST) $(EXTRA_ARGS) --dry-run

clean:
ifndef VM_NAME
	$(error VM_NAME is required for clean, e.g. make clean VM_NAME=f44-hardened-...)
endif
	@read -p "destroy $(VM_NAME) and its volume on $(HOST)? [y/N] " ans; \
	[ "$$ans" = "y" ] || exit 1
	ssh $(HOST) "virsh -c qemu:///session destroy $(VM_NAME) || true; \
	             virsh -c qemu:///session undefine $(VM_NAME) || true; \
	             rm -f \$$HOME/vms/$(VM_NAME).qcow2 \$$HOME/vms/$(VM_NAME)-smoke.qcow2"

lint:
	bash -n scripts/pipeline.sh
	bash -n scripts/hardening-verify.sh
	bash -n scripts/lib/pipeline-lib.sh
	bash -n scripts/capture-state.sh
