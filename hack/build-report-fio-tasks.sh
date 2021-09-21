#!/bin/sh

set -ex

NOTEBOOK="/home/splat/notebooks/results-fio-task-profiles.ipynb"
RESULT_BASE="/results/byGroup-"

create_report() {
	JOB_GROUP=$1
	echo -ne "\n\nRunning notebook for JOB_GROUP=${JOB_GROUP} \n"
	podman exec $(podman ps --filter name=ocp-bench-reports --format "{{.ID}}") /bin/bash -c "export JOB_GROUP=${JOB_GROUP}; jupyter nbconvert --execute --to notebook ${NOTEBOOK} --stdout > ${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}.ipynb" || true
	podman exec $(podman ps --filter name=ocp-bench-reports --format "{{.ID}}") /bin/bash -c "export JOB_GROUP=${JOB_GROUP}; jupyter nbconvert --execute --to html ${NOTEBOOK} --stdout > ${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" || true
	if [[ -f ".local${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" ]]; then
		echo "Report crerated with success on path: .local${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" 
	else
		echo "ERROR to crerate report on path: .local${RESULT_BASE}${JOB_GROUP}/parser/${JOB_GROUP}-nb.html" 
	fi
}

create_report "b3_loop1"
create_report "b3_loop10"
create_report "b4_loop1"
create_report "b4_loop5"
