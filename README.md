# openshift-cluster-benchmark-lab

Tool to provisioning OCP cluster and run pre-build benchmark tests.

The configuration will be created dinamicaly with a pre-set of cluster profiles (customized), once the cluster is provisioned, it will  start a set of pre-defined tests and collect the results locally.

The scripts run on top o openshift-installer using IPI method.

Use cases:
- benchmark specific components from a cloud provider. Eg:
  * benchamark AWS disks gp2 and gp3, then compare with Azure disks
  * test different instance types with a custom Installer binary
- help on daily tasks spining-up clusters configuration


## Usage

Edit the .env file with our credentials:

~~~
cp .env-sample .env
vim .env
~~~

The variables must be set:
- `SSH_PUB_KEYS` : ssh public keys to be added to cluster nodes
- `PULL_SECRET`  : your pull secret
- `OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE` : (optional) if desired, override installer image release

### `cluster` command

The `cluster` command will abastract openshift-installer tasks, creating dynamic configuration based on cluster profiles.

The rendered configuration for a cluster will be saved on local storage `.local/cluster`, that contains:
- `${cluster}_rendered-runner-config.yaml`: dynamic variables created to be used to mount the install-config.yaml
- `${cluster}_install-config.yaml`: rendered install-config.yaml created by pre-defined profile
- `${cluster}/`: directory of `install-dir` openshift-installer option, that holds all installer stuffs
- `${cluster}-${TIMESTAMP}.tar.xz`: backup of data created before destroy/delete clusters

#### `cluster create`

> similar `openshift-install create cluster`

This command creates the install-config.yaml and run `openshift-install create cluster`.

Create a cluster named `c2awsm5x2xgp2` with profile `aws_m5x2xgp2`

~~~
ocp-benchmark cluster create \
    --cluster-profile aws_m5x2xgp2 \
    --cluster-name c2awsm5x2xgp2 --force
~~~

#### `cluster create --kubeconfig` or `cluster link`

Command:
```
ocp-benchmark cluster create \
    --cluster-name c2awsm5x2xgp2 --kubeconfig
```

Link existing cluster configuration (`$KUBECONFIG`) to `.local/cluster/{cluster-name}/auth/kubeconfig`

Create a pseudo cluster to be used on this project. That command will read the `${KUBECONFIG}` env var and create a local configuration on , then it will be possible to run tests in existing clusters / skiping provisioning flow.

#### `cluster setup`

> similar `openshift-install create (manifests|ignition-configs)`

If you want to render the install-config and create manifests, run the `cluster setup`:

~~~
ocp-benchmark cluster setup \
    --cluster-profile aws_m5x2xgp2 \
    --cluster-name c2awsm5x2xgp2
~~~

Then, check-out the changes and run the `cluster install`.

#### `cluster install`

> similar `openshift-install create cluster`

Install a cluster from a already created install dir:

~~~
ocp-benchmark cluster install \
    --cluster-profile aws_m5x2xgp2 \
    --cluster-name c2awsm5x2xgp2
~~~

#### `cluster destroy`

- Remove a cluster:

~~~
ocp-benchmark cluster destroy --cluster-name c2awsm5x2xgp2
~~~

#### `cluster check / ping`

- Check / ping current cluster

~~~
ocp-benchmark cluster ping --cluster-name c2awsm5x2xgp2
~~~

### `run` command

#### run jobs to the cluster

Jobs will bind the cluster (previous created/linked) with `benchmark_profile`, which defines what tasks will run on the cluster. It's possible to run N jobs to the same cluster, the `job-name` should be unique on the project.

All the results will be collected to local storage path: `.local/results`, if grouped (`job-group`) will be `.local/results/byGroup-${group_name}`

Examples:

- Create a job [`c1`] binding benchmark profile [`fio_allTasks_masterNodes`] to a cluster [`c1gp2x1`]:

~~~
./ocp-benchmark run \
    --cluster-name c1gp2x1 \
    --job-name c1 \
    --benchmark-profile fio_allTasks_masterNodes
~~~

- Create many jobs and group the results into the same directory (`.local/results/byGroup-b3`):

~~~
./ocp-benchmark run \
    --cluster-name c1gp2x1 \
    --job-name c1 \
    --job-group b3 \
    --benchmark-profile fio_allTasks_masterNodes

./ocp-benchmark run \
    --cluster-name c3gp3x1 \
    --job-name c3 \
    --job-group b3 \
    --benchmark-profile fio_allTasks_masterNodes
~~~

- override the loop count value from a task definition to `10`, which means to run each task 10 times, instead of `1`(default):

~~~
./ocp-benchmark run \
    --cluster-name c3gp3x1 \
    --job-name c3 \
    --job-group b3 \
    --benchmark-profile fio_allTasks_masterNodes
    --task-loop 10
~~~


## Customization

You can edit any `config.yaml` parameter to create customized cluster installation.

> TODO add --config option to point to a custom config.

Please see bellow some examples to customize the project.

### create a new cluster profile

You may need to create a custom cluster profile when:
- change instance type
- change volume type
- run custom patchs
- run a custom installer

1. create a task function in `src/cluster_jobs`. Function should have name prefix `task_`
2. create a task profile in `config.yaml: task_profiles.${name}`
3. bind the new task to a benchmark profile: `benchmark_profiles.${name}.task_profiles[]`

### create a new task

1. create a task function in `src/cluster_jobs`. Function should have name prefix `task_`
2. create a task profile in `config.yaml: task_profiles.${name}`
3. bind the new task to a benchmark profile: `benchmark_profiles.${name}.task_profiles[]`

### create a new benchmark profile (TODO rename to 'job profile')

### create a create new manifest patch

> TODO

# FAQ

Q: How the tasks will run into the cluster?
A: Depends on the task executior (function that define the task in `src/cluster_jobs` named `task_${task_name}`). The FIO implementation will run each task profile using `oc debug` thoughts, keeping the connection opened until it finished. It's possible to schedule a job and whait to finish, but not supported currently.

Q: Is the tasks run in parallel?
A: No, the tasks will run one-by-one from the `task_profiles` defined on `benchmark_profile`, regardless if has been failed.

Q: Is the jobs run in parallel?
A: Yes, the jobs will run in paralel on each node defined on `target_node_strategy`

Q: Does this project override the installer?
A: No, it automate the process to handle customizations (patch manifests, using custom builds, etc) on installer to run benchmark jobs in different clusters


