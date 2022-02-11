# openshift-cluster-orchestrator

A tool that runs above `openshift-installer` to orchestrate the configuration pre-install applying configuration in the manifests, or patches on the manifests before triggering the `create cluster`.

The tool also orchestrates initial benchmark jobs to a fresh cluster, for example running the benchmark in specific components like disks, etcd, node CPU, etc, interacting with projects:
- openshift-installer
- FIO
- benchmark-operator

The cluster configuration will be created dynamically with a pre-set of cluster profiles (customized), once the cluster is provisioned, it will start a set of pre-defined tests and collect the results locally.

The scripts run on top of `openshift-installer` using IPI method.

Use cases:
- benchmark specific components from a cloud provider. Eg:
  * benchmark AWS disks gp2 and gp3, then compare with Azure disks
  * test different instance types with a custom Installer binary
- help on daily tasks spinning-up clusters configuration

## Install

### Requirements

- yq == 2.x
- jq
- openshift-installer
- oc

## Usage

Create the `.env` file with our credentials.

~~~bash
cp .env-sample .env
# adjust .env
~~~

The variables must be set:
- `SSH_PUB_KEYS` : ssh public keys to be added to cluster nodes
- `PULL_SECRET`  : your pull secret
- `OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE` : (optional) if desired, override installer image release
- `DEFAULT_BASEDOMAIN_AWS` : (optional) if set, the default baseDomain will be used for AWS provider (see config.yaml)
- `DEFAULT_BASEDOMAIN_AZURE` : (optional) if set, the default baseDomain will be used for Azure provider (see config.yaml)

### `cluster` command

The `cluster` command will abstract `openshift-installer` tasks, creating dynamic configuration based on cluster profiles, rendering a custom configuration based on pre-defined profiles from `config.yaml`.

The structure below will be created for each cluster and saved on local storage, `.local/cluster/` directory:
- `${cluster}_rendered-runner-config.yaml`: dynamic variables created to be used to mount the `install-config.yaml`
- `${cluster}_install-config.yaml`: rendered `install-config.yaml` created by pre-defined profile (backup of original)
- `${cluster}/`: directory of `--install-dir` argument from `openshift-installer`. This path will hold all installer stuff
- `${cluster}-${TIMESTAMP}.tar.xz`: backup of data created before destroy/delete clusters

#### `cluster create`

> similar `openshift-install create cluster`

This command creates the `install-config.yaml` and runs `openshift-install create cluster`.

**Examples:**

- Create a cluster named `c2awsm5x2xgp2` with profile `aws_m5x2xgp2`

~~~bash
oco cluster create \
    --cluster-profile aws_m5x2xgp2 \
    --cluster-name c2awsm5x2xgp2 --force
~~~

- Create a cluster in AWS with manual STS mode:

~~~bash
oco cluster create \
    --cluster-profile labccosts \
    --cluster-name aws_dev_cco_sts
~~~


#### `cluster create --kubeconfig` or `cluster link`

Command:
```
oco cluster create \
    --cluster-name c2awsm5x2xgp2 --kubeconfig
```

Link existing cluster configuration (`$KUBECONFIG`) to `.local/cluster/{cluster-name}/auth/kubeconfig`

Create a pseudo cluster to be used on this project. This command reads the `${KUBECONFIG}` env var and creates a local configuration on local storage, then it will be possible to run tests in existing clusters / skipping provisioning flow.

#### `cluster setup`

> similar `openshift-install create (manifests|ignition-configs)`

If you want to render the install-config and create manifests, run the `cluster setup`:

~~~
oco cluster setup \
    --cluster-profile aws_m5x2xgp2 \
    --cluster-name c2awsm5x2xgp2
~~~

If `OPT_CLUSTER_IGNITION_ONLY` is set, the ignition-configs will be created:

~~~bash
OPT_CLUSTER_IGNITION_ONLY=true
oco cluster setup \
    --cluster-profile aws_m5x2xgp2 \
    --cluster-name c2awsm5x2xgp2
