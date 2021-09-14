#!/bin/sh

NOTEBOOK="/home/splat/notebooks/results-fio-task-profiles.ipynb"
RESULT_BASE="/results/byGroup-"

JOB_GROUP=b3_loop1
echo "Running notebook for JOB_GROUP=${JOB_GROUP}"
podman exec $(podman ps --filter name=ocp-bench-reports --format "{{.ID}}") /bin/bash -c "export JOB_GROUP=${JOB_GROUP}; jupyter nbconvert --execute --to html ${NOTEBOOK} --stdout > ${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html"
if [[ -f ".local${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" ]]; then
	echo "Report crerated with success on path: .local${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" 
else
	echo "ERROR to crerate report on path: .local${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" 
fi

JOB_GROUP=b3_loop10
echo "Running notebook for JOB_GROUP=${JOB_GROUP}"
podman exec $(podman ps --filter name=ocp-bench-reports --format "{{.ID}}") /bin/bash -c "export JOB_GROUP=${JOB_GROUP}; jupyter nbconvert --execute --to html ${NOTEBOOK} --stdout > ${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html"
if [[ -f ".local${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" ]]; then
	echo "Report crerated with success on path: .local${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" 
else
	echo "ERROR to crerate report on path: .local${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" 
fi
