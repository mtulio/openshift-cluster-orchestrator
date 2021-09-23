
JUPLAB_IMAGE ?= mtulio/jupyter-lab:latest
PROJECT_IMAGE ?= ocp-bench-reports
CONTAINER ?= ocp-bench-reports

.PHONY: build
build:
	podman build -t $(PROJECT_IMAGE) .

.PHONY: run-container
run-container:
	podman run --rm \
		-v $(PWD)/:/project:z \
		-v $(PWD)/.local/results:/results:z \
		-v $(PWD)/reports:/home/splat/notebooks:z \
		-p 8080:8888 \
		--env-file $(PWD)/.env-container \
		--name $(CONTAINER) \
		-d $(PROJECT_IMAGE)
	sleep 5

.PHONY: show-notebook
show-notebook:
	podman exec $(shell podman ps --filter name=$(CONTAINER) --format "{{.ID}}") /bin/bash -c 'jupyter notebook list'

.PHONY: run
run: run-container show-notebook 

# Run notebook to create a custom html and nb converted
.PHONY: report
report:
	hack/build-report-fio-tasks.sh

.PHONY: clean
clean:
	podman rm -f $(shell podman ps --filter name=$(CONTAINER) --format "{{.ID}}")