~~~

Then, check out the changes and run the `cluster install`.

#### `cluster install`

> similar `openshift-install create cluster`

Install a cluster from an already created install dir:

~~~
oco cluster install \
    --cluster-profile aws_m5x2xgp2 \
    --cluster-name c2awsm5x2xgp2
~~~

#### `cluster destroy`

- Remove a cluster:

~~~bash
oco cluster destroy --cluster-name c2awsm5x2xgp2
~~~

#### `cluster check / ping`

- Check/ping current cluster

~~~bash
oco cluster ping --cluster-name c2awsm5x2xgp2
~~~

### `run` command

#### run jobs to the cluster

Jobs will bind the cluster (previously created/linked) with `benchmark_profile`, which defines what tasks will run on the cluster. It's possible to run N jobs to the same cluster, the `job-name` should be unique on the project.

All the results will be collected to local storage path: `.local/results`, if grouped (`job-group`) will be `.local/results/byGroup-${group_name}`

Examples:

1) Create a job named `fio_ebs_gp` binding benchmark profile `fio_psync_singleMaster` to run on the cluster [`ocp_aws`]:

~~~bash
oco run \
    --cluster-name ocp_aws \
    --job-name fio_ebs_gp \
    --benchmark-profile fio_psync_singleMaster
~~~

The profile `fio_psync_singleMaster` runs [the recommended](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/benchmark_procedures.html) benckmark using FIO on General Pourpose (gp) EBS on AWS, using the engine `psync` with operations `randread`, `randwrite` and `randrw` (random read or/and write).

2) Create many jobs and group the results into the same directory (`.local/results/byGroup-b3`):

~~~bash
oco run \
    --cluster-name c1gp2x1 \
    --job-name c1 \
    --job-group b3 \
    --benchmark-profile fio_allTasks_masterNodes

oco run \
    --cluster-name c3gp3x1 \
    --job-name c3 \
    --job-group b3 \
    --benchmark-profile fio_allTasks_masterNodes
~~~

3) override the loop count value from a task definition to `10`, which means to run each task 10 times, instead of `1`(default):

~~~bash
oco run \
    --cluster-name c3gp3x1 \
    --job-name c3 \
    --job-group b3 \
    --benchmark-profile fio_allTasks_masterNodes
    --task-loop 10
~~~

## Customization

You can edit any `config.yaml` parameter to create a customized cluster installation.

Please see below some examples to customize the project.

### create a new cluster profile

You may need to create a custom cluster profile when:
- change the instance type
- change volume type
- run custom patches
- run a custom installer

1. create a task function in `src/cluster_jobs`. The function should have the name prefix `task_`
2. create a task profile in `config.yaml: task_profiles.${name}`
3. bind the new task to a benchmark profile: `benchmark_profiles.${name}.task_profiles[]`

### create a new task

1. create a task function in `src/cluster_jobs`. Function should have name prefix `task_`
2. create a task profile in `config.yaml: task_profiles.${name}`
3. bind the new task to a benchmark profile: `benchmark_profiles.${name}.task_profiles[]`


## FAQ

Q: How the tasks will run into the cluster?
A: Depends on the task executor (function that define the task in `src/cluster_jobs` named `task_${task_name}`). The FIO implementation will run each task profile using `oc debug` thoughts, keeping the connection opened until it is finished. It's possible to schedule a job and wait to finish, but not supported currently.

Q: Are the tasks run in parallel?
A: No, the tasks will run one-by-one from the `task_profiles` defined on `benchmark_profile`, regardless if has been failed.

Q: Are the jobs run in parallel?
A: Yes, the jobs will run in parallel on each node defined on `target_node_strategy`

Q: Does this project override the installer?
A: No, it automates the process to handle customizations (patch manifests, using custom builds, etc) on the installer to run benchmark jobs in different clusters


<!--
ToDo:
### create a new benchmark profile (TODO rename to 'job profile')
### create a new manifest patch
> TODO
--!>
