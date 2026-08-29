# Convenience wrapper around the three root modules.
#
#   make local-up                     bring the local stack up
#   make azure-plan ENV=dev           plan the dev Azure environment
#   make snowflake-apply ENV=dev      apply the Snowflake objects
#
# ENV selects the .tfvars file for the azure and snowflake targets.

TF      ?= terraform
ENV     ?= dev
ROOT    := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
LOCAL   := $(ROOT)environments/local
AZURE   := $(ROOT)environments/azure
SNOW    := $(ROOT)environments/snowflake

.PHONY: fmt validate \
        local-init local-plan local-up local-down local-output \
        azure-init azure-plan azure-apply azure-output \
        snowflake-init snowflake-plan snowflake-apply snowflake-output

fmt:
	$(TF) fmt -recursive $(ROOT)

validate:
	cd $(LOCAL) && $(TF) validate
	cd $(AZURE) && $(TF) validate
	cd $(SNOW)  && $(TF) validate

# --- local -----------------------------------------------------------------

local-init:
	cd $(LOCAL) && $(TF) init

local-plan: local-init
	cd $(LOCAL) && $(TF) plan

local-up: local-init
	cd $(LOCAL) && $(TF) apply -auto-approve

local-down:
	cd $(LOCAL) && $(TF) destroy -auto-approve

local-output:
	cd $(LOCAL) && $(TF) output

# --- azure -----------------------------------------------------------------
# Run `terraform init -backend-config=backend.$(ENV).hcl` once by hand before
# the first plan; the target below assumes the backend is already configured.

azure-init:
	cd $(AZURE) && $(TF) init -backend-config=backend.$(ENV).hcl

azure-plan:
	cd $(AZURE) && $(TF) plan -var-file=$(ENV).tfvars -out=$(ENV).tfplan

azure-apply:
	cd $(AZURE) && $(TF) apply $(ENV).tfplan

azure-output:
	cd $(AZURE) && $(TF) output

# --- snowflake -------------------------------------------------------------

snowflake-init:
	cd $(SNOW) && $(TF) init

snowflake-plan: snowflake-init
	cd $(SNOW) && $(TF) plan -var-file=$(ENV).tfvars

snowflake-apply: snowflake-init
	cd $(SNOW) && $(TF) apply -var-file=$(ENV).tfvars

snowflake-output:
	cd $(SNOW) && $(TF) output
