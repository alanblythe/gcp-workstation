# Build + publish a NixOS GCE image.
#
# Usage:
#   make image           # build the raw.tar.gz locally (writes ./result-image)
#   make publish         # build, upload, and register as a GCE custom image
#   make clean           # drop the local build artifact
#
# Requires:
#   - nix with flakes enabled (`experimental-features = nix-command flakes`)
#   - gcloud CLI authenticated against PROJECT
#   - GCS bucket GCS_BUCKET (created on first publish via `make bucket`)

PROJECT     ?= $(shell gcloud config get-value project 2>/dev/null || echo "your-project-id")
REGION      ?= us-central1
GCS_BUCKET  ?= $(PROJECT)-nixos-images
FAMILY      ?= nixos-workstation
TIMESTAMP   := $(shell date -u +%Y%m%d-%H%M%S)
IMAGE_NAME  ?= nixos-workstation-$(TIMESTAMP)

.PHONY: image bucket upload register publish clean

image:
	nix build .#gce-image --out-link result-image

bucket:
	gcloud storage buckets describe gs://$(GCS_BUCKET) --project=$(PROJECT) >/dev/null 2>&1 || \
	  gcloud storage buckets create gs://$(GCS_BUCKET) \
	    --project=$(PROJECT) \
	    --location=$(REGION) \
	    --uniform-bucket-level-access

upload: image bucket
	gcloud storage cp result-image/*.raw.tar.gz \
	  gs://$(GCS_BUCKET)/$(IMAGE_NAME).tar.gz \
	  --project=$(PROJECT)

register:
	gcloud compute images create $(IMAGE_NAME) \
	  --source-uri=gs://$(GCS_BUCKET)/$(IMAGE_NAME).tar.gz \
	  --family=$(FAMILY) \
	  --project=$(PROJECT)

publish: upload register
	@echo
	@echo "Published image:"
	@echo "  projects/$(PROJECT)/global/images/$(IMAGE_NAME)"
	@echo "  family:  projects/$(PROJECT)/global/images/family/$(FAMILY)"
	@echo
	@echo "To boot a sibling VM from this image:"
	@echo "  cd ../ && terraform apply \\"
	@echo "    -var='create_nixos_sibling=true' \\"
	@echo "    -var='nixos_image=projects/$(PROJECT)/global/images/family/$(FAMILY)'"

clean:
	rm -f result-image
