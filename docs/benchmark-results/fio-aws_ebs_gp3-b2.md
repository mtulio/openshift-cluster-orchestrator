## Report FIO results for EBS Benchmark on gp2 and gp3

Scenario (clusters):
- t1: OCP cluster with 1x gp2
- t2: OCP cluster with 2x gp2 (etcd isolated)
- t3: OCP cluster with 1x gp3
- t4: OCP cluster with 2x gp3 (etcd isolated)

This report aggregates the data collected on "battery 2" (named `b2`), that tested all control plane disks on layouts described above.

The script to create the "battery 2" and collect the data is defined (by WIP script) [here](https://github.com/mtulio/openshift-cluster-benchmark-lab/blob/init/run-test.sh#L250-L271)

References:
 - [FIO doc](https://fio.readthedocs.io/en/latest/fio_doc.html)
 - This report (notebook): reports/fio-ebs_gp3-b2.ipynb
 - This report (markdown/exported): docs/examples/fio-ebs_gp3-b2.md


```python
# install dependencies
! pip install pandas
```

    Requirement already satisfied: pandas in /opt/conda/lib/python3.8/site-packages (1.3.2)
    Requirement already satisfied: pytz>=2017.3 in /opt/conda/lib/python3.8/site-packages (from pandas) (2021.1)
    Requirement already satisfied: numpy>=1.17.3 in /opt/conda/lib/python3.8/site-packages (from pandas) (1.21.2)
    Requirement already satisfied: python-dateutil>=2.7.3 in /opt/conda/lib/python3.8/site-packages (from pandas) (2.8.1)
    Requirement already satisfied: six>=1.5 in /opt/conda/lib/python3.8/site-packages (from python-dateutil>=2.7.3->pandas) (1.15.0)



```python
import os
import json
import pandas as pd
from IPython.display import display
```


```python
results_path=(f"/results")

results_fio = {}

# files is saved on the format: {battery_id}_{cluster_id}-fio-{hostname}.tar.gz
filter_results_by_battery="b2_"
```


```python
results_path
```




    '/results'




```python
results_dirs = []
for res in os.listdir(results_path):
    if not res.startswith(filter_results_by_battery):
        continue
    # expects that files was extracted. TODO: extract it
    if res.endswith(".tar.gz"):
        continue
    results_dirs.append(res)
```


```python
results_dirs
```




    ['b2_t1-fio-ip-10-0-137-218.ec2.internal',
     'b2_t2-fio-ip-10-0-142-88.ec2.internal',
     'b2_t3-fio-ip-10-0-137-24.ec2.internal',
     'b2_t4-fio-ip-10-0-133-152.ec2.internal']




```python
def build_node_result(battery_id, test_name, node_id):
    global results_fio
    try:
        x = results_fio[f"{battery_id}"]
    except KeyError:
        results_fio[f"{battery_id}"] = []
        pass
   
    return
```


```python
def discovery_and_load_fio_results(fpath, battery_id):
    """
    Walk through fio result dir and load JSON files with FIO results,
    returning only desired metrics for each test.
    """
    global results_fio
    for root, dirs, files in os.walk(fpath):
        for file in files:
            if file.endswith(".json"):
                fpath=os.path.join(root, file)
                with open(fpath, 'r') as f:
                    jdata=json.loads(f.read())

                    # Extract jobId from different standards (latest is fio_io_)
                    try:
                        jobId = jdata['jobs'][0]['jobname'].split('etcd')[1]
                    except Exception as e:
                        jobId = jdata['jobs'][0]['jobname'].split('fio_io_')[1]
                        pass

                    # Collect only desired data from entire FIO payload, for each test.
                    # battery_id is: batteryName+clusterName
                    # Considering only one job by result.
                    results_fio[f"{battery_id}"].append({
                        "node_name": f"{node_id}",
                        "jobname": jdata['jobs'][0]['jobname'],
                        "jobID": jobId,
                        "sync_lat_max_ms": (float(jdata['jobs'][0]['sync']['lat_ns']['max'])/1e+6),
                        "sync_lat_mean_ms": (float(jdata['jobs'][0]['sync']['lat_ns']['mean'])/1e+6),
                        "sync_lat_stddev_ms": (float(jdata['jobs'][0]['sync']['lat_ns']['stddev'])/1e+6),
                        "sync_lat_p99_ms": (float(jdata['jobs'][0]['sync']['lat_ns']['percentile']['99.000000'])/1e+6),
                        "sync_lat_p99.9_ms": (float(jdata['jobs'][0]['sync']['lat_ns']['percentile']['99.900000'])/1e+6)
                    })
```


```python
def aggregate_metric(metric_name):
    """
    Filter desired {metric_name}, extract the jobs (rows) for each cluster (columns),
    and return the data frame.
    JobId | {cluster1}  | [...clusterN |]
    #id   | metricValue | [...metricValue |]
    """
    global results_fio
    data_metric = {}
    for bat in results_fio.keys():
        for res_bat in results_fio[bat]:
            try:
                jid = data_metric[res_bat['jobID']]
            except KeyError:
                data_metric[res_bat['jobID']] = {
                    "job_Id": res_bat['jobID']
                }
                jid = data_metric[res_bat['jobID']]
                pass
            jid[bat] = res_bat[metric_name]
    data_pd = []
    for dk in data_metric.keys():
        row = []
        row.append(data_metric[dk]['job_Id'])
        data_pd.append(data_metric[dk])

    return pd.read_json(json.dumps(data_pd))
```


```python
def aggregate_by_node():
    """
    Aggregate all available metrics by node, returning a list of values for each one.
    {
        "{node_name}": [{...metrics}]
    }
    """
    global results_fio
    data_metrics = {}
    ignore_keys = ['node_name', 'jobname', 'jobID']
    for bat in results_fio.keys():
        for res_bat in results_fio[bat]:
            try:
                jid = data_metrics[res_bat['node_name']]
            except KeyError:
                data_metrics[res_bat['node_name']] = []

                pass
            metric = {
                    'battery_id': bat,
                    "job_Id": res_bat['jobID']
                }
            for rbk in res_bat.keys():
                if rbk in ignore_keys:
                    continue
                metric[rbk] = res_bat[rbk]
            data_metrics[res_bat['node_name']].append(metric)
    return data_metrics
```


```python
def _df_style_high(val, value_yellow=None, value_red=None):
    "Data frame styling / cell formating"
    color = None
    if (value_yellow != None) and (val >=  value_yellow):
        color = 'yellow'
    if (value_red != None) and (val >=  value_red):
        color = 'red'
    if color == None:
        return color
    #return f"color: {color}"
    return f"background-color: {color}"
```

## Discovery and Load results


```python
# Discovery fio payload [json] files created by battery/cluster
# Expected directory name: {batteryId}-fio-{node_name}
# All results will be saved on global var results_fio
for res in results_dirs:
    battery_id = res.split('-')[0]
    test_name = res.split('-')[1]
    node_id = res.split(f"{test_name}-")[1]

    build_node_result(battery_id, test_name, node_id)
    
    discovery_and_load_fio_results(f"{results_path}/{res}", battery_id)
```

## Results

As described, the tests was done in 4 clusters in two disk layouts (single disk, etcd isolated) using gp2 and gp3. The volume has same capacity using standard values for IOPS and throughput (gp3)

- Total of FIO consecutive tests: 50
- Max IOPS on all jobs job: ~1.5/2k IOPS
- Max IOPS for gp2 device: 386 (capacity=128GiB, throughput*=128 MiB/s)
- Max IOPS for gp3 device: 3000 (capacity=128GiB, throughput=120MiB/s) 

\*[Important note from AWS doc](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volume-types.html): 
*"The throughput limit is between 128 MiB/s and 250 MiB/s, depending on the volume size. Volumes smaller than or equal to 170 GiB deliver a maximum throughput of 128 MiB/s. Volumes larger than 170 GiB but smaller than 334 GiB deliver a maximum throughput of 250 MiB/s if burst credits are available. Volumes larger than or equal to 334 GiB deliver 250 MiB/s regardless of burst credits. gp2 volumes that were created before December 3, 2018 and that have not been modified since creation might not reach full performance unless you modify the volume."*

____
____
**FIO sync lattency p99 in ms (sync_lat_p99_ms)**

Summary of results:
- after 32th job the gp2 disks consumed all burst credits (higher than max [380 IOPS]) and become slow (5/6x) due to throttlings
- the cluster with etcd as second disk using gp2 was more reliable for a longer period, comparing with single disk node
- gp3 become bellow from max and stable until the end of all tests
- gp3 in normal conditions had lattency higher than gp2
- Trade-off in reliability (when long intensive IOPS) and performance (in normal operation)

TODO:
- Collect time and Load1 between each job (it's available on runtime log)
- Compare gp2 and gp3 in perc


```python
df = aggregate_metric('sync_lat_p99_ms').rename(columns={"b2_t1": "gp2x1","b2_t2": "gp2x2","b2_t3": "gp3x1","b2_t4": "gp3x2"})
df.style.applymap(_df_style_high, subset=["gp2x1", "gp2x2", "gp3x1", "gp3x2"], value_yellow=5.0, value_red=10.0)
```




<style type="text/css">
#T_2645e_row1_col4, #T_2645e_row5_col4, #T_2645e_row6_col3 {
  background-color: yellow;
}
#T_2645e_row32_col1, #T_2645e_row33_col1, #T_2645e_row34_col1, #T_2645e_row35_col1, #T_2645e_row36_col1, #T_2645e_row37_col1, #T_2645e_row37_col2, #T_2645e_row38_col1, #T_2645e_row38_col2, #T_2645e_row39_col1, #T_2645e_row39_col2, #T_2645e_row40_col1, #T_2645e_row40_col2, #T_2645e_row41_col1, #T_2645e_row41_col2, #T_2645e_row42_col1, #T_2645e_row42_col2, #T_2645e_row43_col1, #T_2645e_row43_col2, #T_2645e_row44_col1, #T_2645e_row44_col2, #T_2645e_row45_col1, #T_2645e_row45_col2, #T_2645e_row46_col1, #T_2645e_row46_col2, #T_2645e_row47_col1, #T_2645e_row47_col2, #T_2645e_row48_col1, #T_2645e_row48_col2, #T_2645e_row49_col1, #T_2645e_row49_col2 {
  background-color: red;
}
</style>
<table id="T_2645e_">
  <thead>
    <tr>
      <th class="blank level0" >&nbsp;</th>
      <th class="col_heading level0 col0" >job_Id</th>
      <th class="col_heading level0 col1" >gp2x1</th>
      <th class="col_heading level0 col2" >gp2x2</th>
      <th class="col_heading level0 col3" >gp3x1</th>
      <th class="col_heading level0 col4" >gp3x2</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th id="T_2645e_level0_row0" class="row_heading level0 row0" >0</th>
      <td id="T_2645e_row0_col0" class="data row0 col0" >a1</td>
      <td id="T_2645e_row0_col1" class="data row0 col1" >1.925120</td>
      <td id="T_2645e_row0_col2" class="data row0 col2" >2.703360</td>
      <td id="T_2645e_row0_col3" class="data row0 col3" >3.653632</td>
      <td id="T_2645e_row0_col4" class="data row0 col4" >4.685824</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row1" class="row_heading level0 row1" >1</th>
      <td id="T_2645e_row1_col0" class="data row1 col0" >a2</td>
      <td id="T_2645e_row1_col1" class="data row1 col1" >2.277376</td>
      <td id="T_2645e_row1_col2" class="data row1 col2" >2.932736</td>
      <td id="T_2645e_row1_col3" class="data row1 col3" >4.227072</td>
      <td id="T_2645e_row1_col4" class="data row1 col4" >5.144576</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row2" class="row_heading level0 row2" >2</th>
      <td id="T_2645e_row2_col0" class="data row2 col0" >a3</td>
      <td id="T_2645e_row2_col1" class="data row2 col1" >2.244608</td>
      <td id="T_2645e_row2_col2" class="data row2 col2" >2.899968</td>
      <td id="T_2645e_row2_col3" class="data row2 col3" >3.883008</td>
      <td id="T_2645e_row2_col4" class="data row2 col4" >3.915776</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row3" class="row_heading level0 row3" >3</th>
      <td id="T_2645e_row3_col0" class="data row3 col0" >a4</td>
      <td id="T_2645e_row3_col1" class="data row3 col1" >2.375680</td>
      <td id="T_2645e_row3_col2" class="data row3 col2" >2.736128</td>
      <td id="T_2645e_row3_col3" class="data row3 col3" >4.145152</td>
      <td id="T_2645e_row3_col4" class="data row3 col4" >3.915776</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row4" class="row_heading level0 row4" >4</th>
      <td id="T_2645e_row4_col0" class="data row4 col0" >a5</td>
      <td id="T_2645e_row4_col1" class="data row4 col1" >2.342912</td>
      <td id="T_2645e_row4_col2" class="data row4 col2" >2.998272</td>
      <td id="T_2645e_row4_col3" class="data row4 col3" >4.079616</td>
      <td id="T_2645e_row4_col4" class="data row4 col4" >4.423680</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row5" class="row_heading level0 row5" >5</th>
      <td id="T_2645e_row5_col0" class="data row5 col0" >b1</td>
      <td id="T_2645e_row5_col1" class="data row5 col1" >2.375680</td>
      <td id="T_2645e_row5_col2" class="data row5 col2" >2.801664</td>
      <td id="T_2645e_row5_col3" class="data row5 col3" >4.046848</td>
      <td id="T_2645e_row5_col4" class="data row5 col4" >5.079040</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row6" class="row_heading level0 row6" >6</th>
      <td id="T_2645e_row6_col0" class="data row6 col0" >b2</td>
      <td id="T_2645e_row6_col1" class="data row6 col1" >2.375680</td>
      <td id="T_2645e_row6_col2" class="data row6 col2" >2.965504</td>
      <td id="T_2645e_row6_col3" class="data row6 col3" >5.079040</td>
      <td id="T_2645e_row6_col4" class="data row6 col4" >3.784704</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row7" class="row_heading level0 row7" >7</th>
      <td id="T_2645e_row7_col0" class="data row7 col0" >b3</td>
      <td id="T_2645e_row7_col1" class="data row7 col1" >2.211840</td>
      <td id="T_2645e_row7_col2" class="data row7 col2" >2.899968</td>
      <td id="T_2645e_row7_col3" class="data row7 col3" >4.751360</td>
      <td id="T_2645e_row7_col4" class="data row7 col4" >3.817472</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row8" class="row_heading level0 row8" >8</th>
      <td id="T_2645e_row8_col0" class="data row8 col0" >b4</td>
      <td id="T_2645e_row8_col1" class="data row8 col1" >2.244608</td>
      <td id="T_2645e_row8_col2" class="data row8 col2" >2.834432</td>
      <td id="T_2645e_row8_col3" class="data row8 col3" >4.489216</td>
      <td id="T_2645e_row8_col4" class="data row8 col4" >3.948544</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row9" class="row_heading level0 row9" >9</th>
      <td id="T_2645e_row9_col0" class="data row9 col0" >b5</td>
      <td id="T_2645e_row9_col1" class="data row9 col1" >2.342912</td>
      <td id="T_2645e_row9_col2" class="data row9 col2" >2.768896</td>
      <td id="T_2645e_row9_col3" class="data row9 col3" >4.177920</td>
      <td id="T_2645e_row9_col4" class="data row9 col4" >3.620864</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row10" class="row_heading level0 row10" >10</th>
      <td id="T_2645e_row10_col0" class="data row10 col0" >c1</td>
      <td id="T_2645e_row10_col1" class="data row10 col1" >2.342912</td>
      <td id="T_2645e_row10_col2" class="data row10 col2" >2.637824</td>
      <td id="T_2645e_row10_col3" class="data row10 col3" >3.883008</td>
      <td id="T_2645e_row10_col4" class="data row10 col4" >4.358144</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row11" class="row_heading level0 row11" >11</th>
      <td id="T_2645e_row11_col0" class="data row11 col0" >c2</td>
      <td id="T_2645e_row11_col1" class="data row11 col1" >2.637824</td>
      <td id="T_2645e_row11_col2" class="data row11 col2" >2.768896</td>
      <td id="T_2645e_row11_col3" class="data row11 col3" >3.457024</td>
      <td id="T_2645e_row11_col4" class="data row11 col4" >3.096576</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row12" class="row_heading level0 row12" >12</th>
      <td id="T_2645e_row12_col0" class="data row12 col0" >c3</td>
      <td id="T_2645e_row12_col1" class="data row12 col1" >2.801664</td>
      <td id="T_2645e_row12_col2" class="data row12 col2" >2.768896</td>
      <td id="T_2645e_row12_col3" class="data row12 col3" >3.653632</td>
      <td id="T_2645e_row12_col4" class="data row12 col4" >3.883008</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row13" class="row_heading level0 row13" >13</th>
      <td id="T_2645e_row13_col0" class="data row13 col0" >c4</td>
      <td id="T_2645e_row13_col1" class="data row13 col1" >2.441216</td>
      <td id="T_2645e_row13_col2" class="data row13 col2" >2.899968</td>
      <td id="T_2645e_row13_col3" class="data row13 col3" >3.457024</td>
      <td id="T_2645e_row13_col4" class="data row13 col4" >4.046848</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row14" class="row_heading level0 row14" >14</th>
      <td id="T_2645e_row14_col0" class="data row14 col0" >c5</td>
      <td id="T_2645e_row14_col1" class="data row14 col1" >2.441216</td>
      <td id="T_2645e_row14_col2" class="data row14 col2" >2.834432</td>
      <td id="T_2645e_row14_col3" class="data row14 col3" >3.751936</td>
      <td id="T_2645e_row14_col4" class="data row14 col4" >3.555328</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row15" class="row_heading level0 row15" >15</th>
      <td id="T_2645e_row15_col0" class="data row15 col0" >d1</td>
      <td id="T_2645e_row15_col1" class="data row15 col1" >2.375680</td>
      <td id="T_2645e_row15_col2" class="data row15 col2" >2.965504</td>
      <td id="T_2645e_row15_col3" class="data row15 col3" >4.227072</td>
      <td id="T_2645e_row15_col4" class="data row15 col4" >3.620864</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row16" class="row_heading level0 row16" >16</th>
      <td id="T_2645e_row16_col0" class="data row16 col0" >d2</td>
      <td id="T_2645e_row16_col1" class="data row16 col1" >2.310144</td>
      <td id="T_2645e_row16_col2" class="data row16 col2" >2.834432</td>
      <td id="T_2645e_row16_col3" class="data row16 col3" >3.620864</td>
      <td id="T_2645e_row16_col4" class="data row16 col4" >3.391488</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row17" class="row_heading level0 row17" >17</th>
      <td id="T_2645e_row17_col0" class="data row17 col0" >d3</td>
      <td id="T_2645e_row17_col1" class="data row17 col1" >2.310144</td>
      <td id="T_2645e_row17_col2" class="data row17 col2" >2.867200</td>
      <td id="T_2645e_row17_col3" class="data row17 col3" >3.588096</td>
      <td id="T_2645e_row17_col4" class="data row17 col4" >3.883008</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row18" class="row_heading level0 row18" >18</th>
      <td id="T_2645e_row18_col0" class="data row18 col0" >d4</td>
      <td id="T_2645e_row18_col1" class="data row18 col1" >2.441216</td>
      <td id="T_2645e_row18_col2" class="data row18 col2" >2.899968</td>
      <td id="T_2645e_row18_col3" class="data row18 col3" >3.555328</td>
      <td id="T_2645e_row18_col4" class="data row18 col4" >4.112384</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row19" class="row_heading level0 row19" >19</th>
      <td id="T_2645e_row19_col0" class="data row19 col0" >d5</td>
      <td id="T_2645e_row19_col1" class="data row19 col1" >2.572288</td>
      <td id="T_2645e_row19_col2" class="data row19 col2" >2.867200</td>
      <td id="T_2645e_row19_col3" class="data row19 col3" >3.489792</td>
      <td id="T_2645e_row19_col4" class="data row19 col4" >3.719168</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row20" class="row_heading level0 row20" >20</th>
      <td id="T_2645e_row20_col0" class="data row20 col0" >e1</td>
      <td id="T_2645e_row20_col1" class="data row20 col1" >2.637824</td>
      <td id="T_2645e_row20_col2" class="data row20 col2" >2.736128</td>
      <td id="T_2645e_row20_col3" class="data row20 col3" >3.325952</td>
      <td id="T_2645e_row20_col4" class="data row20 col4" >3.489792</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row21" class="row_heading level0 row21" >21</th>
      <td id="T_2645e_row21_col0" class="data row21 col0" >e2</td>
      <td id="T_2645e_row21_col1" class="data row21 col1" >2.834432</td>
      <td id="T_2645e_row21_col2" class="data row21 col2" >2.834432</td>
      <td id="T_2645e_row21_col3" class="data row21 col3" >3.489792</td>
      <td id="T_2645e_row21_col4" class="data row21 col4" >3.391488</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row22" class="row_heading level0 row22" >22</th>
      <td id="T_2645e_row22_col0" class="data row22 col0" >e3</td>
      <td id="T_2645e_row22_col1" class="data row22 col1" >2.441216</td>
      <td id="T_2645e_row22_col2" class="data row22 col2" >2.932736</td>
      <td id="T_2645e_row22_col3" class="data row22 col3" >3.588096</td>
      <td id="T_2645e_row22_col4" class="data row22 col4" >3.391488</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row23" class="row_heading level0 row23" >23</th>
      <td id="T_2645e_row23_col0" class="data row23 col0" >e4</td>
      <td id="T_2645e_row23_col1" class="data row23 col1" >2.441216</td>
      <td id="T_2645e_row23_col2" class="data row23 col2" >2.768896</td>
      <td id="T_2645e_row23_col3" class="data row23 col3" >3.555328</td>
      <td id="T_2645e_row23_col4" class="data row23 col4" >4.423680</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row24" class="row_heading level0 row24" >24</th>
      <td id="T_2645e_row24_col0" class="data row24 col0" >e5</td>
      <td id="T_2645e_row24_col1" class="data row24 col1" >2.342912</td>
      <td id="T_2645e_row24_col2" class="data row24 col2" >2.867200</td>
      <td id="T_2645e_row24_col3" class="data row24 col3" >3.948544</td>
      <td id="T_2645e_row24_col4" class="data row24 col4" >3.751936</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row25" class="row_heading level0 row25" >25</th>
      <td id="T_2645e_row25_col0" class="data row25 col0" >f1</td>
      <td id="T_2645e_row25_col1" class="data row25 col1" >2.342912</td>
      <td id="T_2645e_row25_col2" class="data row25 col2" >2.605056</td>
      <td id="T_2645e_row25_col3" class="data row25 col3" >4.554752</td>
      <td id="T_2645e_row25_col4" class="data row25 col4" >4.620288</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row26" class="row_heading level0 row26" >26</th>
      <td id="T_2645e_row26_col0" class="data row26 col0" >f2</td>
      <td id="T_2645e_row26_col1" class="data row26 col1" >2.441216</td>
      <td id="T_2645e_row26_col2" class="data row26 col2" >2.506752</td>
      <td id="T_2645e_row26_col3" class="data row26 col3" >4.046848</td>
      <td id="T_2645e_row26_col4" class="data row26 col4" >4.816896</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row27" class="row_heading level0 row27" >27</th>
      <td id="T_2645e_row27_col0" class="data row27 col0" >f3</td>
      <td id="T_2645e_row27_col1" class="data row27 col1" >2.506752</td>
      <td id="T_2645e_row27_col2" class="data row27 col2" >2.768896</td>
      <td id="T_2645e_row27_col3" class="data row27 col3" >4.112384</td>
      <td id="T_2645e_row27_col4" class="data row27 col4" >3.653632</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row28" class="row_heading level0 row28" >28</th>
      <td id="T_2645e_row28_col0" class="data row28 col0" >f4</td>
      <td id="T_2645e_row28_col1" class="data row28 col1" >2.473984</td>
      <td id="T_2645e_row28_col2" class="data row28 col2" >2.899968</td>
      <td id="T_2645e_row28_col3" class="data row28 col3" >3.653632</td>
      <td id="T_2645e_row28_col4" class="data row28 col4" >3.850240</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row29" class="row_heading level0 row29" >29</th>
      <td id="T_2645e_row29_col0" class="data row29 col0" >f5</td>
      <td id="T_2645e_row29_col1" class="data row29 col1" >2.310144</td>
      <td id="T_2645e_row29_col2" class="data row29 col2" >2.736128</td>
      <td id="T_2645e_row29_col3" class="data row29 col3" >4.112384</td>
      <td id="T_2645e_row29_col4" class="data row29 col4" >3.620864</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row30" class="row_heading level0 row30" >30</th>
      <td id="T_2645e_row30_col0" class="data row30 col0" >g1</td>
      <td id="T_2645e_row30_col1" class="data row30 col1" >2.605056</td>
      <td id="T_2645e_row30_col2" class="data row30 col2" >2.736128</td>
      <td id="T_2645e_row30_col3" class="data row30 col3" >4.423680</td>
      <td id="T_2645e_row30_col4" class="data row30 col4" >3.620864</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row31" class="row_heading level0 row31" >31</th>
      <td id="T_2645e_row31_col0" class="data row31 col0" >g2</td>
      <td id="T_2645e_row31_col1" class="data row31 col1" >2.670592</td>
      <td id="T_2645e_row31_col2" class="data row31 col2" >2.670592</td>
      <td id="T_2645e_row31_col3" class="data row31 col3" >4.145152</td>
      <td id="T_2645e_row31_col4" class="data row31 col4" >3.424256</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row32" class="row_heading level0 row32" >32</th>
      <td id="T_2645e_row32_col0" class="data row32 col0" >g3</td>
      <td id="T_2645e_row32_col1" class="data row32 col1" >17.956864</td>
      <td id="T_2645e_row32_col2" class="data row32 col2" >2.605056</td>
      <td id="T_2645e_row32_col3" class="data row32 col3" >4.292608</td>
      <td id="T_2645e_row32_col4" class="data row32 col4" >3.522560</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row33" class="row_heading level0 row33" >33</th>
      <td id="T_2645e_row33_col0" class="data row33 col0" >g4</td>
      <td id="T_2645e_row33_col1" class="data row33 col1" >18.481152</td>
      <td id="T_2645e_row33_col2" class="data row33 col2" >2.801664</td>
      <td id="T_2645e_row33_col3" class="data row33 col3" >4.227072</td>
      <td id="T_2645e_row33_col4" class="data row33 col4" >3.522560</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row34" class="row_heading level0 row34" >34</th>
      <td id="T_2645e_row34_col0" class="data row34 col0" >g5</td>
      <td id="T_2645e_row34_col1" class="data row34 col1" >20.578304</td>
      <td id="T_2645e_row34_col2" class="data row34 col2" >2.867200</td>
      <td id="T_2645e_row34_col3" class="data row34 col3" >4.112384</td>
      <td id="T_2645e_row34_col4" class="data row34 col4" >3.784704</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row35" class="row_heading level0 row35" >35</th>
      <td id="T_2645e_row35_col0" class="data row35 col0" >h1</td>
      <td id="T_2645e_row35_col1" class="data row35 col1" >20.054016</td>
      <td id="T_2645e_row35_col2" class="data row35 col2" >2.736128</td>
      <td id="T_2645e_row35_col3" class="data row35 col3" >4.227072</td>
      <td id="T_2645e_row35_col4" class="data row35 col4" >3.883008</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row36" class="row_heading level0 row36" >36</th>
      <td id="T_2645e_row36_col0" class="data row36 col0" >h2</td>
      <td id="T_2645e_row36_col1" class="data row36 col1" >18.481152</td>
      <td id="T_2645e_row36_col2" class="data row36 col2" >2.899968</td>
      <td id="T_2645e_row36_col3" class="data row36 col3" >3.719168</td>
      <td id="T_2645e_row36_col4" class="data row36 col4" >4.227072</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row37" class="row_heading level0 row37" >37</th>
      <td id="T_2645e_row37_col0" class="data row37 col0" >h3</td>
      <td id="T_2645e_row37_col1" class="data row37 col1" >18.219008</td>
      <td id="T_2645e_row37_col2" class="data row37 col2" >18.219008</td>
      <td id="T_2645e_row37_col3" class="data row37 col3" >3.883008</td>
      <td id="T_2645e_row37_col4" class="data row37 col4" >4.554752</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row38" class="row_heading level0 row38" >38</th>
      <td id="T_2645e_row38_col0" class="data row38 col0" >h4</td>
      <td id="T_2645e_row38_col1" class="data row38 col1" >18.219008</td>
      <td id="T_2645e_row38_col2" class="data row38 col2" >18.219008</td>
      <td id="T_2645e_row38_col3" class="data row38 col3" >3.751936</td>
      <td id="T_2645e_row38_col4" class="data row38 col4" >4.489216</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row39" class="row_heading level0 row39" >39</th>
      <td id="T_2645e_row39_col0" class="data row39 col0" >h5</td>
      <td id="T_2645e_row39_col1" class="data row39 col1" >18.219008</td>
      <td id="T_2645e_row39_col2" class="data row39 col2" >18.219008</td>
      <td id="T_2645e_row39_col3" class="data row39 col3" >3.948544</td>
      <td id="T_2645e_row39_col4" class="data row39 col4" >3.948544</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row40" class="row_heading level0 row40" >40</th>
      <td id="T_2645e_row40_col0" class="data row40 col0" >i1</td>
      <td id="T_2645e_row40_col1" class="data row40 col1" >18.481152</td>
      <td id="T_2645e_row40_col2" class="data row40 col2" >18.219008</td>
      <td id="T_2645e_row40_col3" class="data row40 col3" >4.046848</td>
      <td id="T_2645e_row40_col4" class="data row40 col4" >4.423680</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row41" class="row_heading level0 row41" >41</th>
      <td id="T_2645e_row41_col0" class="data row41 col0" >i2</td>
      <td id="T_2645e_row41_col1" class="data row41 col1" >18.481152</td>
      <td id="T_2645e_row41_col2" class="data row41 col2" >18.219008</td>
      <td id="T_2645e_row41_col3" class="data row41 col3" >4.112384</td>
      <td id="T_2645e_row41_col4" class="data row41 col4" >4.292608</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row42" class="row_heading level0 row42" >42</th>
      <td id="T_2645e_row42_col0" class="data row42 col0" >i3</td>
      <td id="T_2645e_row42_col1" class="data row42 col1" >18.481152</td>
      <td id="T_2645e_row42_col2" class="data row42 col2" >18.219008</td>
      <td id="T_2645e_row42_col3" class="data row42 col3" >4.685824</td>
      <td id="T_2645e_row42_col4" class="data row42 col4" >4.014080</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row43" class="row_heading level0 row43" >43</th>
      <td id="T_2645e_row43_col0" class="data row43 col0" >i4</td>
      <td id="T_2645e_row43_col1" class="data row43 col1" >18.481152</td>
      <td id="T_2645e_row43_col2" class="data row43 col2" >18.219008</td>
      <td id="T_2645e_row43_col3" class="data row43 col3" >4.751360</td>
      <td id="T_2645e_row43_col4" class="data row43 col4" >3.784704</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row44" class="row_heading level0 row44" >44</th>
      <td id="T_2645e_row44_col0" class="data row44 col0" >i5</td>
      <td id="T_2645e_row44_col1" class="data row44 col1" >18.219008</td>
      <td id="T_2645e_row44_col2" class="data row44 col2" >18.219008</td>
      <td id="T_2645e_row44_col3" class="data row44 col3" >4.079616</td>
      <td id="T_2645e_row44_col4" class="data row44 col4" >3.817472</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row45" class="row_heading level0 row45" >45</th>
      <td id="T_2645e_row45_col0" class="data row45 col0" >j1</td>
      <td id="T_2645e_row45_col1" class="data row45 col1" >18.481152</td>
      <td id="T_2645e_row45_col2" class="data row45 col2" >18.219008</td>
      <td id="T_2645e_row45_col3" class="data row45 col3" >3.391488</td>
      <td id="T_2645e_row45_col4" class="data row45 col4" >3.719168</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row46" class="row_heading level0 row46" >46</th>
      <td id="T_2645e_row46_col0" class="data row46 col0" >j2</td>
      <td id="T_2645e_row46_col1" class="data row46 col1" >18.481152</td>
      <td id="T_2645e_row46_col2" class="data row46 col2" >18.219008</td>
      <td id="T_2645e_row46_col3" class="data row46 col3" >4.423680</td>
      <td id="T_2645e_row46_col4" class="data row46 col4" >3.457024</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row47" class="row_heading level0 row47" >47</th>
      <td id="T_2645e_row47_col0" class="data row47 col0" >j3</td>
      <td id="T_2645e_row47_col1" class="data row47 col1" >19.005440</td>
      <td id="T_2645e_row47_col2" class="data row47 col2" >18.219008</td>
      <td id="T_2645e_row47_col3" class="data row47 col3" >4.947968</td>
      <td id="T_2645e_row47_col4" class="data row47 col4" >4.292608</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row48" class="row_heading level0 row48" >48</th>
      <td id="T_2645e_row48_col0" class="data row48 col0" >j4</td>
      <td id="T_2645e_row48_col1" class="data row48 col1" >18.481152</td>
      <td id="T_2645e_row48_col2" class="data row48 col2" >18.219008</td>
      <td id="T_2645e_row48_col3" class="data row48 col3" >3.784704</td>
      <td id="T_2645e_row48_col4" class="data row48 col4" >4.177920</td>
    </tr>
    <tr>
      <th id="T_2645e_level0_row49" class="row_heading level0 row49" >49</th>
      <td id="T_2645e_row49_col0" class="data row49 col0" >j5</td>
      <td id="T_2645e_row49_col1" class="data row49 col1" >18.481152</td>
      <td id="T_2645e_row49_col2" class="data row49 col2" >18.219008</td>
      <td id="T_2645e_row49_col3" class="data row49 col3" >3.751936</td>
      <td id="T_2645e_row49_col4" class="data row49 col4" >3.489792</td>
    </tr>
  </tbody>
</table>




____
**FIO sync lattency p99.9 in ms (sync_lat_p99.9_ms)**

Summary of results:
- Same points of sync_lat_p99_ms; plus:
- isolated etcd disk reported slower than single disk
- gp3 become stable in a long period of writes


```python
df = aggregate_metric('sync_lat_p99.9_ms').rename(columns={"b2_t1": "gp2x1","b2_t2": "gp2x2","b2_t3": "gp3x1","b2_t4": "gp3x2"})
df.style.applymap(_df_style_high, subset=["gp2x1", "gp2x2", "gp3x1", "gp3x2"], value_yellow=5.0, value_red=10.0)
```




<style type="text/css">
#T_e71b1_row0_col2, #T_e71b1_row0_col3, #T_e71b1_row1_col1, #T_e71b1_row1_col2, #T_e71b1_row1_col3, #T_e71b1_row2_col1, #T_e71b1_row2_col2, #T_e71b1_row2_col3, #T_e71b1_row3_col1, #T_e71b1_row3_col2, #T_e71b1_row3_col3, #T_e71b1_row4_col1, #T_e71b1_row4_col2, #T_e71b1_row4_col3, #T_e71b1_row5_col1, #T_e71b1_row5_col2, #T_e71b1_row5_col3, #T_e71b1_row6_col1, #T_e71b1_row6_col2, #T_e71b1_row7_col1, #T_e71b1_row7_col2, #T_e71b1_row8_col1, #T_e71b1_row8_col2, #T_e71b1_row9_col1, #T_e71b1_row9_col3, #T_e71b1_row10_col1, #T_e71b1_row10_col2, #T_e71b1_row10_col3, #T_e71b1_row11_col1, #T_e71b1_row11_col2, #T_e71b1_row11_col3, #T_e71b1_row12_col1, #T_e71b1_row12_col2, #T_e71b1_row12_col3, #T_e71b1_row13_col1, #T_e71b1_row13_col2, #T_e71b1_row13_col3, #T_e71b1_row14_col1, #T_e71b1_row14_col3, #T_e71b1_row15_col1, #T_e71b1_row16_col1, #T_e71b1_row16_col2, #T_e71b1_row16_col3, #T_e71b1_row16_col4, #T_e71b1_row17_col1, #T_e71b1_row17_col2, #T_e71b1_row17_col3, #T_e71b1_row18_col1, #T_e71b1_row18_col3, #T_e71b1_row19_col1, #T_e71b1_row19_col2, #T_e71b1_row19_col3, #T_e71b1_row20_col1, #T_e71b1_row20_col2, #T_e71b1_row20_col3, #T_e71b1_row21_col1, #T_e71b1_row21_col2, #T_e71b1_row21_col3, #T_e71b1_row22_col1, #T_e71b1_row22_col2, #T_e71b1_row22_col3, #T_e71b1_row23_col1, #T_e71b1_row23_col2, #T_e71b1_row23_col3, #T_e71b1_row24_col1, #T_e71b1_row24_col2, #T_e71b1_row24_col3, #T_e71b1_row25_col1, #T_e71b1_row25_col2, #T_e71b1_row25_col3, #T_e71b1_row26_col1, #T_e71b1_row26_col2, #T_e71b1_row26_col3, #T_e71b1_row27_col1, #T_e71b1_row27_col2, #T_e71b1_row27_col3, #T_e71b1_row28_col1, #T_e71b1_row28_col3, #T_e71b1_row29_col1, #T_e71b1_row29_col2, #T_e71b1_row29_col3, #T_e71b1_row30_col1, #T_e71b1_row30_col2, #T_e71b1_row30_col3, #T_e71b1_row31_col1, #T_e71b1_row31_col2, #T_e71b1_row31_col3, #T_e71b1_row32_col2, #T_e71b1_row32_col3, #T_e71b1_row33_col2, #T_e71b1_row33_col3, #T_e71b1_row34_col3, #T_e71b1_row35_col2, #T_e71b1_row36_col3, #T_e71b1_row37_col3, #T_e71b1_row38_col3, #T_e71b1_row39_col3, #T_e71b1_row40_col3, #T_e71b1_row41_col3, #T_e71b1_row44_col3, #T_e71b1_row45_col3, #T_e71b1_row48_col3, #T_e71b1_row49_col3 {
  background-color: yellow;
}
#T_e71b1_row0_col4, #T_e71b1_row1_col4, #T_e71b1_row2_col4, #T_e71b1_row3_col4, #T_e71b1_row4_col4, #T_e71b1_row5_col4, #T_e71b1_row6_col3, #T_e71b1_row6_col4, #T_e71b1_row7_col3, #T_e71b1_row7_col4, #T_e71b1_row8_col3, #T_e71b1_row8_col4, #T_e71b1_row9_col2, #T_e71b1_row9_col4, #T_e71b1_row10_col4, #T_e71b1_row11_col4, #T_e71b1_row12_col4, #T_e71b1_row13_col4, #T_e71b1_row14_col2, #T_e71b1_row14_col4, #T_e71b1_row15_col2, #T_e71b1_row15_col3, #T_e71b1_row15_col4, #T_e71b1_row17_col4, #T_e71b1_row18_col2, #T_e71b1_row18_col4, #T_e71b1_row19_col4, #T_e71b1_row20_col4, #T_e71b1_row21_col4, #T_e71b1_row22_col4, #T_e71b1_row23_col4, #T_e71b1_row24_col4, #T_e71b1_row25_col4, #T_e71b1_row26_col4, #T_e71b1_row27_col4, #T_e71b1_row28_col2, #T_e71b1_row28_col4, #T_e71b1_row29_col4, #T_e71b1_row30_col4, #T_e71b1_row31_col4, #T_e71b1_row32_col1, #T_e71b1_row32_col4, #T_e71b1_row33_col1, #T_e71b1_row33_col4, #T_e71b1_row34_col1, #T_e71b1_row34_col2, #T_e71b1_row34_col4, #T_e71b1_row35_col1, #T_e71b1_row35_col3, #T_e71b1_row35_col4, #T_e71b1_row36_col1, #T_e71b1_row36_col2, #T_e71b1_row36_col4, #T_e71b1_row37_col1, #T_e71b1_row37_col2, #T_e71b1_row37_col4, #T_e71b1_row38_col1, #T_e71b1_row38_col2, #T_e71b1_row38_col4, #T_e71b1_row39_col1, #T_e71b1_row39_col2, #T_e71b1_row39_col4, #T_e71b1_row40_col1, #T_e71b1_row40_col2, #T_e71b1_row40_col4, #T_e71b1_row41_col1, #T_e71b1_row41_col2, #T_e71b1_row41_col4, #T_e71b1_row42_col1, #T_e71b1_row42_col2, #T_e71b1_row42_col3, #T_e71b1_row42_col4, #T_e71b1_row43_col1, #T_e71b1_row43_col2, #T_e71b1_row43_col3, #T_e71b1_row43_col4, #T_e71b1_row44_col1, #T_e71b1_row44_col2, #T_e71b1_row44_col4, #T_e71b1_row45_col1, #T_e71b1_row45_col2, #T_e71b1_row45_col4, #T_e71b1_row46_col1, #T_e71b1_row46_col2, #T_e71b1_row46_col3, #T_e71b1_row46_col4, #T_e71b1_row47_col1, #T_e71b1_row47_col2, #T_e71b1_row47_col3, #T_e71b1_row47_col4, #T_e71b1_row48_col1, #T_e71b1_row48_col2, #T_e71b1_row48_col4, #T_e71b1_row49_col1, #T_e71b1_row49_col2, #T_e71b1_row49_col4 {
  background-color: red;
}
</style>
<table id="T_e71b1_">
  <thead>
    <tr>
      <th class="blank level0" >&nbsp;</th>
      <th class="col_heading level0 col0" >job_Id</th>
      <th class="col_heading level0 col1" >gp2x1</th>
      <th class="col_heading level0 col2" >gp2x2</th>
      <th class="col_heading level0 col3" >gp3x1</th>
      <th class="col_heading level0 col4" >gp3x2</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th id="T_e71b1_level0_row0" class="row_heading level0 row0" >0</th>
      <td id="T_e71b1_row0_col0" class="data row0 col0" >a1</td>
      <td id="T_e71b1_row0_col1" class="data row0 col1" >4.751360</td>
      <td id="T_e71b1_row0_col2" class="data row0 col2" >9.502720</td>
      <td id="T_e71b1_row0_col3" class="data row0 col3" >8.454144</td>
      <td id="T_e71b1_row0_col4" class="data row0 col4" >11.075584</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row1" class="row_heading level0 row1" >1</th>
      <td id="T_e71b1_row1_col0" class="data row1 col0" >a2</td>
      <td id="T_e71b1_row1_col1" class="data row1 col1" >6.782976</td>
      <td id="T_e71b1_row1_col2" class="data row1 col2" >9.764864</td>
      <td id="T_e71b1_row1_col3" class="data row1 col3" >9.502720</td>
      <td id="T_e71b1_row1_col4" class="data row1 col4" >13.172736</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row2" class="row_heading level0 row2" >2</th>
      <td id="T_e71b1_row2_col0" class="data row2 col0" >a3</td>
      <td id="T_e71b1_row2_col1" class="data row2 col1" >6.586368</td>
      <td id="T_e71b1_row2_col2" class="data row2 col2" >9.240576</td>
      <td id="T_e71b1_row2_col3" class="data row2 col3" >8.978432</td>
      <td id="T_e71b1_row2_col4" class="data row2 col4" >10.158080</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row3" class="row_heading level0 row3" >3</th>
      <td id="T_e71b1_row3_col0" class="data row3 col0" >a4</td>
      <td id="T_e71b1_row3_col1" class="data row3 col1" >6.324224</td>
      <td id="T_e71b1_row3_col2" class="data row3 col2" >9.764864</td>
      <td id="T_e71b1_row3_col3" class="data row3 col3" >9.240576</td>
      <td id="T_e71b1_row3_col4" class="data row3 col4" >10.420224</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row4" class="row_heading level0 row4" >4</th>
      <td id="T_e71b1_row4_col0" class="data row4 col0" >a5</td>
      <td id="T_e71b1_row4_col1" class="data row4 col1" >6.520832</td>
      <td id="T_e71b1_row4_col2" class="data row4 col2" >9.895936</td>
      <td id="T_e71b1_row4_col3" class="data row4 col3" >9.764864</td>
      <td id="T_e71b1_row4_col4" class="data row4 col4" >10.551296</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row5" class="row_heading level0 row5" >5</th>
      <td id="T_e71b1_row5_col0" class="data row5 col0" >b1</td>
      <td id="T_e71b1_row5_col1" class="data row5 col1" >6.782976</td>
      <td id="T_e71b1_row5_col2" class="data row5 col2" >9.371648</td>
      <td id="T_e71b1_row5_col3" class="data row5 col3" >9.371648</td>
      <td id="T_e71b1_row5_col4" class="data row5 col4" >11.730944</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row6" class="row_heading level0 row6" >6</th>
      <td id="T_e71b1_row6_col0" class="data row6 col0" >b2</td>
      <td id="T_e71b1_row6_col1" class="data row6 col1" >6.455296</td>
      <td id="T_e71b1_row6_col2" class="data row6 col2" >9.764864</td>
      <td id="T_e71b1_row6_col3" class="data row6 col3" >10.551296</td>
      <td id="T_e71b1_row6_col4" class="data row6 col4" >10.682368</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row7" class="row_heading level0 row7" >7</th>
      <td id="T_e71b1_row7_col0" class="data row7 col0" >b3</td>
      <td id="T_e71b1_row7_col1" class="data row7 col1" >6.586368</td>
      <td id="T_e71b1_row7_col2" class="data row7 col2" >8.978432</td>
      <td id="T_e71b1_row7_col3" class="data row7 col3" >10.027008</td>
      <td id="T_e71b1_row7_col4" class="data row7 col4" >10.420224</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row8" class="row_heading level0 row8" >8</th>
      <td id="T_e71b1_row8_col0" class="data row8 col0" >b4</td>
      <td id="T_e71b1_row8_col1" class="data row8 col1" >6.651904</td>
      <td id="T_e71b1_row8_col2" class="data row8 col2" >9.109504</td>
      <td id="T_e71b1_row8_col3" class="data row8 col3" >10.420224</td>
      <td id="T_e71b1_row8_col4" class="data row8 col4" >10.682368</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row9" class="row_heading level0 row9" >9</th>
      <td id="T_e71b1_row9_col0" class="data row9 col0" >b5</td>
      <td id="T_e71b1_row9_col1" class="data row9 col1" >6.651904</td>
      <td id="T_e71b1_row9_col2" class="data row9 col2" >10.027008</td>
      <td id="T_e71b1_row9_col3" class="data row9 col3" >9.633792</td>
      <td id="T_e71b1_row9_col4" class="data row9 col4" >10.813440</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row10" class="row_heading level0 row10" >10</th>
      <td id="T_e71b1_row10_col0" class="data row10 col0" >c1</td>
      <td id="T_e71b1_row10_col1" class="data row10 col1" >6.848512</td>
      <td id="T_e71b1_row10_col2" class="data row10 col2" >9.371648</td>
      <td id="T_e71b1_row10_col3" class="data row10 col3" >9.895936</td>
      <td id="T_e71b1_row10_col4" class="data row10 col4" >11.730944</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row11" class="row_heading level0 row11" >11</th>
      <td id="T_e71b1_row11_col0" class="data row11 col0" >c2</td>
      <td id="T_e71b1_row11_col1" class="data row11 col1" >7.438336</td>
      <td id="T_e71b1_row11_col2" class="data row11 col2" >9.240576</td>
      <td id="T_e71b1_row11_col3" class="data row11 col3" >8.716288</td>
      <td id="T_e71b1_row11_col4" class="data row11 col4" >10.158080</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row12" class="row_heading level0 row12" >12</th>
      <td id="T_e71b1_row12_col0" class="data row12 col0" >c3</td>
      <td id="T_e71b1_row12_col1" class="data row12 col1" >6.914048</td>
      <td id="T_e71b1_row12_col2" class="data row12 col2" >9.502720</td>
      <td id="T_e71b1_row12_col3" class="data row12 col3" >8.847360</td>
      <td id="T_e71b1_row12_col4" class="data row12 col4" >10.027008</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row13" class="row_heading level0 row13" >13</th>
      <td id="T_e71b1_row13_col0" class="data row13 col0" >c4</td>
      <td id="T_e71b1_row13_col1" class="data row13 col1" >7.110656</td>
      <td id="T_e71b1_row13_col2" class="data row13 col2" >9.502720</td>
      <td id="T_e71b1_row13_col3" class="data row13 col3" >8.847360</td>
      <td id="T_e71b1_row13_col4" class="data row13 col4" >10.027008</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row14" class="row_heading level0 row14" >14</th>
      <td id="T_e71b1_row14_col0" class="data row14 col0" >c5</td>
      <td id="T_e71b1_row14_col1" class="data row14 col1" >7.045120</td>
      <td id="T_e71b1_row14_col2" class="data row14 col2" >10.027008</td>
      <td id="T_e71b1_row14_col3" class="data row14 col3" >9.109504</td>
      <td id="T_e71b1_row14_col4" class="data row14 col4" >10.158080</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row15" class="row_heading level0 row15" >15</th>
      <td id="T_e71b1_row15_col0" class="data row15 col0" >d1</td>
      <td id="T_e71b1_row15_col1" class="data row15 col1" >7.110656</td>
      <td id="T_e71b1_row15_col2" class="data row15 col2" >10.158080</td>
      <td id="T_e71b1_row15_col3" class="data row15 col3" >10.027008</td>
      <td id="T_e71b1_row15_col4" class="data row15 col4" >10.551296</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row16" class="row_heading level0 row16" >16</th>
      <td id="T_e71b1_row16_col0" class="data row16 col0" >d2</td>
      <td id="T_e71b1_row16_col1" class="data row16 col1" >6.914048</td>
      <td id="T_e71b1_row16_col2" class="data row16 col2" >9.502720</td>
      <td id="T_e71b1_row16_col3" class="data row16 col3" >9.240576</td>
      <td id="T_e71b1_row16_col4" class="data row16 col4" >9.633792</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row17" class="row_heading level0 row17" >17</th>
      <td id="T_e71b1_row17_col0" class="data row17 col0" >d3</td>
      <td id="T_e71b1_row17_col1" class="data row17 col1" >6.717440</td>
      <td id="T_e71b1_row17_col2" class="data row17 col2" >9.633792</td>
      <td id="T_e71b1_row17_col3" class="data row17 col3" >9.240576</td>
      <td id="T_e71b1_row17_col4" class="data row17 col4" >10.551296</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row18" class="row_heading level0 row18" >18</th>
      <td id="T_e71b1_row18_col0" class="data row18 col0" >d4</td>
      <td id="T_e71b1_row18_col1" class="data row18 col1" >6.717440</td>
      <td id="T_e71b1_row18_col2" class="data row18 col2" >10.027008</td>
      <td id="T_e71b1_row18_col3" class="data row18 col3" >9.240576</td>
      <td id="T_e71b1_row18_col4" class="data row18 col4" >11.075584</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row19" class="row_heading level0 row19" >19</th>
      <td id="T_e71b1_row19_col0" class="data row19 col0" >d5</td>
      <td id="T_e71b1_row19_col1" class="data row19 col1" >6.979584</td>
      <td id="T_e71b1_row19_col2" class="data row19 col2" >9.895936</td>
      <td id="T_e71b1_row19_col3" class="data row19 col3" >9.109504</td>
      <td id="T_e71b1_row19_col4" class="data row19 col4" >10.944512</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row20" class="row_heading level0 row20" >20</th>
      <td id="T_e71b1_row20_col0" class="data row20 col0" >e1</td>
      <td id="T_e71b1_row20_col1" class="data row20 col1" >7.372800</td>
      <td id="T_e71b1_row20_col2" class="data row20 col2" >9.633792</td>
      <td id="T_e71b1_row20_col3" class="data row20 col3" >8.978432</td>
      <td id="T_e71b1_row20_col4" class="data row20 col4" >10.158080</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row21" class="row_heading level0 row21" >21</th>
      <td id="T_e71b1_row21_col0" class="data row21 col0" >e2</td>
      <td id="T_e71b1_row21_col1" class="data row21 col1" >7.634944</td>
      <td id="T_e71b1_row21_col2" class="data row21 col2" >9.633792</td>
      <td id="T_e71b1_row21_col3" class="data row21 col3" >8.716288</td>
      <td id="T_e71b1_row21_col4" class="data row21 col4" >10.420224</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row22" class="row_heading level0 row22" >22</th>
      <td id="T_e71b1_row22_col0" class="data row22 col0" >e3</td>
      <td id="T_e71b1_row22_col1" class="data row22 col1" >6.782976</td>
      <td id="T_e71b1_row22_col2" class="data row22 col2" >9.764864</td>
      <td id="T_e71b1_row22_col3" class="data row22 col3" >8.716288</td>
      <td id="T_e71b1_row22_col4" class="data row22 col4" >10.158080</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row23" class="row_heading level0 row23" >23</th>
      <td id="T_e71b1_row23_col0" class="data row23 col0" >e4</td>
      <td id="T_e71b1_row23_col1" class="data row23 col1" >6.455296</td>
      <td id="T_e71b1_row23_col2" class="data row23 col2" >9.633792</td>
      <td id="T_e71b1_row23_col3" class="data row23 col3" >8.847360</td>
      <td id="T_e71b1_row23_col4" class="data row23 col4" >11.075584</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row24" class="row_heading level0 row24" >24</th>
      <td id="T_e71b1_row24_col0" class="data row24 col0" >e5</td>
      <td id="T_e71b1_row24_col1" class="data row24 col1" >7.045120</td>
      <td id="T_e71b1_row24_col2" class="data row24 col2" >9.895936</td>
      <td id="T_e71b1_row24_col3" class="data row24 col3" >8.978432</td>
      <td id="T_e71b1_row24_col4" class="data row24 col4" >10.289152</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row25" class="row_heading level0 row25" >25</th>
      <td id="T_e71b1_row25_col0" class="data row25 col0" >f1</td>
      <td id="T_e71b1_row25_col1" class="data row25 col1" >6.586368</td>
      <td id="T_e71b1_row25_col2" class="data row25 col2" >9.502720</td>
      <td id="T_e71b1_row25_col3" class="data row25 col3" >9.764864</td>
      <td id="T_e71b1_row25_col4" class="data row25 col4" >12.517376</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row26" class="row_heading level0 row26" >26</th>
      <td id="T_e71b1_row26_col0" class="data row26 col0" >f2</td>
      <td id="T_e71b1_row26_col1" class="data row26 col1" >6.586368</td>
      <td id="T_e71b1_row26_col2" class="data row26 col2" >8.454144</td>
      <td id="T_e71b1_row26_col3" class="data row26 col3" >9.240576</td>
      <td id="T_e71b1_row26_col4" class="data row26 col4" >11.337728</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row27" class="row_heading level0 row27" >27</th>
      <td id="T_e71b1_row27_col0" class="data row27 col0" >f3</td>
      <td id="T_e71b1_row27_col1" class="data row27 col1" >6.717440</td>
      <td id="T_e71b1_row27_col2" class="data row27 col2" >9.633792</td>
      <td id="T_e71b1_row27_col3" class="data row27 col3" >9.240576</td>
      <td id="T_e71b1_row27_col4" class="data row27 col4" >10.420224</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row28" class="row_heading level0 row28" >28</th>
      <td id="T_e71b1_row28_col0" class="data row28 col0" >f4</td>
      <td id="T_e71b1_row28_col1" class="data row28 col1" >6.717440</td>
      <td id="T_e71b1_row28_col2" class="data row28 col2" >10.813440</td>
      <td id="T_e71b1_row28_col3" class="data row28 col3" >9.109504</td>
      <td id="T_e71b1_row28_col4" class="data row28 col4" >10.682368</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row29" class="row_heading level0 row29" >29</th>
      <td id="T_e71b1_row29_col0" class="data row29 col0" >f5</td>
      <td id="T_e71b1_row29_col1" class="data row29 col1" >6.848512</td>
      <td id="T_e71b1_row29_col2" class="data row29 col2" >8.716288</td>
      <td id="T_e71b1_row29_col3" class="data row29 col3" >9.764864</td>
      <td id="T_e71b1_row29_col4" class="data row29 col4" >10.944512</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row30" class="row_heading level0 row30" >30</th>
      <td id="T_e71b1_row30_col0" class="data row30 col0" >g1</td>
      <td id="T_e71b1_row30_col1" class="data row30 col1" >6.651904</td>
      <td id="T_e71b1_row30_col2" class="data row30 col2" >9.502720</td>
      <td id="T_e71b1_row30_col3" class="data row30 col3" >9.895936</td>
      <td id="T_e71b1_row30_col4" class="data row30 col4" >10.420224</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row31" class="row_heading level0 row31" >31</th>
      <td id="T_e71b1_row31_col0" class="data row31 col0" >g2</td>
      <td id="T_e71b1_row31_col1" class="data row31 col1" >6.979584</td>
      <td id="T_e71b1_row31_col2" class="data row31 col2" >9.764864</td>
      <td id="T_e71b1_row31_col3" class="data row31 col3" >9.502720</td>
      <td id="T_e71b1_row31_col4" class="data row31 col4" >10.027008</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row32" class="row_heading level0 row32" >32</th>
      <td id="T_e71b1_row32_col0" class="data row32 col0" >g3</td>
      <td id="T_e71b1_row32_col1" class="data row32 col1" >28.704768</td>
      <td id="T_e71b1_row32_col2" class="data row32 col2" >9.109504</td>
      <td id="T_e71b1_row32_col3" class="data row32 col3" >9.502720</td>
      <td id="T_e71b1_row32_col4" class="data row32 col4" >10.158080</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row33" class="row_heading level0 row33" >33</th>
      <td id="T_e71b1_row33_col0" class="data row33 col0" >g4</td>
      <td id="T_e71b1_row33_col1" class="data row33 col1" >33.816576</td>
      <td id="T_e71b1_row33_col2" class="data row33 col2" >9.633792</td>
      <td id="T_e71b1_row33_col3" class="data row33 col3" >8.978432</td>
      <td id="T_e71b1_row33_col4" class="data row33 col4" >10.027008</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row34" class="row_heading level0 row34" >34</th>
      <td id="T_e71b1_row34_col0" class="data row34 col0" >g5</td>
      <td id="T_e71b1_row34_col1" class="data row34 col1" >36.438016</td>
      <td id="T_e71b1_row34_col2" class="data row34 col2" >10.027008</td>
      <td id="T_e71b1_row34_col3" class="data row34 col3" >9.240576</td>
      <td id="T_e71b1_row34_col4" class="data row34 col4" >10.289152</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row35" class="row_heading level0 row35" >35</th>
      <td id="T_e71b1_row35_col0" class="data row35 col0" >h1</td>
      <td id="T_e71b1_row35_col1" class="data row35 col1" >36.438016</td>
      <td id="T_e71b1_row35_col2" class="data row35 col2" >9.764864</td>
      <td id="T_e71b1_row35_col3" class="data row35 col3" >10.420224</td>
      <td id="T_e71b1_row35_col4" class="data row35 col4" >10.944512</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row36" class="row_heading level0 row36" >36</th>
      <td id="T_e71b1_row36_col0" class="data row36 col0" >h2</td>
      <td id="T_e71b1_row36_col1" class="data row36 col1" >39.059456</td>
      <td id="T_e71b1_row36_col2" class="data row36 col2" >10.158080</td>
      <td id="T_e71b1_row36_col3" class="data row36 col3" >9.371648</td>
      <td id="T_e71b1_row36_col4" class="data row36 col4" >10.944512</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row37" class="row_heading level0 row37" >37</th>
      <td id="T_e71b1_row37_col0" class="data row37 col0" >h3</td>
      <td id="T_e71b1_row37_col1" class="data row37 col1" >36.438016</td>
      <td id="T_e71b1_row37_col2" class="data row37 col2" >25.821184</td>
      <td id="T_e71b1_row37_col3" class="data row37 col3" >9.240576</td>
      <td id="T_e71b1_row37_col4" class="data row37 col4" >11.599872</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row38" class="row_heading level0 row38" >38</th>
      <td id="T_e71b1_row38_col0" class="data row38 col0" >h4</td>
      <td id="T_e71b1_row38_col1" class="data row38 col1" >36.438016</td>
      <td id="T_e71b1_row38_col2" class="data row38 col2" >25.821184</td>
      <td id="T_e71b1_row38_col3" class="data row38 col3" >8.978432</td>
      <td id="T_e71b1_row38_col4" class="data row38 col4" >11.206656</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row39" class="row_heading level0 row39" >39</th>
      <td id="T_e71b1_row39_col0" class="data row39 col0" >h5</td>
      <td id="T_e71b1_row39_col1" class="data row39 col1" >36.438016</td>
      <td id="T_e71b1_row39_col2" class="data row39 col2" >25.821184</td>
      <td id="T_e71b1_row39_col3" class="data row39 col3" >9.109504</td>
      <td id="T_e71b1_row39_col4" class="data row39 col4" >10.289152</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row40" class="row_heading level0 row40" >40</th>
      <td id="T_e71b1_row40_col0" class="data row40 col0" >i1</td>
      <td id="T_e71b1_row40_col1" class="data row40 col1" >36.438016</td>
      <td id="T_e71b1_row40_col2" class="data row40 col2" >23.724032</td>
      <td id="T_e71b1_row40_col3" class="data row40 col3" >9.633792</td>
      <td id="T_e71b1_row40_col4" class="data row40 col4" >10.682368</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row41" class="row_heading level0 row41" >41</th>
      <td id="T_e71b1_row41_col0" class="data row41 col0" >i2</td>
      <td id="T_e71b1_row41_col1" class="data row41 col1" >36.438016</td>
      <td id="T_e71b1_row41_col2" class="data row41 col2" >24.248320</td>
      <td id="T_e71b1_row41_col3" class="data row41 col3" >9.109504</td>
      <td id="T_e71b1_row41_col4" class="data row41 col4" >11.337728</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row42" class="row_heading level0 row42" >42</th>
      <td id="T_e71b1_row42_col0" class="data row42 col0" >i3</td>
      <td id="T_e71b1_row42_col1" class="data row42 col1" >36.438016</td>
      <td id="T_e71b1_row42_col2" class="data row42 col2" >25.559040</td>
      <td id="T_e71b1_row42_col3" class="data row42 col3" >10.158080</td>
      <td id="T_e71b1_row42_col4" class="data row42 col4" >11.862016</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row43" class="row_heading level0 row43" >43</th>
      <td id="T_e71b1_row43_col0" class="data row43 col0" >i4</td>
      <td id="T_e71b1_row43_col1" class="data row43 col1" >36.438016</td>
      <td id="T_e71b1_row43_col2" class="data row43 col2" >25.296896</td>
      <td id="T_e71b1_row43_col3" class="data row43 col3" >10.289152</td>
      <td id="T_e71b1_row43_col4" class="data row43 col4" >10.682368</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row44" class="row_heading level0 row44" >44</th>
      <td id="T_e71b1_row44_col0" class="data row44 col0" >i5</td>
      <td id="T_e71b1_row44_col1" class="data row44 col1" >36.438016</td>
      <td id="T_e71b1_row44_col2" class="data row44 col2" >26.083328</td>
      <td id="T_e71b1_row44_col3" class="data row44 col3" >9.633792</td>
      <td id="T_e71b1_row44_col4" class="data row44 col4" >10.813440</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row45" class="row_heading level0 row45" >45</th>
      <td id="T_e71b1_row45_col0" class="data row45 col0" >j1</td>
      <td id="T_e71b1_row45_col1" class="data row45 col1" >36.438016</td>
      <td id="T_e71b1_row45_col2" class="data row45 col2" >26.083328</td>
      <td id="T_e71b1_row45_col3" class="data row45 col3" >8.716288</td>
      <td id="T_e71b1_row45_col4" class="data row45 col4" >10.551296</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row46" class="row_heading level0 row46" >46</th>
      <td id="T_e71b1_row46_col0" class="data row46 col0" >j2</td>
      <td id="T_e71b1_row46_col1" class="data row46 col1" >39.059456</td>
      <td id="T_e71b1_row46_col2" class="data row46 col2" >25.821184</td>
      <td id="T_e71b1_row46_col3" class="data row46 col3" >10.027008</td>
      <td id="T_e71b1_row46_col4" class="data row46 col4" >10.289152</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row47" class="row_heading level0 row47" >47</th>
      <td id="T_e71b1_row47_col0" class="data row47 col0" >j3</td>
      <td id="T_e71b1_row47_col1" class="data row47 col1" >39.059456</td>
      <td id="T_e71b1_row47_col2" class="data row47 col2" >23.724032</td>
      <td id="T_e71b1_row47_col3" class="data row47 col3" >10.551296</td>
      <td id="T_e71b1_row47_col4" class="data row47 col4" >10.813440</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row48" class="row_heading level0 row48" >48</th>
      <td id="T_e71b1_row48_col0" class="data row48 col0" >j4</td>
      <td id="T_e71b1_row48_col1" class="data row48 col1" >36.438016</td>
      <td id="T_e71b1_row48_col2" class="data row48 col2" >23.986176</td>
      <td id="T_e71b1_row48_col3" class="data row48 col3" >9.371648</td>
      <td id="T_e71b1_row48_col4" class="data row48 col4" >10.944512</td>
    </tr>
    <tr>
      <th id="T_e71b1_level0_row49" class="row_heading level0 row49" >49</th>
      <td id="T_e71b1_row49_col0" class="data row49 col0" >j5</td>
      <td id="T_e71b1_row49_col1" class="data row49 col1" >39.059456</td>
      <td id="T_e71b1_row49_col2" class="data row49 col2" >25.821184</td>
      <td id="T_e71b1_row49_col3" class="data row49 col3" >8.847360</td>
      <td id="T_e71b1_row49_col4" class="data row49 col4" >10.289152</td>
    </tr>
  </tbody>
</table>




____
**FIO sync lattency Mean in ms (sync_lat_mean_ms)**

Summary of results:
- gp2: isolated etcd disk reported slower than single disk
- gp3: had similar results in both scenarios


```python
aggregate_metric('sync_lat_mean_ms').rename(columns={"b2_t1": "gp2x1","b2_t2": "gp2x2","b2_t3": "gp3x1","b2_t4": "gp3x2"})\
    .style.applymap(_df_style_high, subset=["gp2x1", "gp2x2", "gp3x1", "gp3x2"], value_yellow=2.0, value_red=5.0)
```




<style type="text/css">
#T_6cdca_row32_col1 {
  background-color: yellow;
}
#T_6cdca_row33_col1, #T_6cdca_row34_col1, #T_6cdca_row35_col1, #T_6cdca_row36_col1, #T_6cdca_row37_col1, #T_6cdca_row37_col2, #T_6cdca_row38_col1, #T_6cdca_row38_col2, #T_6cdca_row39_col1, #T_6cdca_row39_col2, #T_6cdca_row40_col1, #T_6cdca_row40_col2, #T_6cdca_row41_col1, #T_6cdca_row41_col2, #T_6cdca_row42_col1, #T_6cdca_row42_col2, #T_6cdca_row43_col1, #T_6cdca_row43_col2, #T_6cdca_row44_col1, #T_6cdca_row44_col2, #T_6cdca_row45_col1, #T_6cdca_row45_col2, #T_6cdca_row46_col1, #T_6cdca_row46_col2, #T_6cdca_row47_col1, #T_6cdca_row47_col2, #T_6cdca_row48_col1, #T_6cdca_row48_col2, #T_6cdca_row49_col1, #T_6cdca_row49_col2 {
  background-color: red;
}
</style>
<table id="T_6cdca_">
  <thead>
    <tr>
      <th class="blank level0" >&nbsp;</th>
      <th class="col_heading level0 col0" >job_Id</th>
      <th class="col_heading level0 col1" >gp2x1</th>
      <th class="col_heading level0 col2" >gp2x2</th>
      <th class="col_heading level0 col3" >gp3x1</th>
      <th class="col_heading level0 col4" >gp3x2</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th id="T_6cdca_level0_row0" class="row_heading level0 row0" >0</th>
      <td id="T_6cdca_row0_col0" class="data row0 col0" >a1</td>
      <td id="T_6cdca_row0_col1" class="data row0 col1" >0.789064</td>
      <td id="T_6cdca_row0_col2" class="data row0 col2" >1.319287</td>
      <td id="T_6cdca_row0_col3" class="data row0 col3" >1.333167</td>
      <td id="T_6cdca_row0_col4" class="data row0 col4" >1.712503</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row1" class="row_heading level0 row1" >1</th>
      <td id="T_6cdca_row1_col0" class="data row1 col0" >a2</td>
      <td id="T_6cdca_row1_col1" class="data row1 col1" >1.056788</td>
      <td id="T_6cdca_row1_col2" class="data row1 col2" >1.348980</td>
      <td id="T_6cdca_row1_col3" class="data row1 col3" >1.687630</td>
      <td id="T_6cdca_row1_col4" class="data row1 col4" >1.756673</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row2" class="row_heading level0 row2" >2</th>
      <td id="T_6cdca_row2_col0" class="data row2 col0" >a3</td>
      <td id="T_6cdca_row2_col1" class="data row2 col1" >1.070381</td>
      <td id="T_6cdca_row2_col2" class="data row2 col2" >1.334769</td>
      <td id="T_6cdca_row2_col3" class="data row2 col3" >1.650445</td>
      <td id="T_6cdca_row2_col4" class="data row2 col4" >1.626919</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row3" class="row_heading level0 row3" >3</th>
      <td id="T_6cdca_row3_col0" class="data row3 col0" >a4</td>
      <td id="T_6cdca_row3_col1" class="data row3 col1" >1.068620</td>
      <td id="T_6cdca_row3_col2" class="data row3 col2" >1.322543</td>
      <td id="T_6cdca_row3_col3" class="data row3 col3" >1.641819</td>
      <td id="T_6cdca_row3_col4" class="data row3 col4" >1.633420</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row4" class="row_heading level0 row4" >4</th>
      <td id="T_6cdca_row4_col0" class="data row4 col0" >a5</td>
      <td id="T_6cdca_row4_col1" class="data row4 col1" >1.069686</td>
      <td id="T_6cdca_row4_col2" class="data row4 col2" >1.363166</td>
      <td id="T_6cdca_row4_col3" class="data row4 col3" >1.666814</td>
      <td id="T_6cdca_row4_col4" class="data row4 col4" >1.701093</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row5" class="row_heading level0 row5" >5</th>
      <td id="T_6cdca_row5_col0" class="data row5 col0" >b1</td>
      <td id="T_6cdca_row5_col1" class="data row5 col1" >1.075730</td>
      <td id="T_6cdca_row5_col2" class="data row5 col2" >1.342571</td>
      <td id="T_6cdca_row5_col3" class="data row5 col3" >1.681684</td>
      <td id="T_6cdca_row5_col4" class="data row5 col4" >1.759722</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row6" class="row_heading level0 row6" >6</th>
      <td id="T_6cdca_row6_col0" class="data row6 col0" >b2</td>
      <td id="T_6cdca_row6_col1" class="data row6 col1" >1.065582</td>
      <td id="T_6cdca_row6_col2" class="data row6 col2" >1.380487</td>
      <td id="T_6cdca_row6_col3" class="data row6 col3" >1.774595</td>
      <td id="T_6cdca_row6_col4" class="data row6 col4" >1.649717</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row7" class="row_heading level0 row7" >7</th>
      <td id="T_6cdca_row7_col0" class="data row7 col0" >b3</td>
      <td id="T_6cdca_row7_col1" class="data row7 col1" >1.041871</td>
      <td id="T_6cdca_row7_col2" class="data row7 col2" >1.349172</td>
      <td id="T_6cdca_row7_col3" class="data row7 col3" >1.744623</td>
      <td id="T_6cdca_row7_col4" class="data row7 col4" >1.654040</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row8" class="row_heading level0 row8" >8</th>
      <td id="T_6cdca_row8_col0" class="data row8 col0" >b4</td>
      <td id="T_6cdca_row8_col1" class="data row8 col1" >1.060716</td>
      <td id="T_6cdca_row8_col2" class="data row8 col2" >1.323254</td>
      <td id="T_6cdca_row8_col3" class="data row8 col3" >1.722502</td>
      <td id="T_6cdca_row8_col4" class="data row8 col4" >1.703117</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row9" class="row_heading level0 row9" >9</th>
      <td id="T_6cdca_row9_col0" class="data row9 col0" >b5</td>
      <td id="T_6cdca_row9_col1" class="data row9 col1" >1.053578</td>
      <td id="T_6cdca_row9_col2" class="data row9 col2" >1.314879</td>
      <td id="T_6cdca_row9_col3" class="data row9 col3" >1.681496</td>
      <td id="T_6cdca_row9_col4" class="data row9 col4" >1.630997</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row10" class="row_heading level0 row10" >10</th>
      <td id="T_6cdca_row10_col0" class="data row10 col0" >c1</td>
      <td id="T_6cdca_row10_col1" class="data row10 col1" >1.070039</td>
      <td id="T_6cdca_row10_col2" class="data row10 col2" >1.288025</td>
      <td id="T_6cdca_row10_col3" class="data row10 col3" >1.601921</td>
      <td id="T_6cdca_row10_col4" class="data row10 col4" >1.688473</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row11" class="row_heading level0 row11" >11</th>
      <td id="T_6cdca_row11_col0" class="data row11 col0" >c2</td>
      <td id="T_6cdca_row11_col1" class="data row11 col1" >1.160528</td>
      <td id="T_6cdca_row11_col2" class="data row11 col2" >1.310626</td>
      <td id="T_6cdca_row11_col3" class="data row11 col3" >1.593500</td>
      <td id="T_6cdca_row11_col4" class="data row11 col4" >1.540552</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row12" class="row_heading level0 row12" >12</th>
      <td id="T_6cdca_row12_col0" class="data row12 col0" >c3</td>
      <td id="T_6cdca_row12_col1" class="data row12 col1" >1.193205</td>
      <td id="T_6cdca_row12_col2" class="data row12 col2" >1.325149</td>
      <td id="T_6cdca_row12_col3" class="data row12 col3" >1.629773</td>
      <td id="T_6cdca_row12_col4" class="data row12 col4" >1.653208</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row13" class="row_heading level0 row13" >13</th>
      <td id="T_6cdca_row13_col0" class="data row13 col0" >c4</td>
      <td id="T_6cdca_row13_col1" class="data row13 col1" >1.106304</td>
      <td id="T_6cdca_row13_col2" class="data row13 col2" >1.327079</td>
      <td id="T_6cdca_row13_col3" class="data row13 col3" >1.612760</td>
      <td id="T_6cdca_row13_col4" class="data row13 col4" >1.679135</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row14" class="row_heading level0 row14" >14</th>
      <td id="T_6cdca_row14_col0" class="data row14 col0" >c5</td>
      <td id="T_6cdca_row14_col1" class="data row14 col1" >1.114071</td>
      <td id="T_6cdca_row14_col2" class="data row14 col2" >1.326199</td>
      <td id="T_6cdca_row14_col3" class="data row14 col3" >1.596592</td>
      <td id="T_6cdca_row14_col4" class="data row14 col4" >1.620467</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row15" class="row_heading level0 row15" >15</th>
      <td id="T_6cdca_row15_col0" class="data row15 col0" >d1</td>
      <td id="T_6cdca_row15_col1" class="data row15 col1" >1.094274</td>
      <td id="T_6cdca_row15_col2" class="data row15 col2" >1.343508</td>
      <td id="T_6cdca_row15_col3" class="data row15 col3" >1.645699</td>
      <td id="T_6cdca_row15_col4" class="data row15 col4" >1.627862</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row16" class="row_heading level0 row16" >16</th>
      <td id="T_6cdca_row16_col0" class="data row16 col0" >d2</td>
      <td id="T_6cdca_row16_col1" class="data row16 col1" >1.085720</td>
      <td id="T_6cdca_row16_col2" class="data row16 col2" >1.340880</td>
      <td id="T_6cdca_row16_col3" class="data row16 col3" >1.615442</td>
      <td id="T_6cdca_row16_col4" class="data row16 col4" >1.601489</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row17" class="row_heading level0 row17" >17</th>
      <td id="T_6cdca_row17_col0" class="data row17 col0" >d3</td>
      <td id="T_6cdca_row17_col1" class="data row17 col1" >1.073432</td>
      <td id="T_6cdca_row17_col2" class="data row17 col2" >1.341512</td>
      <td id="T_6cdca_row17_col3" class="data row17 col3" >1.609966</td>
      <td id="T_6cdca_row17_col4" class="data row17 col4" >1.682410</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row18" class="row_heading level0 row18" >18</th>
      <td id="T_6cdca_row18_col0" class="data row18 col0" >d4</td>
      <td id="T_6cdca_row18_col1" class="data row18 col1" >1.107403</td>
      <td id="T_6cdca_row18_col2" class="data row18 col2" >1.338761</td>
      <td id="T_6cdca_row18_col3" class="data row18 col3" >1.595604</td>
      <td id="T_6cdca_row18_col4" class="data row18 col4" >1.690741</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row19" class="row_heading level0 row19" >19</th>
      <td id="T_6cdca_row19_col0" class="data row19 col0" >d5</td>
      <td id="T_6cdca_row19_col1" class="data row19 col1" >1.132898</td>
      <td id="T_6cdca_row19_col2" class="data row19 col2" >1.338119</td>
      <td id="T_6cdca_row19_col3" class="data row19 col3" >1.597500</td>
      <td id="T_6cdca_row19_col4" class="data row19 col4" >1.613168</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row20" class="row_heading level0 row20" >20</th>
      <td id="T_6cdca_row20_col0" class="data row20 col0" >e1</td>
      <td id="T_6cdca_row20_col1" class="data row20 col1" >1.161496</td>
      <td id="T_6cdca_row20_col2" class="data row20 col2" >1.313773</td>
      <td id="T_6cdca_row20_col3" class="data row20 col3" >1.581205</td>
      <td id="T_6cdca_row20_col4" class="data row20 col4" >1.616357</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row21" class="row_heading level0 row21" >21</th>
      <td id="T_6cdca_row21_col0" class="data row21 col0" >e2</td>
      <td id="T_6cdca_row21_col1" class="data row21 col1" >1.196111</td>
      <td id="T_6cdca_row21_col2" class="data row21 col2" >1.337504</td>
      <td id="T_6cdca_row21_col3" class="data row21 col3" >1.620661</td>
      <td id="T_6cdca_row21_col4" class="data row21 col4" >1.585113</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row22" class="row_heading level0 row22" >22</th>
      <td id="T_6cdca_row22_col0" class="data row22 col0" >e3</td>
      <td id="T_6cdca_row22_col1" class="data row22 col1" >1.110110</td>
      <td id="T_6cdca_row22_col2" class="data row22 col2" >1.352634</td>
      <td id="T_6cdca_row22_col3" class="data row22 col3" >1.635464</td>
      <td id="T_6cdca_row22_col4" class="data row22 col4" >1.600341</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row23" class="row_heading level0 row23" >23</th>
      <td id="T_6cdca_row23_col0" class="data row23 col0" >e4</td>
      <td id="T_6cdca_row23_col1" class="data row23 col1" >1.082656</td>
      <td id="T_6cdca_row23_col2" class="data row23 col2" >1.321663</td>
      <td id="T_6cdca_row23_col3" class="data row23 col3" >1.622308</td>
      <td id="T_6cdca_row23_col4" class="data row23 col4" >1.694389</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row24" class="row_heading level0 row24" >24</th>
      <td id="T_6cdca_row24_col0" class="data row24 col0" >e5</td>
      <td id="T_6cdca_row24_col1" class="data row24 col1" >1.081432</td>
      <td id="T_6cdca_row24_col2" class="data row24 col2" >1.355056</td>
      <td id="T_6cdca_row24_col3" class="data row24 col3" >1.667598</td>
      <td id="T_6cdca_row24_col4" class="data row24 col4" >1.656733</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row25" class="row_heading level0 row25" >25</th>
      <td id="T_6cdca_row25_col0" class="data row25 col0" >f1</td>
      <td id="T_6cdca_row25_col1" class="data row25 col1" >1.073290</td>
      <td id="T_6cdca_row25_col2" class="data row25 col2" >1.292314</td>
      <td id="T_6cdca_row25_col3" class="data row25 col3" >1.704640</td>
      <td id="T_6cdca_row25_col4" class="data row25 col4" >1.721286</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row26" class="row_heading level0 row26" >26</th>
      <td id="T_6cdca_row26_col0" class="data row26 col0" >f2</td>
      <td id="T_6cdca_row26_col1" class="data row26 col1" >1.101784</td>
      <td id="T_6cdca_row26_col2" class="data row26 col2" >1.270952</td>
      <td id="T_6cdca_row26_col3" class="data row26 col3" >1.675780</td>
      <td id="T_6cdca_row26_col4" class="data row26 col4" >1.736041</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row27" class="row_heading level0 row27" >27</th>
      <td id="T_6cdca_row27_col0" class="data row27 col0" >f3</td>
      <td id="T_6cdca_row27_col1" class="data row27 col1" >1.126240</td>
      <td id="T_6cdca_row27_col2" class="data row27 col2" >1.304639</td>
      <td id="T_6cdca_row27_col3" class="data row27 col3" >1.627094</td>
      <td id="T_6cdca_row27_col4" class="data row27 col4" >1.645838</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row28" class="row_heading level0 row28" >28</th>
      <td id="T_6cdca_row28_col0" class="data row28 col0" >f4</td>
      <td id="T_6cdca_row28_col1" class="data row28 col1" >1.113870</td>
      <td id="T_6cdca_row28_col2" class="data row28 col2" >1.320057</td>
      <td id="T_6cdca_row28_col3" class="data row28 col3" >1.640222</td>
      <td id="T_6cdca_row28_col4" class="data row28 col4" >1.663913</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row29" class="row_heading level0 row29" >29</th>
      <td id="T_6cdca_row29_col0" class="data row29 col0" >f5</td>
      <td id="T_6cdca_row29_col1" class="data row29 col1" >1.086203</td>
      <td id="T_6cdca_row29_col2" class="data row29 col2" >1.304557</td>
      <td id="T_6cdca_row29_col3" class="data row29 col3" >1.666991</td>
      <td id="T_6cdca_row29_col4" class="data row29 col4" >1.641694</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row30" class="row_heading level0 row30" >30</th>
      <td id="T_6cdca_row30_col0" class="data row30 col0" >g1</td>
      <td id="T_6cdca_row30_col1" class="data row30 col1" >1.157267</td>
      <td id="T_6cdca_row30_col2" class="data row30 col2" >1.302631</td>
      <td id="T_6cdca_row30_col3" class="data row30 col3" >1.657269</td>
      <td id="T_6cdca_row30_col4" class="data row30 col4" >1.636465</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row31" class="row_heading level0 row31" >31</th>
      <td id="T_6cdca_row31_col0" class="data row31 col0" >g2</td>
      <td id="T_6cdca_row31_col1" class="data row31 col1" >1.158294</td>
      <td id="T_6cdca_row31_col2" class="data row31 col2" >1.318653</td>
      <td id="T_6cdca_row31_col3" class="data row31 col3" >1.649059</td>
      <td id="T_6cdca_row31_col4" class="data row31 col4" >1.599612</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row32" class="row_heading level0 row32" >32</th>
      <td id="T_6cdca_row32_col0" class="data row32 col0" >g3</td>
      <td id="T_6cdca_row32_col1" class="data row32 col1" >4.443336</td>
      <td id="T_6cdca_row32_col2" class="data row32 col2" >1.278411</td>
      <td id="T_6cdca_row32_col3" class="data row32 col3" >1.687637</td>
      <td id="T_6cdca_row32_col4" class="data row32 col4" >1.619913</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row33" class="row_heading level0 row33" >33</th>
      <td id="T_6cdca_row33_col0" class="data row33 col0" >g4</td>
      <td id="T_6cdca_row33_col1" class="data row33 col1" >5.903099</td>
      <td id="T_6cdca_row33_col2" class="data row33 col2" >1.326244</td>
      <td id="T_6cdca_row33_col3" class="data row33 col3" >1.659621</td>
      <td id="T_6cdca_row33_col4" class="data row33 col4" >1.573605</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row34" class="row_heading level0 row34" >34</th>
      <td id="T_6cdca_row34_col0" class="data row34 col0" >g5</td>
      <td id="T_6cdca_row34_col1" class="data row34 col1" >5.923943</td>
      <td id="T_6cdca_row34_col2" class="data row34 col2" >1.340073</td>
      <td id="T_6cdca_row34_col3" class="data row34 col3" >1.659012</td>
      <td id="T_6cdca_row34_col4" class="data row34 col4" >1.642198</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row35" class="row_heading level0 row35" >35</th>
      <td id="T_6cdca_row35_col0" class="data row35 col0" >h1</td>
      <td id="T_6cdca_row35_col1" class="data row35 col1" >5.924606</td>
      <td id="T_6cdca_row35_col2" class="data row35 col2" >1.319705</td>
      <td id="T_6cdca_row35_col3" class="data row35 col3" >1.681932</td>
      <td id="T_6cdca_row35_col4" class="data row35 col4" >1.669151</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row36" class="row_heading level0 row36" >36</th>
      <td id="T_6cdca_row36_col0" class="data row36 col0" >h2</td>
      <td id="T_6cdca_row36_col1" class="data row36 col1" >5.917048</td>
      <td id="T_6cdca_row36_col2" class="data row36 col2" >1.336998</td>
      <td id="T_6cdca_row36_col3" class="data row36 col3" >1.615984</td>
      <td id="T_6cdca_row36_col4" class="data row36 col4" >1.716879</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row37" class="row_heading level0 row37" >37</th>
      <td id="T_6cdca_row37_col0" class="data row37 col0" >h3</td>
      <td id="T_6cdca_row37_col1" class="data row37 col1" >5.899914</td>
      <td id="T_6cdca_row37_col2" class="data row37 col2" >5.690261</td>
      <td id="T_6cdca_row37_col3" class="data row37 col3" >1.646508</td>
      <td id="T_6cdca_row37_col4" class="data row37 col4" >1.724542</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row38" class="row_heading level0 row38" >38</th>
      <td id="T_6cdca_row38_col0" class="data row38 col0" >h4</td>
      <td id="T_6cdca_row38_col1" class="data row38 col1" >5.904183</td>
      <td id="T_6cdca_row38_col2" class="data row38 col2" >5.808433</td>
      <td id="T_6cdca_row38_col3" class="data row38 col3" >1.623840</td>
      <td id="T_6cdca_row38_col4" class="data row38 col4" >1.746813</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row39" class="row_heading level0 row39" >39</th>
      <td id="T_6cdca_row39_col0" class="data row39 col0" >h5</td>
      <td id="T_6cdca_row39_col1" class="data row39 col1" >5.896509</td>
      <td id="T_6cdca_row39_col2" class="data row39 col2" >5.841664</td>
      <td id="T_6cdca_row39_col3" class="data row39 col3" >1.632903</td>
      <td id="T_6cdca_row39_col4" class="data row39 col4" >1.668419</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row40" class="row_heading level0 row40" >40</th>
      <td id="T_6cdca_row40_col0" class="data row40 col0" >i1</td>
      <td id="T_6cdca_row40_col1" class="data row40 col1" >5.905301</td>
      <td id="T_6cdca_row40_col2" class="data row40 col2" >5.849903</td>
      <td id="T_6cdca_row40_col3" class="data row40 col3" >1.675081</td>
      <td id="T_6cdca_row40_col4" class="data row40 col4" >1.727930</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row41" class="row_heading level0 row41" >41</th>
      <td id="T_6cdca_row41_col0" class="data row41 col0" >i2</td>
      <td id="T_6cdca_row41_col1" class="data row41 col1" >5.933013</td>
      <td id="T_6cdca_row41_col2" class="data row41 col2" >5.862731</td>
      <td id="T_6cdca_row41_col3" class="data row41 col3" >1.710924</td>
      <td id="T_6cdca_row41_col4" class="data row41 col4" >1.690698</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row42" class="row_heading level0 row42" >42</th>
      <td id="T_6cdca_row42_col0" class="data row42 col0" >i3</td>
      <td id="T_6cdca_row42_col1" class="data row42 col1" >5.918613</td>
      <td id="T_6cdca_row42_col2" class="data row42 col2" >5.841414</td>
      <td id="T_6cdca_row42_col3" class="data row42 col3" >1.746246</td>
      <td id="T_6cdca_row42_col4" class="data row42 col4" >1.678174</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row43" class="row_heading level0 row43" >43</th>
      <td id="T_6cdca_row43_col0" class="data row43 col0" >i4</td>
      <td id="T_6cdca_row43_col1" class="data row43 col1" >5.917122</td>
      <td id="T_6cdca_row43_col2" class="data row43 col2" >5.845320</td>
      <td id="T_6cdca_row43_col3" class="data row43 col3" >1.773936</td>
      <td id="T_6cdca_row43_col4" class="data row43 col4" >1.637586</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row44" class="row_heading level0 row44" >44</th>
      <td id="T_6cdca_row44_col0" class="data row44 col0" >i5</td>
      <td id="T_6cdca_row44_col1" class="data row44 col1" >5.912760</td>
      <td id="T_6cdca_row44_col2" class="data row44 col2" >5.839628</td>
      <td id="T_6cdca_row44_col3" class="data row44 col3" >1.690446</td>
      <td id="T_6cdca_row44_col4" class="data row44 col4" >1.681608</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row45" class="row_heading level0 row45" >45</th>
      <td id="T_6cdca_row45_col0" class="data row45 col0" >j1</td>
      <td id="T_6cdca_row45_col1" class="data row45 col1" >5.926906</td>
      <td id="T_6cdca_row45_col2" class="data row45 col2" >5.854145</td>
      <td id="T_6cdca_row45_col3" class="data row45 col3" >1.620321</td>
      <td id="T_6cdca_row45_col4" class="data row45 col4" >1.657394</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row46" class="row_heading level0 row46" >46</th>
      <td id="T_6cdca_row46_col0" class="data row46 col0" >j2</td>
      <td id="T_6cdca_row46_col1" class="data row46 col1" >5.928445</td>
      <td id="T_6cdca_row46_col2" class="data row46 col2" >5.847236</td>
      <td id="T_6cdca_row46_col3" class="data row46 col3" >1.713289</td>
      <td id="T_6cdca_row46_col4" class="data row46 col4" >1.614540</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row47" class="row_heading level0 row47" >47</th>
      <td id="T_6cdca_row47_col0" class="data row47 col0" >j3</td>
      <td id="T_6cdca_row47_col1" class="data row47 col1" >5.936170</td>
      <td id="T_6cdca_row47_col2" class="data row47 col2" >5.845602</td>
      <td id="T_6cdca_row47_col3" class="data row47 col3" >1.796371</td>
      <td id="T_6cdca_row47_col4" class="data row47 col4" >1.728508</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row48" class="row_heading level0 row48" >48</th>
      <td id="T_6cdca_row48_col0" class="data row48 col0" >j4</td>
      <td id="T_6cdca_row48_col1" class="data row48 col1" >5.940704</td>
      <td id="T_6cdca_row48_col2" class="data row48 col2" >5.839305</td>
      <td id="T_6cdca_row48_col3" class="data row48 col3" >1.628370</td>
      <td id="T_6cdca_row48_col4" class="data row48 col4" >1.668683</td>
    </tr>
    <tr>
      <th id="T_6cdca_level0_row49" class="row_heading level0 row49" >49</th>
      <td id="T_6cdca_row49_col0" class="data row49 col0" >j5</td>
      <td id="T_6cdca_row49_col1" class="data row49 col1" >5.938387</td>
      <td id="T_6cdca_row49_col2" class="data row49 col2" >5.827451</td>
      <td id="T_6cdca_row49_col3" class="data row49 col3" >1.614145</td>
      <td id="T_6cdca_row49_col4" class="data row49 col4" >1.615724</td>
    </tr>
  </tbody>
</table>




____
**FIO sync lattency Mean in ms (sync_lat_max_ms)**

Summary of results:
- isolated gp2 become more reliable than single disk when burst balance ended


```python
aggregate_metric('sync_lat_max_ms').rename(columns={"b2_t1": "gp2x1","b2_t2": "gp2x2","b2_t3": "gp3x1","b2_t4": "gp3x2"}).\
    style.applymap(_df_style_high, subset=["gp2x1", "gp2x2", "gp3x1", "gp3x2"], value_yellow=50.0, value_red=100.0)
```




<style type="text/css">
#T_9db92_row0_col3, #T_9db92_row0_col4, #T_9db92_row1_col1, #T_9db92_row1_col4, #T_9db92_row2_col3, #T_9db92_row2_col4, #T_9db92_row4_col1, #T_9db92_row4_col2, #T_9db92_row4_col3, #T_9db92_row4_col4, #T_9db92_row5_col3, #T_9db92_row6_col1, #T_9db92_row6_col2, #T_9db92_row6_col4, #T_9db92_row7_col1, #T_9db92_row7_col2, #T_9db92_row8_col1, #T_9db92_row9_col1, #T_9db92_row9_col2, #T_9db92_row9_col4, #T_9db92_row10_col1, #T_9db92_row10_col3, #T_9db92_row11_col1, #T_9db92_row11_col3, #T_9db92_row11_col4, #T_9db92_row12_col4, #T_9db92_row14_col1, #T_9db92_row15_col1, #T_9db92_row15_col2, #T_9db92_row15_col4, #T_9db92_row17_col2, #T_9db92_row17_col3, #T_9db92_row18_col2, #T_9db92_row18_col3, #T_9db92_row19_col4, #T_9db92_row20_col1, #T_9db92_row20_col4, #T_9db92_row21_col2, #T_9db92_row21_col3, #T_9db92_row21_col4, #T_9db92_row22_col1, #T_9db92_row22_col4, #T_9db92_row23_col1, #T_9db92_row24_col4, #T_9db92_row25_col4, #T_9db92_row26_col1, #T_9db92_row26_col4, #T_9db92_row27_col2, #T_9db92_row27_col3, #T_9db92_row28_col1, #T_9db92_row28_col2, #T_9db92_row29_col3, #T_9db92_row30_col2, #T_9db92_row31_col1, #T_9db92_row31_col2, #T_9db92_row31_col3, #T_9db92_row31_col4, #T_9db92_row32_col1, #T_9db92_row32_col4, #T_9db92_row34_col2, #T_9db92_row34_col4, #T_9db92_row35_col2, #T_9db92_row35_col4, #T_9db92_row36_col1, #T_9db92_row36_col4, #T_9db92_row37_col2, #T_9db92_row37_col4, #T_9db92_row38_col2, #T_9db92_row38_col3, #T_9db92_row39_col2, #T_9db92_row39_col3, #T_9db92_row40_col2, #T_9db92_row40_col3, #T_9db92_row41_col2, #T_9db92_row41_col3, #T_9db92_row41_col4, #T_9db92_row42_col2, #T_9db92_row42_col3, #T_9db92_row42_col4, #T_9db92_row43_col2, #T_9db92_row43_col3, #T_9db92_row44_col2, #T_9db92_row44_col3, #T_9db92_row44_col4, #T_9db92_row45_col2, #T_9db92_row45_col3, #T_9db92_row45_col4, #T_9db92_row46_col2, #T_9db92_row46_col3, #T_9db92_row46_col4, #T_9db92_row47_col2, #T_9db92_row47_col3, #T_9db92_row48_col2, #T_9db92_row48_col4, #T_9db92_row49_col2 {
  background-color: yellow;
}
#T_9db92_row33_col1, #T_9db92_row34_col1, #T_9db92_row35_col1, #T_9db92_row37_col1, #T_9db92_row38_col1, #T_9db92_row39_col1, #T_9db92_row40_col1, #T_9db92_row41_col1, #T_9db92_row42_col1, #T_9db92_row43_col1, #T_9db92_row44_col1, #T_9db92_row45_col1, #T_9db92_row46_col1, #T_9db92_row47_col1, #T_9db92_row48_col1, #T_9db92_row49_col1 {
  background-color: red;
}
</style>
<table id="T_9db92_">
  <thead>
    <tr>
      <th class="blank level0" >&nbsp;</th>
      <th class="col_heading level0 col0" >job_Id</th>
      <th class="col_heading level0 col1" >gp2x1</th>
      <th class="col_heading level0 col2" >gp2x2</th>
      <th class="col_heading level0 col3" >gp3x1</th>
      <th class="col_heading level0 col4" >gp3x2</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th id="T_9db92_level0_row0" class="row_heading level0 row0" >0</th>
      <td id="T_9db92_row0_col0" class="data row0 col0" >a1</td>
      <td id="T_9db92_row0_col1" class="data row0 col1" >21.362522</td>
      <td id="T_9db92_row0_col2" class="data row0 col2" >42.921417</td>
      <td id="T_9db92_row0_col3" class="data row0 col3" >68.017842</td>
      <td id="T_9db92_row0_col4" class="data row0 col4" >82.157969</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row1" class="row_heading level0 row1" >1</th>
      <td id="T_9db92_row1_col0" class="data row1 col0" >a2</td>
      <td id="T_9db92_row1_col1" class="data row1 col1" >70.671594</td>
      <td id="T_9db92_row1_col2" class="data row1 col2" >28.750373</td>
      <td id="T_9db92_row1_col3" class="data row1 col3" >18.266890</td>
      <td id="T_9db92_row1_col4" class="data row1 col4" >84.258343</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row2" class="row_heading level0 row2" >2</th>
      <td id="T_9db92_row2_col0" class="data row2 col0" >a3</td>
      <td id="T_9db92_row2_col1" class="data row2 col1" >14.560474</td>
      <td id="T_9db92_row2_col2" class="data row2 col2" >19.301707</td>
      <td id="T_9db92_row2_col3" class="data row2 col3" >78.664201</td>
      <td id="T_9db92_row2_col4" class="data row2 col4" >82.106066</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row3" class="row_heading level0 row3" >3</th>
      <td id="T_9db92_row3_col0" class="data row3 col0" >a4</td>
      <td id="T_9db92_row3_col1" class="data row3 col1" >23.222146</td>
      <td id="T_9db92_row3_col2" class="data row3 col2" >35.648584</td>
      <td id="T_9db92_row3_col3" class="data row3 col3" >33.433859</td>
      <td id="T_9db92_row3_col4" class="data row3 col4" >34.026425</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row4" class="row_heading level0 row4" >4</th>
      <td id="T_9db92_row4_col0" class="data row4 col0" >a5</td>
      <td id="T_9db92_row4_col1" class="data row4 col1" >76.327184</td>
      <td id="T_9db92_row4_col2" class="data row4 col2" >80.075922</td>
      <td id="T_9db92_row4_col3" class="data row4 col3" >76.929612</td>
      <td id="T_9db92_row4_col4" class="data row4 col4" >64.642143</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row5" class="row_heading level0 row5" >5</th>
      <td id="T_9db92_row5_col0" class="data row5 col0" >b1</td>
      <td id="T_9db92_row5_col1" class="data row5 col1" >16.081376</td>
      <td id="T_9db92_row5_col2" class="data row5 col2" >16.037055</td>
      <td id="T_9db92_row5_col3" class="data row5 col3" >66.840544</td>
      <td id="T_9db92_row5_col4" class="data row5 col4" >27.682156</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row6" class="row_heading level0 row6" >6</th>
      <td id="T_9db92_row6_col0" class="data row6 col0" >b2</td>
      <td id="T_9db92_row6_col1" class="data row6 col1" >78.391998</td>
      <td id="T_9db92_row6_col2" class="data row6 col2" >67.246422</td>
      <td id="T_9db92_row6_col3" class="data row6 col3" >46.956900</td>
      <td id="T_9db92_row6_col4" class="data row6 col4" >86.332541</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row7" class="row_heading level0 row7" >7</th>
      <td id="T_9db92_row7_col0" class="data row7 col0" >b3</td>
      <td id="T_9db92_row7_col1" class="data row7 col1" >87.659569</td>
      <td id="T_9db92_row7_col2" class="data row7 col2" >68.943773</td>
      <td id="T_9db92_row7_col3" class="data row7 col3" >22.667406</td>
      <td id="T_9db92_row7_col4" class="data row7 col4" >19.102149</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row8" class="row_heading level0 row8" >8</th>
      <td id="T_9db92_row8_col0" class="data row8 col0" >b4</td>
      <td id="T_9db92_row8_col1" class="data row8 col1" >75.570967</td>
      <td id="T_9db92_row8_col2" class="data row8 col2" >17.130309</td>
      <td id="T_9db92_row8_col3" class="data row8 col3" >33.258572</td>
      <td id="T_9db92_row8_col4" class="data row8 col4" >18.097099</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row9" class="row_heading level0 row9" >9</th>
      <td id="T_9db92_row9_col0" class="data row9 col0" >b5</td>
      <td id="T_9db92_row9_col1" class="data row9 col1" >90.578402</td>
      <td id="T_9db92_row9_col2" class="data row9 col2" >83.009037</td>
      <td id="T_9db92_row9_col3" class="data row9 col3" >32.785594</td>
      <td id="T_9db92_row9_col4" class="data row9 col4" >82.894287</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row10" class="row_heading level0 row10" >10</th>
      <td id="T_9db92_row10_col0" class="data row10 col0" >c1</td>
      <td id="T_9db92_row10_col1" class="data row10 col1" >73.352157</td>
      <td id="T_9db92_row10_col2" class="data row10 col2" >21.638637</td>
      <td id="T_9db92_row10_col3" class="data row10 col3" >59.235491</td>
      <td id="T_9db92_row10_col4" class="data row10 col4" >34.250775</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row11" class="row_heading level0 row11" >11</th>
      <td id="T_9db92_row11_col0" class="data row11 col0" >c2</td>
      <td id="T_9db92_row11_col1" class="data row11 col1" >85.045124</td>
      <td id="T_9db92_row11_col2" class="data row11 col2" >16.988951</td>
      <td id="T_9db92_row11_col3" class="data row11 col3" >79.425341</td>
      <td id="T_9db92_row11_col4" class="data row11 col4" >50.890176</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row12" class="row_heading level0 row12" >12</th>
      <td id="T_9db92_row12_col0" class="data row12 col0" >c3</td>
      <td id="T_9db92_row12_col1" class="data row12 col1" >12.304493</td>
      <td id="T_9db92_row12_col2" class="data row12 col2" >19.812239</td>
      <td id="T_9db92_row12_col3" class="data row12 col3" >24.650658</td>
      <td id="T_9db92_row12_col4" class="data row12 col4" >81.638564</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row13" class="row_heading level0 row13" >13</th>
      <td id="T_9db92_row13_col0" class="data row13 col0" >c4</td>
      <td id="T_9db92_row13_col1" class="data row13 col1" >14.302122</td>
      <td id="T_9db92_row13_col2" class="data row13 col2" >18.536172</td>
      <td id="T_9db92_row13_col3" class="data row13 col3" >16.888352</td>
      <td id="T_9db92_row13_col4" class="data row13 col4" >34.058662</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row14" class="row_heading level0 row14" >14</th>
      <td id="T_9db92_row14_col0" class="data row14 col0" >c5</td>
      <td id="T_9db92_row14_col1" class="data row14 col1" >87.205052</td>
      <td id="T_9db92_row14_col2" class="data row14 col2" >20.644870</td>
      <td id="T_9db92_row14_col3" class="data row14 col3" >23.930174</td>
      <td id="T_9db92_row14_col4" class="data row14 col4" >35.630164</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row15" class="row_heading level0 row15" >15</th>
      <td id="T_9db92_row15_col0" class="data row15 col0" >d1</td>
      <td id="T_9db92_row15_col1" class="data row15 col1" >83.430267</td>
      <td id="T_9db92_row15_col2" class="data row15 col2" >57.498424</td>
      <td id="T_9db92_row15_col3" class="data row15 col3" >19.653545</td>
      <td id="T_9db92_row15_col4" class="data row15 col4" >59.792853</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row16" class="row_heading level0 row16" >16</th>
      <td id="T_9db92_row16_col0" class="data row16 col0" >d2</td>
      <td id="T_9db92_row16_col1" class="data row16 col1" >19.871437</td>
      <td id="T_9db92_row16_col2" class="data row16 col2" >24.036400</td>
      <td id="T_9db92_row16_col3" class="data row16 col3" >21.477089</td>
      <td id="T_9db92_row16_col4" class="data row16 col4" >22.930208</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row17" class="row_heading level0 row17" >17</th>
      <td id="T_9db92_row17_col0" class="data row17 col0" >d3</td>
      <td id="T_9db92_row17_col1" class="data row17 col1" >13.603607</td>
      <td id="T_9db92_row17_col2" class="data row17 col2" >82.225018</td>
      <td id="T_9db92_row17_col3" class="data row17 col3" >78.386342</td>
      <td id="T_9db92_row17_col4" class="data row17 col4" >18.953083</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row18" class="row_heading level0 row18" >18</th>
      <td id="T_9db92_row18_col0" class="data row18 col0" >d4</td>
      <td id="T_9db92_row18_col1" class="data row18 col1" >14.650788</td>
      <td id="T_9db92_row18_col2" class="data row18 col2" >80.986273</td>
      <td id="T_9db92_row18_col3" class="data row18 col3" >83.007022</td>
      <td id="T_9db92_row18_col4" class="data row18 col4" >35.577028</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row19" class="row_heading level0 row19" >19</th>
      <td id="T_9db92_row19_col0" class="data row19 col0" >d5</td>
      <td id="T_9db92_row19_col1" class="data row19 col1" >40.155084</td>
      <td id="T_9db92_row19_col2" class="data row19 col2" >22.170003</td>
      <td id="T_9db92_row19_col3" class="data row19 col3" >25.149553</td>
      <td id="T_9db92_row19_col4" class="data row19 col4" >82.663219</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row20" class="row_heading level0 row20" >20</th>
      <td id="T_9db92_row20_col0" class="data row20 col0" >e1</td>
      <td id="T_9db92_row20_col1" class="data row20 col1" >74.314233</td>
      <td id="T_9db92_row20_col2" class="data row20 col2" >18.404405</td>
      <td id="T_9db92_row20_col3" class="data row20 col3" >22.188355</td>
      <td id="T_9db92_row20_col4" class="data row20 col4" >84.178326</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row21" class="row_heading level0 row21" >21</th>
      <td id="T_9db92_row21_col0" class="data row21 col0" >e2</td>
      <td id="T_9db92_row21_col1" class="data row21 col1" >16.248647</td>
      <td id="T_9db92_row21_col2" class="data row21 col2" >79.907495</td>
      <td id="T_9db92_row21_col3" class="data row21 col3" >79.116955</td>
      <td id="T_9db92_row21_col4" class="data row21 col4" >84.137220</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row22" class="row_heading level0 row22" >22</th>
      <td id="T_9db92_row22_col0" class="data row22 col0" >e3</td>
      <td id="T_9db92_row22_col1" class="data row22 col1" >84.335387</td>
      <td id="T_9db92_row22_col2" class="data row22 col2" >23.808354</td>
      <td id="T_9db92_row22_col3" class="data row22 col3" >30.646049</td>
      <td id="T_9db92_row22_col4" class="data row22 col4" >65.512945</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row23" class="row_heading level0 row23" >23</th>
      <td id="T_9db92_row23_col0" class="data row23 col0" >e4</td>
      <td id="T_9db92_row23_col1" class="data row23 col1" >83.818774</td>
      <td id="T_9db92_row23_col2" class="data row23 col2" >24.078522</td>
      <td id="T_9db92_row23_col3" class="data row23 col3" >18.313882</td>
      <td id="T_9db92_row23_col4" class="data row23 col4" >42.574045</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row24" class="row_heading level0 row24" >24</th>
      <td id="T_9db92_row24_col0" class="data row24 col0" >e5</td>
      <td id="T_9db92_row24_col1" class="data row24 col1" >18.223823</td>
      <td id="T_9db92_row24_col2" class="data row24 col2" >25.349922</td>
      <td id="T_9db92_row24_col3" class="data row24 col3" >18.892629</td>
      <td id="T_9db92_row24_col4" class="data row24 col4" >54.098514</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row25" class="row_heading level0 row25" >25</th>
      <td id="T_9db92_row25_col0" class="data row25 col0" >f1</td>
      <td id="T_9db92_row25_col1" class="data row25 col1" >18.969413</td>
      <td id="T_9db92_row25_col2" class="data row25 col2" >18.479378</td>
      <td id="T_9db92_row25_col3" class="data row25 col3" >21.439933</td>
      <td id="T_9db92_row25_col4" class="data row25 col4" >80.975664</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row26" class="row_heading level0 row26" >26</th>
      <td id="T_9db92_row26_col0" class="data row26 col0" >f2</td>
      <td id="T_9db92_row26_col1" class="data row26 col1" >78.021850</td>
      <td id="T_9db92_row26_col2" class="data row26 col2" >16.161620</td>
      <td id="T_9db92_row26_col3" class="data row26 col3" >19.664112</td>
      <td id="T_9db92_row26_col4" class="data row26 col4" >82.165180</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row27" class="row_heading level0 row27" >27</th>
      <td id="T_9db92_row27_col0" class="data row27 col0" >f3</td>
      <td id="T_9db92_row27_col1" class="data row27 col1" >16.521411</td>
      <td id="T_9db92_row27_col2" class="data row27 col2" >78.555610</td>
      <td id="T_9db92_row27_col3" class="data row27 col3" >79.879006</td>
      <td id="T_9db92_row27_col4" class="data row27 col4" >38.448971</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row28" class="row_heading level0 row28" >28</th>
      <td id="T_9db92_row28_col0" class="data row28 col0" >f4</td>
      <td id="T_9db92_row28_col1" class="data row28 col1" >56.012427</td>
      <td id="T_9db92_row28_col2" class="data row28 col2" >72.935047</td>
      <td id="T_9db92_row28_col3" class="data row28 col3" >42.729975</td>
      <td id="T_9db92_row28_col4" class="data row28 col4" >20.558225</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row29" class="row_heading level0 row29" >29</th>
      <td id="T_9db92_row29_col0" class="data row29 col0" >f5</td>
      <td id="T_9db92_row29_col1" class="data row29 col1" >17.123146</td>
      <td id="T_9db92_row29_col2" class="data row29 col2" >18.523360</td>
      <td id="T_9db92_row29_col3" class="data row29 col3" >83.259088</td>
      <td id="T_9db92_row29_col4" class="data row29 col4" >17.461157</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row30" class="row_heading level0 row30" >30</th>
      <td id="T_9db92_row30_col0" class="data row30 col0" >g1</td>
      <td id="T_9db92_row30_col1" class="data row30 col1" >19.361459</td>
      <td id="T_9db92_row30_col2" class="data row30 col2" >76.735155</td>
      <td id="T_9db92_row30_col3" class="data row30 col3" >42.321099</td>
      <td id="T_9db92_row30_col4" class="data row30 col4" >22.709828</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row31" class="row_heading level0 row31" >31</th>
      <td id="T_9db92_row31_col0" class="data row31 col0" >g2</td>
      <td id="T_9db92_row31_col1" class="data row31 col1" >83.561105</td>
      <td id="T_9db92_row31_col2" class="data row31 col2" >78.265215</td>
      <td id="T_9db92_row31_col3" class="data row31 col3" >81.137182</td>
      <td id="T_9db92_row31_col4" class="data row31 col4" >73.773492</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row32" class="row_heading level0 row32" >32</th>
      <td id="T_9db92_row32_col0" class="data row32 col0" >g3</td>
      <td id="T_9db92_row32_col1" class="data row32 col1" >98.943857</td>
      <td id="T_9db92_row32_col2" class="data row32 col2" >18.506985</td>
      <td id="T_9db92_row32_col3" class="data row32 col3" >33.762865</td>
      <td id="T_9db92_row32_col4" class="data row32 col4" >71.800190</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row33" class="row_heading level0 row33" >33</th>
      <td id="T_9db92_row33_col0" class="data row33 col0" >g4</td>
      <td id="T_9db92_row33_col1" class="data row33 col1" >127.694486</td>
      <td id="T_9db92_row33_col2" class="data row33 col2" >24.294061</td>
      <td id="T_9db92_row33_col3" class="data row33 col3" >20.463802</td>
      <td id="T_9db92_row33_col4" class="data row33 col4" >20.252410</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row34" class="row_heading level0 row34" >34</th>
      <td id="T_9db92_row34_col0" class="data row34 col0" >g5</td>
      <td id="T_9db92_row34_col1" class="data row34 col1" >104.226220</td>
      <td id="T_9db92_row34_col2" class="data row34 col2" >79.426097</td>
      <td id="T_9db92_row34_col3" class="data row34 col3" >21.846251</td>
      <td id="T_9db92_row34_col4" class="data row34 col4" >84.670361</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row35" class="row_heading level0 row35" >35</th>
      <td id="T_9db92_row35_col0" class="data row35 col0" >h1</td>
      <td id="T_9db92_row35_col1" class="data row35 col1" >130.507872</td>
      <td id="T_9db92_row35_col2" class="data row35 col2" >79.757899</td>
      <td id="T_9db92_row35_col3" class="data row35 col3" >26.704316</td>
      <td id="T_9db92_row35_col4" class="data row35 col4" >82.534891</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row36" class="row_heading level0 row36" >36</th>
      <td id="T_9db92_row36_col0" class="data row36 col0" >h2</td>
      <td id="T_9db92_row36_col1" class="data row36 col1" >98.664309</td>
      <td id="T_9db92_row36_col2" class="data row36 col2" >37.476716</td>
      <td id="T_9db92_row36_col3" class="data row36 col3" >26.717716</td>
      <td id="T_9db92_row36_col4" class="data row36 col4" >69.176836</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row37" class="row_heading level0 row37" >37</th>
      <td id="T_9db92_row37_col0" class="data row37 col0" >h3</td>
      <td id="T_9db92_row37_col1" class="data row37 col1" >137.669736</td>
      <td id="T_9db92_row37_col2" class="data row37 col2" >79.369348</td>
      <td id="T_9db92_row37_col3" class="data row37 col3" >23.694303</td>
      <td id="T_9db92_row37_col4" class="data row37 col4" >83.234735</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row38" class="row_heading level0 row38" >38</th>
      <td id="T_9db92_row38_col0" class="data row38 col0" >h4</td>
      <td id="T_9db92_row38_col1" class="data row38 col1" >101.321112</td>
      <td id="T_9db92_row38_col2" class="data row38 col2" >88.399460</td>
      <td id="T_9db92_row38_col3" class="data row38 col3" >77.473870</td>
      <td id="T_9db92_row38_col4" class="data row38 col4" >35.095336</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row39" class="row_heading level0 row39" >39</th>
      <td id="T_9db92_row39_col0" class="data row39 col0" >h5</td>
      <td id="T_9db92_row39_col1" class="data row39 col1" >104.007671</td>
      <td id="T_9db92_row39_col2" class="data row39 col2" >57.270093</td>
      <td id="T_9db92_row39_col3" class="data row39 col3" >79.897140</td>
      <td id="T_9db92_row39_col4" class="data row39 col4" >22.740948</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row40" class="row_heading level0 row40" >40</th>
      <td id="T_9db92_row40_col0" class="data row40 col0" >i1</td>
      <td id="T_9db92_row40_col1" class="data row40 col1" >127.577284</td>
      <td id="T_9db92_row40_col2" class="data row40 col2" >91.292011</td>
      <td id="T_9db92_row40_col3" class="data row40 col3" >80.932569</td>
      <td id="T_9db92_row40_col4" class="data row40 col4" >19.667939</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row41" class="row_heading level0 row41" >41</th>
      <td id="T_9db92_row41_col0" class="data row41 col0" >i2</td>
      <td id="T_9db92_row41_col1" class="data row41 col1" >106.278686</td>
      <td id="T_9db92_row41_col2" class="data row41 col2" >70.225794</td>
      <td id="T_9db92_row41_col3" class="data row41 col3" >76.433845</td>
      <td id="T_9db92_row41_col4" class="data row41 col4" >82.139685</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row42" class="row_heading level0 row42" >42</th>
      <td id="T_9db92_row42_col0" class="data row42 col0" >i3</td>
      <td id="T_9db92_row42_col1" class="data row42 col1" >101.747360</td>
      <td id="T_9db92_row42_col2" class="data row42 col2" >62.654754</td>
      <td id="T_9db92_row42_col3" class="data row42 col3" >78.075309</td>
      <td id="T_9db92_row42_col4" class="data row42 col4" >84.682646</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row43" class="row_heading level0 row43" >43</th>
      <td id="T_9db92_row43_col0" class="data row43 col0" >i4</td>
      <td id="T_9db92_row43_col1" class="data row43 col1" >130.361933</td>
      <td id="T_9db92_row43_col2" class="data row43 col2" >75.292917</td>
      <td id="T_9db92_row43_col3" class="data row43 col3" >82.724512</td>
      <td id="T_9db92_row43_col4" class="data row43 col4" >19.903843</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row44" class="row_heading level0 row44" >44</th>
      <td id="T_9db92_row44_col0" class="data row44 col0" >i5</td>
      <td id="T_9db92_row44_col1" class="data row44 col1" >125.034424</td>
      <td id="T_9db92_row44_col2" class="data row44 col2" >78.167728</td>
      <td id="T_9db92_row44_col3" class="data row44 col3" >80.088464</td>
      <td id="T_9db92_row44_col4" class="data row44 col4" >68.709482</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row45" class="row_heading level0 row45" >45</th>
      <td id="T_9db92_row45_col0" class="data row45 col0" >j1</td>
      <td id="T_9db92_row45_col1" class="data row45 col1" >109.374159</td>
      <td id="T_9db92_row45_col2" class="data row45 col2" >79.784803</td>
      <td id="T_9db92_row45_col3" class="data row45 col3" >77.763431</td>
      <td id="T_9db92_row45_col4" class="data row45 col4" >82.784139</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row46" class="row_heading level0 row46" >46</th>
      <td id="T_9db92_row46_col0" class="data row46 col0" >j2</td>
      <td id="T_9db92_row46_col1" class="data row46 col1" >130.202472</td>
      <td id="T_9db92_row46_col2" class="data row46 col2" >65.524540</td>
      <td id="T_9db92_row46_col3" class="data row46 col3" >79.562965</td>
      <td id="T_9db92_row46_col4" class="data row46 col4" >76.739871</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row47" class="row_heading level0 row47" >47</th>
      <td id="T_9db92_row47_col0" class="data row47 col0" >j3</td>
      <td id="T_9db92_row47_col1" class="data row47 col1" >106.458561</td>
      <td id="T_9db92_row47_col2" class="data row47 col2" >78.996063</td>
      <td id="T_9db92_row47_col3" class="data row47 col3" >80.719352</td>
      <td id="T_9db92_row47_col4" class="data row47 col4" >21.593767</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row48" class="row_heading level0 row48" >48</th>
      <td id="T_9db92_row48_col0" class="data row48 col0" >j4</td>
      <td id="T_9db92_row48_col1" class="data row48 col1" >162.079734</td>
      <td id="T_9db92_row48_col2" class="data row48 col2" >62.459498</td>
      <td id="T_9db92_row48_col3" class="data row48 col3" >24.492515</td>
      <td id="T_9db92_row48_col4" class="data row48 col4" >86.788914</td>
    </tr>
    <tr>
      <th id="T_9db92_level0_row49" class="row_heading level0 row49" >49</th>
      <td id="T_9db92_row49_col0" class="data row49 col0" >j5</td>
      <td id="T_9db92_row49_col1" class="data row49 col1" >130.081632</td>
      <td id="T_9db92_row49_col2" class="data row49 col2" >65.139597</td>
      <td id="T_9db92_row49_col3" class="data row49 col3" >20.263875</td>
      <td id="T_9db92_row49_col4" class="data row49 col4" >19.679278</td>
    </tr>
  </tbody>
</table>




____
**FIO sync lattency Standard Deviation in ms (sync_lat_max_ms)**

Summary of results:
- gp2: similar/expected deviation when throttling for both disk layouts


```python
aggregate_metric('sync_lat_stddev_ms').rename(columns={"b2_t1": "gp2x1","b2_t2": "gp2x2","b2_t3": "gp3x1","b2_t4": "gp3x2"}).\
    style.applymap(_df_style_high, subset=["gp2x1", "gp2x2", "gp3x1", "gp3x2"], value_red=1.0)
```




<style type="text/css">
#T_337f3_row1_col4, #T_337f3_row25_col4, #T_337f3_row32_col1, #T_337f3_row33_col1, #T_337f3_row34_col1, #T_337f3_row35_col1, #T_337f3_row36_col1, #T_337f3_row37_col1, #T_337f3_row37_col2, #T_337f3_row38_col1, #T_337f3_row38_col2, #T_337f3_row39_col1, #T_337f3_row39_col2, #T_337f3_row40_col1, #T_337f3_row40_col2, #T_337f3_row41_col1, #T_337f3_row41_col2, #T_337f3_row42_col1, #T_337f3_row42_col2, #T_337f3_row43_col1, #T_337f3_row43_col2, #T_337f3_row44_col1, #T_337f3_row44_col2, #T_337f3_row45_col1, #T_337f3_row45_col2, #T_337f3_row46_col1, #T_337f3_row46_col2, #T_337f3_row47_col1, #T_337f3_row47_col2, #T_337f3_row47_col3, #T_337f3_row48_col1, #T_337f3_row48_col2, #T_337f3_row49_col1, #T_337f3_row49_col2 {
  background-color: red;
}
</style>
<table id="T_337f3_">
  <thead>
    <tr>
      <th class="blank level0" >&nbsp;</th>
      <th class="col_heading level0 col0" >job_Id</th>
      <th class="col_heading level0 col1" >gp2x1</th>
      <th class="col_heading level0 col2" >gp2x2</th>
      <th class="col_heading level0 col3" >gp3x1</th>
      <th class="col_heading level0 col4" >gp3x2</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th id="T_337f3_level0_row0" class="row_heading level0 row0" >0</th>
      <td id="T_337f3_row0_col0" class="data row0 col0" >a1</td>
      <td id="T_337f3_row0_col1" class="data row0 col1" >0.430956</td>
      <td id="T_337f3_row0_col2" class="data row0 col2" >0.703880</td>
      <td id="T_337f3_row0_col3" class="data row0 col3" >0.772607</td>
      <td id="T_337f3_row0_col4" class="data row0 col4" >0.959877</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row1" class="row_heading level0 row1" >1</th>
      <td id="T_337f3_row1_col0" class="data row1 col0" >a2</td>
      <td id="T_337f3_row1_col1" class="data row1 col1" >0.582749</td>
      <td id="T_337f3_row1_col2" class="data row1 col2" >0.723067</td>
      <td id="T_337f3_row1_col3" class="data row1 col3" >0.841022</td>
      <td id="T_337f3_row1_col4" class="data row1 col4" >1.073758</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row2" class="row_heading level0 row2" >2</th>
      <td id="T_337f3_row2_col0" class="data row2 col0" >a3</td>
      <td id="T_337f3_row2_col1" class="data row2 col1" >0.529805</td>
      <td id="T_337f3_row2_col2" class="data row2 col2" >0.688169</td>
      <td id="T_337f3_row2_col3" class="data row2 col3" >0.836908</td>
      <td id="T_337f3_row2_col4" class="data row2 col4" >0.860998</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row3" class="row_heading level0 row3" >3</th>
      <td id="T_337f3_row3_col0" class="data row3 col0" >a4</td>
      <td id="T_337f3_row3_col1" class="data row3 col1" >0.537326</td>
      <td id="T_337f3_row3_col2" class="data row3 col2" >0.707594</td>
      <td id="T_337f3_row3_col3" class="data row3 col3" >0.819819</td>
      <td id="T_337f3_row3_col4" class="data row3 col4" >0.842392</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row4" class="row_heading level0 row4" >4</th>
      <td id="T_337f3_row4_col0" class="data row4 col0" >a5</td>
      <td id="T_337f3_row4_col1" class="data row4 col1" >0.586911</td>
      <td id="T_337f3_row4_col2" class="data row4 col2" >0.754138</td>
      <td id="T_337f3_row4_col3" class="data row4 col3" >0.871086</td>
      <td id="T_337f3_row4_col4" class="data row4 col4" >0.917508</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row5" class="row_heading level0 row5" >5</th>
      <td id="T_337f3_row5_col0" class="data row5 col0" >b1</td>
      <td id="T_337f3_row5_col1" class="data row5 col1" >0.545497</td>
      <td id="T_337f3_row5_col2" class="data row5 col2" >0.687214</td>
      <td id="T_337f3_row5_col3" class="data row5 col3" >0.853895</td>
      <td id="T_337f3_row5_col4" class="data row5 col4" >0.985698</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row6" class="row_heading level0 row6" >6</th>
      <td id="T_337f3_row6_col0" class="data row6 col0" >b2</td>
      <td id="T_337f3_row6_col1" class="data row6 col1" >0.615213</td>
      <td id="T_337f3_row6_col2" class="data row6 col2" >0.751622</td>
      <td id="T_337f3_row6_col3" class="data row6 col3" >0.952194</td>
      <td id="T_337f3_row6_col4" class="data row6 col4" >0.877783</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row7" class="row_heading level0 row7" >7</th>
      <td id="T_337f3_row7_col0" class="data row7 col0" >b3</td>
      <td id="T_337f3_row7_col1" class="data row7 col1" >0.599280</td>
      <td id="T_337f3_row7_col2" class="data row7 col2" >0.730728</td>
      <td id="T_337f3_row7_col3" class="data row7 col3" >0.914686</td>
      <td id="T_337f3_row7_col4" class="data row7 col4" >0.821403</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row8" class="row_heading level0 row8" >8</th>
      <td id="T_337f3_row8_col0" class="data row8 col0" >b4</td>
      <td id="T_337f3_row8_col1" class="data row8 col1" >0.621720</td>
      <td id="T_337f3_row8_col2" class="data row8 col2" >0.679319</td>
      <td id="T_337f3_row8_col3" class="data row8 col3" >0.917649</td>
      <td id="T_337f3_row8_col4" class="data row8 col4" >0.850724</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row9" class="row_heading level0 row9" >9</th>
      <td id="T_337f3_row9_col0" class="data row9 col0" >b5</td>
      <td id="T_337f3_row9_col1" class="data row9 col1" >0.612393</td>
      <td id="T_337f3_row9_col2" class="data row9 col2" >0.751204</td>
      <td id="T_337f3_row9_col3" class="data row9 col3" >0.844867</td>
      <td id="T_337f3_row9_col4" class="data row9 col4" >0.880190</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row10" class="row_heading level0 row10" >10</th>
      <td id="T_337f3_row10_col0" class="data row10 col0" >c1</td>
      <td id="T_337f3_row10_col1" class="data row10 col1" >0.620716</td>
      <td id="T_337f3_row10_col2" class="data row10 col2" >0.674037</td>
      <td id="T_337f3_row10_col3" class="data row10 col3" >0.844636</td>
      <td id="T_337f3_row10_col4" class="data row10 col4" >0.907226</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row11" class="row_heading level0 row11" >11</th>
      <td id="T_337f3_row11_col0" class="data row11 col0" >c2</td>
      <td id="T_337f3_row11_col1" class="data row11 col1" >0.663657</td>
      <td id="T_337f3_row11_col2" class="data row11 col2" >0.682124</td>
      <td id="T_337f3_row11_col3" class="data row11 col3" >0.803912</td>
      <td id="T_337f3_row11_col4" class="data row11 col4" >0.757315</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row12" class="row_heading level0 row12" >12</th>
      <td id="T_337f3_row12_col0" class="data row12 col0" >c3</td>
      <td id="T_337f3_row12_col1" class="data row12 col1" >0.602402</td>
      <td id="T_337f3_row12_col2" class="data row12 col2" >0.687454</td>
      <td id="T_337f3_row12_col3" class="data row12 col3" >0.790597</td>
      <td id="T_337f3_row12_col4" class="data row12 col4" >0.865012</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row13" class="row_heading level0 row13" >13</th>
      <td id="T_337f3_row13_col0" class="data row13 col0" >c4</td>
      <td id="T_337f3_row13_col1" class="data row13 col1" >0.562018</td>
      <td id="T_337f3_row13_col2" class="data row13 col2" >0.701443</td>
      <td id="T_337f3_row13_col3" class="data row13 col3" >0.762405</td>
      <td id="T_337f3_row13_col4" class="data row13 col4" >0.840935</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row14" class="row_heading level0 row14" >14</th>
      <td id="T_337f3_row14_col0" class="data row14 col0" >c5</td>
      <td id="T_337f3_row14_col1" class="data row14 col1" >0.633961</td>
      <td id="T_337f3_row14_col2" class="data row14 col2" >0.704009</td>
      <td id="T_337f3_row14_col3" class="data row14 col3" >0.786703</td>
      <td id="T_337f3_row14_col4" class="data row14 col4" >0.794594</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row15" class="row_heading level0 row15" >15</th>
      <td id="T_337f3_row15_col0" class="data row15 col0" >d1</td>
      <td id="T_337f3_row15_col1" class="data row15 col1" >0.616942</td>
      <td id="T_337f3_row15_col2" class="data row15 col2" >0.744269</td>
      <td id="T_337f3_row15_col3" class="data row15 col3" >0.843539</td>
      <td id="T_337f3_row15_col4" class="data row15 col4" >0.838632</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row16" class="row_heading level0 row16" >16</th>
      <td id="T_337f3_row16_col0" class="data row16 col0" >d2</td>
      <td id="T_337f3_row16_col1" class="data row16 col1" >0.549715</td>
      <td id="T_337f3_row16_col2" class="data row16 col2" >0.694338</td>
      <td id="T_337f3_row16_col3" class="data row16 col3" >0.787897</td>
      <td id="T_337f3_row16_col4" class="data row16 col4" >0.768104</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row17" class="row_heading level0 row17" >17</th>
      <td id="T_337f3_row17_col0" class="data row17 col0" >d3</td>
      <td id="T_337f3_row17_col1" class="data row17 col1" >0.538930</td>
      <td id="T_337f3_row17_col2" class="data row17 col2" >0.750067</td>
      <td id="T_337f3_row17_col3" class="data row17 col3" >0.823499</td>
      <td id="T_337f3_row17_col4" class="data row17 col4" >0.846683</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row18" class="row_heading level0 row18" >18</th>
      <td id="T_337f3_row18_col0" class="data row18 col0" >d4</td>
      <td id="T_337f3_row18_col1" class="data row18 col1" >0.554933</td>
      <td id="T_337f3_row18_col2" class="data row18 col2" >0.753507</td>
      <td id="T_337f3_row18_col3" class="data row18 col3" >0.861799</td>
      <td id="T_337f3_row18_col4" class="data row18 col4" >0.880741</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row19" class="row_heading level0 row19" >19</th>
      <td id="T_337f3_row19_col0" class="data row19 col0" >d5</td>
      <td id="T_337f3_row19_col1" class="data row19 col1" >0.598044</td>
      <td id="T_337f3_row19_col2" class="data row19 col2" >0.704970</td>
      <td id="T_337f3_row19_col3" class="data row19 col3" >0.775678</td>
      <td id="T_337f3_row19_col4" class="data row19 col4" >0.859680</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row20" class="row_heading level0 row20" >20</th>
      <td id="T_337f3_row20_col0" class="data row20 col0" >e1</td>
      <td id="T_337f3_row20_col1" class="data row20 col1" >0.646730</td>
      <td id="T_337f3_row20_col2" class="data row20 col2" >0.680368</td>
      <td id="T_337f3_row20_col3" class="data row20 col3" >0.756247</td>
      <td id="T_337f3_row20_col4" class="data row20 col4" >0.827707</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row21" class="row_heading level0 row21" >21</th>
      <td id="T_337f3_row21_col0" class="data row21 col0" >e2</td>
      <td id="T_337f3_row21_col1" class="data row21 col1" >0.624049</td>
      <td id="T_337f3_row21_col2" class="data row21 col2" >0.742640</td>
      <td id="T_337f3_row21_col3" class="data row21 col3" >0.808597</td>
      <td id="T_337f3_row21_col4" class="data row21 col4" >0.826806</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row22" class="row_heading level0 row22" >22</th>
      <td id="T_337f3_row22_col0" class="data row22 col0" >e3</td>
      <td id="T_337f3_row22_col1" class="data row22 col1" >0.626943</td>
      <td id="T_337f3_row22_col2" class="data row22 col2" >0.714605</td>
      <td id="T_337f3_row22_col3" class="data row22 col3" >0.768980</td>
      <td id="T_337f3_row22_col4" class="data row22 col4" >0.796826</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row23" class="row_heading level0 row23" >23</th>
      <td id="T_337f3_row23_col0" class="data row23 col0" >e4</td>
      <td id="T_337f3_row23_col1" class="data row23 col1" >0.606692</td>
      <td id="T_337f3_row23_col2" class="data row23 col2" >0.686635</td>
      <td id="T_337f3_row23_col3" class="data row23 col3" >0.767243</td>
      <td id="T_337f3_row23_col4" class="data row23 col4" >0.903739</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row24" class="row_heading level0 row24" >24</th>
      <td id="T_337f3_row24_col0" class="data row24 col0" >e5</td>
      <td id="T_337f3_row24_col1" class="data row24 col1" >0.556802</td>
      <td id="T_337f3_row24_col2" class="data row24 col2" >0.709999</td>
      <td id="T_337f3_row24_col3" class="data row24 col3" >0.809127</td>
      <td id="T_337f3_row24_col4" class="data row24 col4" >0.841158</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row25" class="row_heading level0 row25" >25</th>
      <td id="T_337f3_row25_col0" class="data row25 col0" >f1</td>
      <td id="T_337f3_row25_col1" class="data row25 col1" >0.541922</td>
      <td id="T_337f3_row25_col2" class="data row25 col2" >0.670444</td>
      <td id="T_337f3_row25_col3" class="data row25 col3" >0.866086</td>
      <td id="T_337f3_row25_col4" class="data row25 col4" >1.012981</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row26" class="row_heading level0 row26" >26</th>
      <td id="T_337f3_row26_col0" class="data row26 col0" >f2</td>
      <td id="T_337f3_row26_col1" class="data row26 col1" >0.620040</td>
      <td id="T_337f3_row26_col2" class="data row26 col2" >0.638763</td>
      <td id="T_337f3_row26_col3" class="data row26 col3" >0.824882</td>
      <td id="T_337f3_row26_col4" class="data row26 col4" >0.998473</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row27" class="row_heading level0 row27" >27</th>
      <td id="T_337f3_row27_col0" class="data row27 col0" >f3</td>
      <td id="T_337f3_row27_col1" class="data row27 col1" >0.568856</td>
      <td id="T_337f3_row27_col2" class="data row27 col2" >0.730971</td>
      <td id="T_337f3_row27_col3" class="data row27 col3" >0.854483</td>
      <td id="T_337f3_row27_col4" class="data row27 col4" >0.830153</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row28" class="row_heading level0 row28" >28</th>
      <td id="T_337f3_row28_col0" class="data row28 col0" >f4</td>
      <td id="T_337f3_row28_col1" class="data row28 col1" >0.589814</td>
      <td id="T_337f3_row28_col2" class="data row28 col2" >0.787872</td>
      <td id="T_337f3_row28_col3" class="data row28 col3" >0.799137</td>
      <td id="T_337f3_row28_col4" class="data row28 col4" >0.839331</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row29" class="row_heading level0 row29" >29</th>
      <td id="T_337f3_row29_col0" class="data row29 col0" >f5</td>
      <td id="T_337f3_row29_col1" class="data row29 col1" >0.551999</td>
      <td id="T_337f3_row29_col2" class="data row29 col2" >0.661377</td>
      <td id="T_337f3_row29_col3" class="data row29 col3" >0.898885</td>
      <td id="T_337f3_row29_col4" class="data row29 col4" >0.815392</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row30" class="row_heading level0 row30" >30</th>
      <td id="T_337f3_row30_col0" class="data row30 col0" >g1</td>
      <td id="T_337f3_row30_col1" class="data row30 col1" >0.589222</td>
      <td id="T_337f3_row30_col2" class="data row30 col2" >0.725293</td>
      <td id="T_337f3_row30_col3" class="data row30 col3" >0.883888</td>
      <td id="T_337f3_row30_col4" class="data row30 col4" >0.814237</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row31" class="row_heading level0 row31" >31</th>
      <td id="T_337f3_row31_col0" class="data row31 col0" >g2</td>
      <td id="T_337f3_row31_col1" class="data row31 col1" >0.650944</td>
      <td id="T_337f3_row31_col2" class="data row31 col2" >0.734398</td>
      <td id="T_337f3_row31_col3" class="data row31 col3" >0.877024</td>
      <td id="T_337f3_row31_col4" class="data row31 col4" >0.820261</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row32" class="row_heading level0 row32" >32</th>
      <td id="T_337f3_row32_col0" class="data row32 col0" >g3</td>
      <td id="T_337f3_row32_col1" class="data row32 col1" >3.825136</td>
      <td id="T_337f3_row32_col2" class="data row32 col2" >0.660164</td>
      <td id="T_337f3_row32_col3" class="data row32 col3" >0.854193</td>
      <td id="T_337f3_row32_col4" class="data row32 col4" >0.814386</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row33" class="row_heading level0 row33" >33</th>
      <td id="T_337f3_row33_col0" class="data row33 col0" >g4</td>
      <td id="T_337f3_row33_col1" class="data row33 col1" >3.863416</td>
      <td id="T_337f3_row33_col2" class="data row33 col2" >0.693937</td>
      <td id="T_337f3_row33_col3" class="data row33 col3" >0.824036</td>
      <td id="T_337f3_row33_col4" class="data row33 col4" >0.779804</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row34" class="row_heading level0 row34" >34</th>
      <td id="T_337f3_row34_col0" class="data row34 col0" >g5</td>
      <td id="T_337f3_row34_col1" class="data row34 col1" >3.925166</td>
      <td id="T_337f3_row34_col2" class="data row34 col2" >0.750579</td>
      <td id="T_337f3_row34_col3" class="data row34 col3" >0.829251</td>
      <td id="T_337f3_row34_col4" class="data row34 col4" >0.888350</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row35" class="row_heading level0 row35" >35</th>
      <td id="T_337f3_row35_col0" class="data row35 col0" >h1</td>
      <td id="T_337f3_row35_col1" class="data row35 col1" >3.906435</td>
      <td id="T_337f3_row35_col2" class="data row35 col2" >0.741914</td>
      <td id="T_337f3_row35_col3" class="data row35 col3" >0.890803</td>
      <td id="T_337f3_row35_col4" class="data row35 col4" >0.915968</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row36" class="row_heading level0 row36" >36</th>
      <td id="T_337f3_row36_col0" class="data row36 col0" >h2</td>
      <td id="T_337f3_row36_col1" class="data row36 col1" >3.876710</td>
      <td id="T_337f3_row36_col2" class="data row36 col2" >0.725465</td>
      <td id="T_337f3_row36_col3" class="data row36 col3" >0.805530</td>
      <td id="T_337f3_row36_col4" class="data row36 col4" >0.905877</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row37" class="row_heading level0 row37" >37</th>
      <td id="T_337f3_row37_col0" class="data row37 col0" >h3</td>
      <td id="T_337f3_row37_col1" class="data row37 col1" >3.816676</td>
      <td id="T_337f3_row37_col2" class="data row37 col2" >3.389939</td>
      <td id="T_337f3_row37_col3" class="data row37 col3" >0.813346</td>
      <td id="T_337f3_row37_col4" class="data row37 col4" >0.969917</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row38" class="row_heading level0 row38" >38</th>
      <td id="T_337f3_row38_col0" class="data row38 col0" >h4</td>
      <td id="T_337f3_row38_col1" class="data row38 col1" >3.804448</td>
      <td id="T_337f3_row38_col2" class="data row38 col2" >3.408925</td>
      <td id="T_337f3_row38_col3" class="data row38 col3" >0.825446</td>
      <td id="T_337f3_row38_col4" class="data row38 col4" >0.937789</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row39" class="row_heading level0 row39" >39</th>
      <td id="T_337f3_row39_col0" class="data row39 col0" >h5</td>
      <td id="T_337f3_row39_col1" class="data row39 col1" >3.839013</td>
      <td id="T_337f3_row39_col2" class="data row39 col2" >3.453397</td>
      <td id="T_337f3_row39_col3" class="data row39 col3" >0.856980</td>
      <td id="T_337f3_row39_col4" class="data row39 col4" >0.838676</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row40" class="row_heading level0 row40" >40</th>
      <td id="T_337f3_row40_col0" class="data row40 col0" >i1</td>
      <td id="T_337f3_row40_col1" class="data row40 col1" >3.836431</td>
      <td id="T_337f3_row40_col2" class="data row40 col2" >3.465687</td>
      <td id="T_337f3_row40_col3" class="data row40 col3" >0.917261</td>
      <td id="T_337f3_row40_col4" class="data row40 col4" >0.893797</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row41" class="row_heading level0 row41" >41</th>
      <td id="T_337f3_row41_col0" class="data row41 col0" >i2</td>
      <td id="T_337f3_row41_col1" class="data row41 col1" >3.845477</td>
      <td id="T_337f3_row41_col2" class="data row41 col2" >3.476876</td>
      <td id="T_337f3_row41_col3" class="data row41 col3" >0.862999</td>
      <td id="T_337f3_row41_col4" class="data row41 col4" >0.945605</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row42" class="row_heading level0 row42" >42</th>
      <td id="T_337f3_row42_col0" class="data row42 col0" >i3</td>
      <td id="T_337f3_row42_col1" class="data row42 col1" >3.819285</td>
      <td id="T_337f3_row42_col2" class="data row42 col2" >3.440871</td>
      <td id="T_337f3_row42_col3" class="data row42 col3" >0.949621</td>
      <td id="T_337f3_row42_col4" class="data row42 col4" >0.936211</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row43" class="row_heading level0 row43" >43</th>
      <td id="T_337f3_row43_col0" class="data row43 col0" >i4</td>
      <td id="T_337f3_row43_col1" class="data row43 col1" >3.912056</td>
      <td id="T_337f3_row43_col2" class="data row43 col2" >3.462567</td>
      <td id="T_337f3_row43_col3" class="data row43 col3" >0.988854</td>
      <td id="T_337f3_row43_col4" class="data row43 col4" >0.820174</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row44" class="row_heading level0 row44" >44</th>
      <td id="T_337f3_row44_col0" class="data row44 col0" >i5</td>
      <td id="T_337f3_row44_col1" class="data row44 col1" >3.892198</td>
      <td id="T_337f3_row44_col2" class="data row44 col2" >3.483655</td>
      <td id="T_337f3_row44_col3" class="data row44 col3" >0.889230</td>
      <td id="T_337f3_row44_col4" class="data row44 col4" >0.891130</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row45" class="row_heading level0 row45" >45</th>
      <td id="T_337f3_row45_col0" class="data row45 col0" >j1</td>
      <td id="T_337f3_row45_col1" class="data row45 col1" >3.862755</td>
      <td id="T_337f3_row45_col2" class="data row45 col2" >3.480325</td>
      <td id="T_337f3_row45_col3" class="data row45 col3" >0.794586</td>
      <td id="T_337f3_row45_col4" class="data row45 col4" >0.906569</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row46" class="row_heading level0 row46" >46</th>
      <td id="T_337f3_row46_col0" class="data row46 col0" >j2</td>
      <td id="T_337f3_row46_col1" class="data row46 col1" >3.870202</td>
      <td id="T_337f3_row46_col2" class="data row46 col2" >3.483793</td>
      <td id="T_337f3_row46_col3" class="data row46 col3" >0.910338</td>
      <td id="T_337f3_row46_col4" class="data row46 col4" >0.831806</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row47" class="row_heading level0 row47" >47</th>
      <td id="T_337f3_row47_col0" class="data row47 col0" >j3</td>
      <td id="T_337f3_row47_col1" class="data row47 col1" >3.899451</td>
      <td id="T_337f3_row47_col2" class="data row47 col2" >3.453708</td>
      <td id="T_337f3_row47_col3" class="data row47 col3" >1.010509</td>
      <td id="T_337f3_row47_col4" class="data row47 col4" >0.897712</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row48" class="row_heading level0 row48" >48</th>
      <td id="T_337f3_row48_col0" class="data row48 col0" >j4</td>
      <td id="T_337f3_row48_col1" class="data row48 col1" >3.918237</td>
      <td id="T_337f3_row48_col2" class="data row48 col2" >3.418863</td>
      <td id="T_337f3_row48_col3" class="data row48 col3" >0.820270</td>
      <td id="T_337f3_row48_col4" class="data row48 col4" >0.936373</td>
    </tr>
    <tr>
      <th id="T_337f3_level0_row49" class="row_heading level0 row49" >49</th>
      <td id="T_337f3_row49_col0" class="data row49 col0" >j5</td>
      <td id="T_337f3_row49_col1" class="data row49 col1" >3.965393</td>
      <td id="T_337f3_row49_col2" class="data row49 col2" >3.427648</td>
      <td id="T_337f3_row49_col3" class="data row49 col3" >0.783822</td>
      <td id="T_337f3_row49_col4" class="data row49 col4" >0.792559</td>
    </tr>
  </tbody>
</table>




____
**FIO sync lattency - all metrics by node - in ms (sync_lat_max_ms)**

Summary of results: []


```python
node_metrics = aggregate_by_node()
for node in list(node_metrics.keys()):
    print(f"#> {node} [{node_metrics[node][0]['battery_id']}]")
    display(pd.read_json(json.dumps(node_metrics[node])))
```

    #> ip-10-0-137-218.ec2.internal [b2_t1]



<div>
<style scoped>
    .dataframe tbody tr th:only-of-type {
        vertical-align: middle;
    }

    .dataframe tbody tr th {
        vertical-align: top;
    }

    .dataframe thead th {
        text-align: right;
    }
</style>
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th>battery_id</th>
      <th>job_Id</th>
      <th>sync_lat_max_ms</th>
      <th>sync_lat_mean_ms</th>
      <th>sync_lat_stddev_ms</th>
      <th>sync_lat_p99_ms</th>
      <th>sync_lat_p99.9_ms</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>0</th>
      <td>b2_t1</td>
      <td>a1</td>
      <td>21.362522</td>
      <td>0.789064</td>
      <td>0.430956</td>
      <td>1.925120</td>
      <td>4.751360</td>
    </tr>
    <tr>
      <th>1</th>
      <td>b2_t1</td>
      <td>a2</td>
      <td>70.671594</td>
      <td>1.056788</td>
      <td>0.582749</td>
      <td>2.277376</td>
      <td>6.782976</td>
    </tr>
    <tr>
      <th>2</th>
      <td>b2_t1</td>
      <td>a3</td>
      <td>14.560474</td>
      <td>1.070381</td>
      <td>0.529805</td>
      <td>2.244608</td>
      <td>6.586368</td>
    </tr>
    <tr>
      <th>3</th>
      <td>b2_t1</td>
      <td>a4</td>
      <td>23.222146</td>
      <td>1.068620</td>
      <td>0.537326</td>
      <td>2.375680</td>
      <td>6.324224</td>
    </tr>
    <tr>
      <th>4</th>
      <td>b2_t1</td>
      <td>a5</td>
      <td>76.327184</td>
      <td>1.069686</td>
      <td>0.586911</td>
      <td>2.342912</td>
      <td>6.520832</td>
    </tr>
    <tr>
      <th>5</th>
      <td>b2_t1</td>
      <td>b1</td>
      <td>16.081376</td>
      <td>1.075730</td>
      <td>0.545497</td>
      <td>2.375680</td>
      <td>6.782976</td>
    </tr>
    <tr>
      <th>6</th>
      <td>b2_t1</td>
      <td>b2</td>
      <td>78.391998</td>
      <td>1.065582</td>
      <td>0.615213</td>
      <td>2.375680</td>
      <td>6.455296</td>
    </tr>
    <tr>
      <th>7</th>
      <td>b2_t1</td>
      <td>b3</td>
      <td>87.659569</td>
      <td>1.041871</td>
      <td>0.599280</td>
      <td>2.211840</td>
      <td>6.586368</td>
    </tr>
    <tr>
      <th>8</th>
      <td>b2_t1</td>
      <td>b4</td>
      <td>75.570967</td>
      <td>1.060716</td>
      <td>0.621720</td>
      <td>2.244608</td>
      <td>6.651904</td>
    </tr>
    <tr>
      <th>9</th>
      <td>b2_t1</td>
      <td>b5</td>
      <td>90.578402</td>
      <td>1.053578</td>
      <td>0.612393</td>
      <td>2.342912</td>
      <td>6.651904</td>
    </tr>
    <tr>
      <th>10</th>
      <td>b2_t1</td>
      <td>c1</td>
      <td>73.352157</td>
      <td>1.070039</td>
      <td>0.620716</td>
      <td>2.342912</td>
      <td>6.848512</td>
    </tr>
    <tr>
      <th>11</th>
      <td>b2_t1</td>
      <td>c2</td>
      <td>85.045124</td>
      <td>1.160528</td>
      <td>0.663657</td>
      <td>2.637824</td>
      <td>7.438336</td>
    </tr>
    <tr>
      <th>12</th>
      <td>b2_t1</td>
      <td>c3</td>
      <td>12.304493</td>
      <td>1.193205</td>
      <td>0.602402</td>
      <td>2.801664</td>
      <td>6.914048</td>
    </tr>
    <tr>
      <th>13</th>
      <td>b2_t1</td>
      <td>c4</td>
      <td>14.302122</td>
      <td>1.106304</td>
      <td>0.562018</td>
      <td>2.441216</td>
      <td>7.110656</td>
    </tr>
    <tr>
      <th>14</th>
      <td>b2_t1</td>
      <td>c5</td>
      <td>87.205052</td>
      <td>1.114071</td>
      <td>0.633961</td>
      <td>2.441216</td>
      <td>7.045120</td>
    </tr>
    <tr>
      <th>15</th>
      <td>b2_t1</td>
      <td>d1</td>
      <td>83.430267</td>
      <td>1.094274</td>
      <td>0.616942</td>
      <td>2.375680</td>
      <td>7.110656</td>
    </tr>
    <tr>
      <th>16</th>
      <td>b2_t1</td>
      <td>d2</td>
      <td>19.871437</td>
      <td>1.085720</td>
      <td>0.549715</td>
      <td>2.310144</td>
      <td>6.914048</td>
    </tr>
    <tr>
      <th>17</th>
      <td>b2_t1</td>
      <td>d3</td>
      <td>13.603607</td>
      <td>1.073432</td>
      <td>0.538930</td>
      <td>2.310144</td>
      <td>6.717440</td>
    </tr>
    <tr>
      <th>18</th>
      <td>b2_t1</td>
      <td>d4</td>
      <td>14.650788</td>
      <td>1.107403</td>
      <td>0.554933</td>
      <td>2.441216</td>
      <td>6.717440</td>
    </tr>
    <tr>
      <th>19</th>
      <td>b2_t1</td>
      <td>d5</td>
      <td>40.155084</td>
      <td>1.132898</td>
      <td>0.598044</td>
      <td>2.572288</td>
      <td>6.979584</td>
    </tr>
    <tr>
      <th>20</th>
      <td>b2_t1</td>
      <td>e1</td>
      <td>74.314233</td>
      <td>1.161496</td>
      <td>0.646730</td>
      <td>2.637824</td>
      <td>7.372800</td>
    </tr>
    <tr>
      <th>21</th>
      <td>b2_t1</td>
      <td>e2</td>
      <td>16.248647</td>
      <td>1.196111</td>
      <td>0.624049</td>
      <td>2.834432</td>
      <td>7.634944</td>
    </tr>
    <tr>
      <th>22</th>
      <td>b2_t1</td>
      <td>e3</td>
      <td>84.335387</td>
      <td>1.110110</td>
      <td>0.626943</td>
      <td>2.441216</td>
      <td>6.782976</td>
    </tr>
    <tr>
      <th>23</th>
      <td>b2_t1</td>
      <td>e4</td>
      <td>83.818774</td>
      <td>1.082656</td>
      <td>0.606692</td>
      <td>2.441216</td>
      <td>6.455296</td>
    </tr>
    <tr>
      <th>24</th>
      <td>b2_t1</td>
      <td>e5</td>
      <td>18.223823</td>
      <td>1.081432</td>
      <td>0.556802</td>
      <td>2.342912</td>
      <td>7.045120</td>
    </tr>
    <tr>
      <th>25</th>
      <td>b2_t1</td>
      <td>f1</td>
      <td>18.969413</td>
      <td>1.073290</td>
      <td>0.541922</td>
      <td>2.342912</td>
      <td>6.586368</td>
    </tr>
    <tr>
      <th>26</th>
      <td>b2_t1</td>
      <td>f2</td>
      <td>78.021850</td>
      <td>1.101784</td>
      <td>0.620040</td>
      <td>2.441216</td>
      <td>6.586368</td>
    </tr>
    <tr>
      <th>27</th>
      <td>b2_t1</td>
      <td>f3</td>
      <td>16.521411</td>
      <td>1.126240</td>
      <td>0.568856</td>
      <td>2.506752</td>
      <td>6.717440</td>
    </tr>
    <tr>
      <th>28</th>
      <td>b2_t1</td>
      <td>f4</td>
      <td>56.012427</td>
      <td>1.113870</td>
      <td>0.589814</td>
      <td>2.473984</td>
      <td>6.717440</td>
    </tr>
    <tr>
      <th>29</th>
      <td>b2_t1</td>
      <td>f5</td>
      <td>17.123146</td>
      <td>1.086203</td>
      <td>0.551999</td>
      <td>2.310144</td>
      <td>6.848512</td>
    </tr>
    <tr>
      <th>30</th>
      <td>b2_t1</td>
      <td>g1</td>
      <td>19.361459</td>
      <td>1.157267</td>
      <td>0.589222</td>
      <td>2.605056</td>
      <td>6.651904</td>
    </tr>
    <tr>
      <th>31</th>
      <td>b2_t1</td>
      <td>g2</td>
      <td>83.561105</td>
      <td>1.158294</td>
      <td>0.650944</td>
      <td>2.670592</td>
      <td>6.979584</td>
    </tr>
    <tr>
      <th>32</th>
      <td>b2_t1</td>
      <td>g3</td>
      <td>98.943857</td>
      <td>4.443336</td>
      <td>3.825136</td>
      <td>17.956864</td>
      <td>28.704768</td>
    </tr>
    <tr>
      <th>33</th>
      <td>b2_t1</td>
      <td>g4</td>
      <td>127.694486</td>
      <td>5.903099</td>
      <td>3.863416</td>
      <td>18.481152</td>
      <td>33.816576</td>
    </tr>
    <tr>
      <th>34</th>
      <td>b2_t1</td>
      <td>g5</td>
      <td>104.226220</td>
      <td>5.923943</td>
      <td>3.925166</td>
      <td>20.578304</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>35</th>
      <td>b2_t1</td>
      <td>h1</td>
      <td>130.507872</td>
      <td>5.924606</td>
      <td>3.906435</td>
      <td>20.054016</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>36</th>
      <td>b2_t1</td>
      <td>h2</td>
      <td>98.664309</td>
      <td>5.917048</td>
      <td>3.876710</td>
      <td>18.481152</td>
      <td>39.059456</td>
    </tr>
    <tr>
      <th>37</th>
      <td>b2_t1</td>
      <td>h3</td>
      <td>137.669736</td>
      <td>5.899914</td>
      <td>3.816676</td>
      <td>18.219008</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>38</th>
      <td>b2_t1</td>
      <td>h4</td>
      <td>101.321112</td>
      <td>5.904183</td>
      <td>3.804448</td>
      <td>18.219008</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>39</th>
      <td>b2_t1</td>
      <td>h5</td>
      <td>104.007671</td>
      <td>5.896509</td>
      <td>3.839013</td>
      <td>18.219008</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>40</th>
      <td>b2_t1</td>
      <td>i1</td>
      <td>127.577284</td>
      <td>5.905301</td>
      <td>3.836431</td>
      <td>18.481152</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>41</th>
      <td>b2_t1</td>
      <td>i2</td>
      <td>106.278686</td>
      <td>5.933013</td>
      <td>3.845477</td>
      <td>18.481152</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>42</th>
      <td>b2_t1</td>
      <td>i3</td>
      <td>101.747360</td>
      <td>5.918613</td>
      <td>3.819285</td>
      <td>18.481152</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>43</th>
      <td>b2_t1</td>
      <td>i4</td>
      <td>130.361933</td>
      <td>5.917122</td>
      <td>3.912056</td>
      <td>18.481152</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>44</th>
      <td>b2_t1</td>
      <td>i5</td>
      <td>125.034424</td>
      <td>5.912760</td>
      <td>3.892198</td>
      <td>18.219008</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>45</th>
      <td>b2_t1</td>
      <td>j1</td>
      <td>109.374159</td>
      <td>5.926906</td>
      <td>3.862755</td>
      <td>18.481152</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>46</th>
      <td>b2_t1</td>
      <td>j2</td>
      <td>130.202472</td>
      <td>5.928445</td>
      <td>3.870202</td>
      <td>18.481152</td>
      <td>39.059456</td>
    </tr>
    <tr>
      <th>47</th>
      <td>b2_t1</td>
      <td>j3</td>
      <td>106.458561</td>
      <td>5.936170</td>
      <td>3.899451</td>
      <td>19.005440</td>
      <td>39.059456</td>
    </tr>
    <tr>
      <th>48</th>
      <td>b2_t1</td>
      <td>j4</td>
      <td>162.079734</td>
      <td>5.940704</td>
      <td>3.918237</td>
      <td>18.481152</td>
      <td>36.438016</td>
    </tr>
    <tr>
      <th>49</th>
      <td>b2_t1</td>
      <td>j5</td>
      <td>130.081632</td>
      <td>5.938387</td>
      <td>3.965393</td>
      <td>18.481152</td>
      <td>39.059456</td>
    </tr>
  </tbody>
</table>
</div>


    #> ip-10-0-142-88.ec2.internal [b2_t2]



<div>
<style scoped>
    .dataframe tbody tr th:only-of-type {
        vertical-align: middle;
    }

    .dataframe tbody tr th {
        vertical-align: top;
    }

    .dataframe thead th {
        text-align: right;
    }
</style>
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th>battery_id</th>
      <th>job_Id</th>
      <th>sync_lat_max_ms</th>
      <th>sync_lat_mean_ms</th>
      <th>sync_lat_stddev_ms</th>
      <th>sync_lat_p99_ms</th>
      <th>sync_lat_p99.9_ms</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>0</th>
      <td>b2_t2</td>
      <td>a1</td>
      <td>42.921417</td>
      <td>1.319287</td>
      <td>0.703880</td>
      <td>2.703360</td>
      <td>9.502720</td>
    </tr>
    <tr>
      <th>1</th>
      <td>b2_t2</td>
      <td>a2</td>
      <td>28.750373</td>
      <td>1.348980</td>
      <td>0.723067</td>
      <td>2.932736</td>
      <td>9.764864</td>
    </tr>
    <tr>
      <th>2</th>
      <td>b2_t2</td>
      <td>a3</td>
      <td>19.301707</td>
      <td>1.334769</td>
      <td>0.688169</td>
      <td>2.899968</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>3</th>
      <td>b2_t2</td>
      <td>a4</td>
      <td>35.648584</td>
      <td>1.322543</td>
      <td>0.707594</td>
      <td>2.736128</td>
      <td>9.764864</td>
    </tr>
    <tr>
      <th>4</th>
      <td>b2_t2</td>
      <td>a5</td>
      <td>80.075922</td>
      <td>1.363166</td>
      <td>0.754138</td>
      <td>2.998272</td>
      <td>9.895936</td>
    </tr>
    <tr>
      <th>5</th>
      <td>b2_t2</td>
      <td>b1</td>
      <td>16.037055</td>
      <td>1.342571</td>
      <td>0.687214</td>
      <td>2.801664</td>
      <td>9.371648</td>
    </tr>
    <tr>
      <th>6</th>
      <td>b2_t2</td>
      <td>b2</td>
      <td>67.246422</td>
      <td>1.380487</td>
      <td>0.751622</td>
      <td>2.965504</td>
      <td>9.764864</td>
    </tr>
    <tr>
      <th>7</th>
      <td>b2_t2</td>
      <td>b3</td>
      <td>68.943773</td>
      <td>1.349172</td>
      <td>0.730728</td>
      <td>2.899968</td>
      <td>8.978432</td>
    </tr>
    <tr>
      <th>8</th>
      <td>b2_t2</td>
      <td>b4</td>
      <td>17.130309</td>
      <td>1.323254</td>
      <td>0.679319</td>
      <td>2.834432</td>
      <td>9.109504</td>
    </tr>
    <tr>
      <th>9</th>
      <td>b2_t2</td>
      <td>b5</td>
      <td>83.009037</td>
      <td>1.314879</td>
      <td>0.751204</td>
      <td>2.768896</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>10</th>
      <td>b2_t2</td>
      <td>c1</td>
      <td>21.638637</td>
      <td>1.288025</td>
      <td>0.674037</td>
      <td>2.637824</td>
      <td>9.371648</td>
    </tr>
    <tr>
      <th>11</th>
      <td>b2_t2</td>
      <td>c2</td>
      <td>16.988951</td>
      <td>1.310626</td>
      <td>0.682124</td>
      <td>2.768896</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>12</th>
      <td>b2_t2</td>
      <td>c3</td>
      <td>19.812239</td>
      <td>1.325149</td>
      <td>0.687454</td>
      <td>2.768896</td>
      <td>9.502720</td>
    </tr>
    <tr>
      <th>13</th>
      <td>b2_t2</td>
      <td>c4</td>
      <td>18.536172</td>
      <td>1.327079</td>
      <td>0.701443</td>
      <td>2.899968</td>
      <td>9.502720</td>
    </tr>
    <tr>
      <th>14</th>
      <td>b2_t2</td>
      <td>c5</td>
      <td>20.644870</td>
      <td>1.326199</td>
      <td>0.704009</td>
      <td>2.834432</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>15</th>
      <td>b2_t2</td>
      <td>d1</td>
      <td>57.498424</td>
      <td>1.343508</td>
      <td>0.744269</td>
      <td>2.965504</td>
      <td>10.158080</td>
    </tr>
    <tr>
      <th>16</th>
      <td>b2_t2</td>
      <td>d2</td>
      <td>24.036400</td>
      <td>1.340880</td>
      <td>0.694338</td>
      <td>2.834432</td>
      <td>9.502720</td>
    </tr>
    <tr>
      <th>17</th>
      <td>b2_t2</td>
      <td>d3</td>
      <td>82.225018</td>
      <td>1.341512</td>
      <td>0.750067</td>
      <td>2.867200</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>18</th>
      <td>b2_t2</td>
      <td>d4</td>
      <td>80.986273</td>
      <td>1.338761</td>
      <td>0.753507</td>
      <td>2.899968</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>19</th>
      <td>b2_t2</td>
      <td>d5</td>
      <td>22.170003</td>
      <td>1.338119</td>
      <td>0.704970</td>
      <td>2.867200</td>
      <td>9.895936</td>
    </tr>
    <tr>
      <th>20</th>
      <td>b2_t2</td>
      <td>e1</td>
      <td>18.404405</td>
      <td>1.313773</td>
      <td>0.680368</td>
      <td>2.736128</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>21</th>
      <td>b2_t2</td>
      <td>e2</td>
      <td>79.907495</td>
      <td>1.337504</td>
      <td>0.742640</td>
      <td>2.834432</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>22</th>
      <td>b2_t2</td>
      <td>e3</td>
      <td>23.808354</td>
      <td>1.352634</td>
      <td>0.714605</td>
      <td>2.932736</td>
      <td>9.764864</td>
    </tr>
    <tr>
      <th>23</th>
      <td>b2_t2</td>
      <td>e4</td>
      <td>24.078522</td>
      <td>1.321663</td>
      <td>0.686635</td>
      <td>2.768896</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>24</th>
      <td>b2_t2</td>
      <td>e5</td>
      <td>25.349922</td>
      <td>1.355056</td>
      <td>0.709999</td>
      <td>2.867200</td>
      <td>9.895936</td>
    </tr>
    <tr>
      <th>25</th>
      <td>b2_t2</td>
      <td>f1</td>
      <td>18.479378</td>
      <td>1.292314</td>
      <td>0.670444</td>
      <td>2.605056</td>
      <td>9.502720</td>
    </tr>
    <tr>
      <th>26</th>
      <td>b2_t2</td>
      <td>f2</td>
      <td>16.161620</td>
      <td>1.270952</td>
      <td>0.638763</td>
      <td>2.506752</td>
      <td>8.454144</td>
    </tr>
    <tr>
      <th>27</th>
      <td>b2_t2</td>
      <td>f3</td>
      <td>78.555610</td>
      <td>1.304639</td>
      <td>0.730971</td>
      <td>2.768896</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>28</th>
      <td>b2_t2</td>
      <td>f4</td>
      <td>72.935047</td>
      <td>1.320057</td>
      <td>0.787872</td>
      <td>2.899968</td>
      <td>10.813440</td>
    </tr>
    <tr>
      <th>29</th>
      <td>b2_t2</td>
      <td>f5</td>
      <td>18.523360</td>
      <td>1.304557</td>
      <td>0.661377</td>
      <td>2.736128</td>
      <td>8.716288</td>
    </tr>
    <tr>
      <th>30</th>
      <td>b2_t2</td>
      <td>g1</td>
      <td>76.735155</td>
      <td>1.302631</td>
      <td>0.725293</td>
      <td>2.736128</td>
      <td>9.502720</td>
    </tr>
    <tr>
      <th>31</th>
      <td>b2_t2</td>
      <td>g2</td>
      <td>78.265215</td>
      <td>1.318653</td>
      <td>0.734398</td>
      <td>2.670592</td>
      <td>9.764864</td>
    </tr>
    <tr>
      <th>32</th>
      <td>b2_t2</td>
      <td>g3</td>
      <td>18.506985</td>
      <td>1.278411</td>
      <td>0.660164</td>
      <td>2.605056</td>
      <td>9.109504</td>
    </tr>
    <tr>
      <th>33</th>
      <td>b2_t2</td>
      <td>g4</td>
      <td>24.294061</td>
      <td>1.326244</td>
      <td>0.693937</td>
      <td>2.801664</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>34</th>
      <td>b2_t2</td>
      <td>g5</td>
      <td>79.426097</td>
      <td>1.340073</td>
      <td>0.750579</td>
      <td>2.867200</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>35</th>
      <td>b2_t2</td>
      <td>h1</td>
      <td>79.757899</td>
      <td>1.319705</td>
      <td>0.741914</td>
      <td>2.736128</td>
      <td>9.764864</td>
    </tr>
    <tr>
      <th>36</th>
      <td>b2_t2</td>
      <td>h2</td>
      <td>37.476716</td>
      <td>1.336998</td>
      <td>0.725465</td>
      <td>2.899968</td>
      <td>10.158080</td>
    </tr>
    <tr>
      <th>37</th>
      <td>b2_t2</td>
      <td>h3</td>
      <td>79.369348</td>
      <td>5.690261</td>
      <td>3.389939</td>
      <td>18.219008</td>
      <td>25.821184</td>
    </tr>
    <tr>
      <th>38</th>
      <td>b2_t2</td>
      <td>h4</td>
      <td>88.399460</td>
      <td>5.808433</td>
      <td>3.408925</td>
      <td>18.219008</td>
      <td>25.821184</td>
    </tr>
    <tr>
      <th>39</th>
      <td>b2_t2</td>
      <td>h5</td>
      <td>57.270093</td>
      <td>5.841664</td>
      <td>3.453397</td>
      <td>18.219008</td>
      <td>25.821184</td>
    </tr>
    <tr>
      <th>40</th>
      <td>b2_t2</td>
      <td>i1</td>
      <td>91.292011</td>
      <td>5.849903</td>
      <td>3.465687</td>
      <td>18.219008</td>
      <td>23.724032</td>
    </tr>
    <tr>
      <th>41</th>
      <td>b2_t2</td>
      <td>i2</td>
      <td>70.225794</td>
      <td>5.862731</td>
      <td>3.476876</td>
      <td>18.219008</td>
      <td>24.248320</td>
    </tr>
    <tr>
      <th>42</th>
      <td>b2_t2</td>
      <td>i3</td>
      <td>62.654754</td>
      <td>5.841414</td>
      <td>3.440871</td>
      <td>18.219008</td>
      <td>25.559040</td>
    </tr>
    <tr>
      <th>43</th>
      <td>b2_t2</td>
      <td>i4</td>
      <td>75.292917</td>
      <td>5.845320</td>
      <td>3.462567</td>
      <td>18.219008</td>
      <td>25.296896</td>
    </tr>
    <tr>
      <th>44</th>
      <td>b2_t2</td>
      <td>i5</td>
      <td>78.167728</td>
      <td>5.839628</td>
      <td>3.483655</td>
      <td>18.219008</td>
      <td>26.083328</td>
    </tr>
    <tr>
      <th>45</th>
      <td>b2_t2</td>
      <td>j1</td>
      <td>79.784803</td>
      <td>5.854145</td>
      <td>3.480325</td>
      <td>18.219008</td>
      <td>26.083328</td>
    </tr>
    <tr>
      <th>46</th>
      <td>b2_t2</td>
      <td>j2</td>
      <td>65.524540</td>
      <td>5.847236</td>
      <td>3.483793</td>
      <td>18.219008</td>
      <td>25.821184</td>
    </tr>
    <tr>
      <th>47</th>
      <td>b2_t2</td>
      <td>j3</td>
      <td>78.996063</td>
      <td>5.845602</td>
      <td>3.453708</td>
      <td>18.219008</td>
      <td>23.724032</td>
    </tr>
    <tr>
      <th>48</th>
      <td>b2_t2</td>
      <td>j4</td>
      <td>62.459498</td>
      <td>5.839305</td>
      <td>3.418863</td>
      <td>18.219008</td>
      <td>23.986176</td>
    </tr>
    <tr>
      <th>49</th>
      <td>b2_t2</td>
      <td>j5</td>
      <td>65.139597</td>
      <td>5.827451</td>
      <td>3.427648</td>
      <td>18.219008</td>
      <td>25.821184</td>
    </tr>
  </tbody>
</table>
</div>


    #> ip-10-0-137-24.ec2.internal [b2_t3]



<div>
<style scoped>
    .dataframe tbody tr th:only-of-type {
        vertical-align: middle;
    }

    .dataframe tbody tr th {
        vertical-align: top;
    }

    .dataframe thead th {
        text-align: right;
    }
</style>
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th>battery_id</th>
      <th>job_Id</th>
      <th>sync_lat_max_ms</th>
      <th>sync_lat_mean_ms</th>
      <th>sync_lat_stddev_ms</th>
      <th>sync_lat_p99_ms</th>
      <th>sync_lat_p99.9_ms</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>0</th>
      <td>b2_t3</td>
      <td>a1</td>
      <td>68.017842</td>
      <td>1.333167</td>
      <td>0.772607</td>
      <td>3.653632</td>
      <td>8.454144</td>
    </tr>
    <tr>
      <th>1</th>
      <td>b2_t3</td>
      <td>a2</td>
      <td>18.266890</td>
      <td>1.687630</td>
      <td>0.841022</td>
      <td>4.227072</td>
      <td>9.502720</td>
    </tr>
    <tr>
      <th>2</th>
      <td>b2_t3</td>
      <td>a3</td>
      <td>78.664201</td>
      <td>1.650445</td>
      <td>0.836908</td>
      <td>3.883008</td>
      <td>8.978432</td>
    </tr>
    <tr>
      <th>3</th>
      <td>b2_t3</td>
      <td>a4</td>
      <td>33.433859</td>
      <td>1.641819</td>
      <td>0.819819</td>
      <td>4.145152</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>4</th>
      <td>b2_t3</td>
      <td>a5</td>
      <td>76.929612</td>
      <td>1.666814</td>
      <td>0.871086</td>
      <td>4.079616</td>
      <td>9.764864</td>
    </tr>
    <tr>
      <th>5</th>
      <td>b2_t3</td>
      <td>b1</td>
      <td>66.840544</td>
      <td>1.681684</td>
      <td>0.853895</td>
      <td>4.046848</td>
      <td>9.371648</td>
    </tr>
    <tr>
      <th>6</th>
      <td>b2_t3</td>
      <td>b2</td>
      <td>46.956900</td>
      <td>1.774595</td>
      <td>0.952194</td>
      <td>5.079040</td>
      <td>10.551296</td>
    </tr>
    <tr>
      <th>7</th>
      <td>b2_t3</td>
      <td>b3</td>
      <td>22.667406</td>
      <td>1.744623</td>
      <td>0.914686</td>
      <td>4.751360</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>8</th>
      <td>b2_t3</td>
      <td>b4</td>
      <td>33.258572</td>
      <td>1.722502</td>
      <td>0.917649</td>
      <td>4.489216</td>
      <td>10.420224</td>
    </tr>
    <tr>
      <th>9</th>
      <td>b2_t3</td>
      <td>b5</td>
      <td>32.785594</td>
      <td>1.681496</td>
      <td>0.844867</td>
      <td>4.177920</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>10</th>
      <td>b2_t3</td>
      <td>c1</td>
      <td>59.235491</td>
      <td>1.601921</td>
      <td>0.844636</td>
      <td>3.883008</td>
      <td>9.895936</td>
    </tr>
    <tr>
      <th>11</th>
      <td>b2_t3</td>
      <td>c2</td>
      <td>79.425341</td>
      <td>1.593500</td>
      <td>0.803912</td>
      <td>3.457024</td>
      <td>8.716288</td>
    </tr>
    <tr>
      <th>12</th>
      <td>b2_t3</td>
      <td>c3</td>
      <td>24.650658</td>
      <td>1.629773</td>
      <td>0.790597</td>
      <td>3.653632</td>
      <td>8.847360</td>
    </tr>
    <tr>
      <th>13</th>
      <td>b2_t3</td>
      <td>c4</td>
      <td>16.888352</td>
      <td>1.612760</td>
      <td>0.762405</td>
      <td>3.457024</td>
      <td>8.847360</td>
    </tr>
    <tr>
      <th>14</th>
      <td>b2_t3</td>
      <td>c5</td>
      <td>23.930174</td>
      <td>1.596592</td>
      <td>0.786703</td>
      <td>3.751936</td>
      <td>9.109504</td>
    </tr>
    <tr>
      <th>15</th>
      <td>b2_t3</td>
      <td>d1</td>
      <td>19.653545</td>
      <td>1.645699</td>
      <td>0.843539</td>
      <td>4.227072</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>16</th>
      <td>b2_t3</td>
      <td>d2</td>
      <td>21.477089</td>
      <td>1.615442</td>
      <td>0.787897</td>
      <td>3.620864</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>17</th>
      <td>b2_t3</td>
      <td>d3</td>
      <td>78.386342</td>
      <td>1.609966</td>
      <td>0.823499</td>
      <td>3.588096</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>18</th>
      <td>b2_t3</td>
      <td>d4</td>
      <td>83.007022</td>
      <td>1.595604</td>
      <td>0.861799</td>
      <td>3.555328</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>19</th>
      <td>b2_t3</td>
      <td>d5</td>
      <td>25.149553</td>
      <td>1.597500</td>
      <td>0.775678</td>
      <td>3.489792</td>
      <td>9.109504</td>
    </tr>
    <tr>
      <th>20</th>
      <td>b2_t3</td>
      <td>e1</td>
      <td>22.188355</td>
      <td>1.581205</td>
      <td>0.756247</td>
      <td>3.325952</td>
      <td>8.978432</td>
    </tr>
    <tr>
      <th>21</th>
      <td>b2_t3</td>
      <td>e2</td>
      <td>79.116955</td>
      <td>1.620661</td>
      <td>0.808597</td>
      <td>3.489792</td>
      <td>8.716288</td>
    </tr>
    <tr>
      <th>22</th>
      <td>b2_t3</td>
      <td>e3</td>
      <td>30.646049</td>
      <td>1.635464</td>
      <td>0.768980</td>
      <td>3.588096</td>
      <td>8.716288</td>
    </tr>
    <tr>
      <th>23</th>
      <td>b2_t3</td>
      <td>e4</td>
      <td>18.313882</td>
      <td>1.622308</td>
      <td>0.767243</td>
      <td>3.555328</td>
      <td>8.847360</td>
    </tr>
    <tr>
      <th>24</th>
      <td>b2_t3</td>
      <td>e5</td>
      <td>18.892629</td>
      <td>1.667598</td>
      <td>0.809127</td>
      <td>3.948544</td>
      <td>8.978432</td>
    </tr>
    <tr>
      <th>25</th>
      <td>b2_t3</td>
      <td>f1</td>
      <td>21.439933</td>
      <td>1.704640</td>
      <td>0.866086</td>
      <td>4.554752</td>
      <td>9.764864</td>
    </tr>
    <tr>
      <th>26</th>
      <td>b2_t3</td>
      <td>f2</td>
      <td>19.664112</td>
      <td>1.675780</td>
      <td>0.824882</td>
      <td>4.046848</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>27</th>
      <td>b2_t3</td>
      <td>f3</td>
      <td>79.879006</td>
      <td>1.627094</td>
      <td>0.854483</td>
      <td>4.112384</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>28</th>
      <td>b2_t3</td>
      <td>f4</td>
      <td>42.729975</td>
      <td>1.640222</td>
      <td>0.799137</td>
      <td>3.653632</td>
      <td>9.109504</td>
    </tr>
    <tr>
      <th>29</th>
      <td>b2_t3</td>
      <td>f5</td>
      <td>83.259088</td>
      <td>1.666991</td>
      <td>0.898885</td>
      <td>4.112384</td>
      <td>9.764864</td>
    </tr>
    <tr>
      <th>30</th>
      <td>b2_t3</td>
      <td>g1</td>
      <td>42.321099</td>
      <td>1.657269</td>
      <td>0.883888</td>
      <td>4.423680</td>
      <td>9.895936</td>
    </tr>
    <tr>
      <th>31</th>
      <td>b2_t3</td>
      <td>g2</td>
      <td>81.137182</td>
      <td>1.649059</td>
      <td>0.877024</td>
      <td>4.145152</td>
      <td>9.502720</td>
    </tr>
    <tr>
      <th>32</th>
      <td>b2_t3</td>
      <td>g3</td>
      <td>33.762865</td>
      <td>1.687637</td>
      <td>0.854193</td>
      <td>4.292608</td>
      <td>9.502720</td>
    </tr>
    <tr>
      <th>33</th>
      <td>b2_t3</td>
      <td>g4</td>
      <td>20.463802</td>
      <td>1.659621</td>
      <td>0.824036</td>
      <td>4.227072</td>
      <td>8.978432</td>
    </tr>
    <tr>
      <th>34</th>
      <td>b2_t3</td>
      <td>g5</td>
      <td>21.846251</td>
      <td>1.659012</td>
      <td>0.829251</td>
      <td>4.112384</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>35</th>
      <td>b2_t3</td>
      <td>h1</td>
      <td>26.704316</td>
      <td>1.681932</td>
      <td>0.890803</td>
      <td>4.227072</td>
      <td>10.420224</td>
    </tr>
    <tr>
      <th>36</th>
      <td>b2_t3</td>
      <td>h2</td>
      <td>26.717716</td>
      <td>1.615984</td>
      <td>0.805530</td>
      <td>3.719168</td>
      <td>9.371648</td>
    </tr>
    <tr>
      <th>37</th>
      <td>b2_t3</td>
      <td>h3</td>
      <td>23.694303</td>
      <td>1.646508</td>
      <td>0.813346</td>
      <td>3.883008</td>
      <td>9.240576</td>
    </tr>
    <tr>
      <th>38</th>
      <td>b2_t3</td>
      <td>h4</td>
      <td>77.473870</td>
      <td>1.623840</td>
      <td>0.825446</td>
      <td>3.751936</td>
      <td>8.978432</td>
    </tr>
    <tr>
      <th>39</th>
      <td>b2_t3</td>
      <td>h5</td>
      <td>79.897140</td>
      <td>1.632903</td>
      <td>0.856980</td>
      <td>3.948544</td>
      <td>9.109504</td>
    </tr>
    <tr>
      <th>40</th>
      <td>b2_t3</td>
      <td>i1</td>
      <td>80.932569</td>
      <td>1.675081</td>
      <td>0.917261</td>
      <td>4.046848</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>41</th>
      <td>b2_t3</td>
      <td>i2</td>
      <td>76.433845</td>
      <td>1.710924</td>
      <td>0.862999</td>
      <td>4.112384</td>
      <td>9.109504</td>
    </tr>
    <tr>
      <th>42</th>
      <td>b2_t3</td>
      <td>i3</td>
      <td>78.075309</td>
      <td>1.746246</td>
      <td>0.949621</td>
      <td>4.685824</td>
      <td>10.158080</td>
    </tr>
    <tr>
      <th>43</th>
      <td>b2_t3</td>
      <td>i4</td>
      <td>82.724512</td>
      <td>1.773936</td>
      <td>0.988854</td>
      <td>4.751360</td>
      <td>10.289152</td>
    </tr>
    <tr>
      <th>44</th>
      <td>b2_t3</td>
      <td>i5</td>
      <td>80.088464</td>
      <td>1.690446</td>
      <td>0.889230</td>
      <td>4.079616</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>45</th>
      <td>b2_t3</td>
      <td>j1</td>
      <td>77.763431</td>
      <td>1.620321</td>
      <td>0.794586</td>
      <td>3.391488</td>
      <td>8.716288</td>
    </tr>
    <tr>
      <th>46</th>
      <td>b2_t3</td>
      <td>j2</td>
      <td>79.562965</td>
      <td>1.713289</td>
      <td>0.910338</td>
      <td>4.423680</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>47</th>
      <td>b2_t3</td>
      <td>j3</td>
      <td>80.719352</td>
      <td>1.796371</td>
      <td>1.010509</td>
      <td>4.947968</td>
      <td>10.551296</td>
    </tr>
    <tr>
      <th>48</th>
      <td>b2_t3</td>
      <td>j4</td>
      <td>24.492515</td>
      <td>1.628370</td>
      <td>0.820270</td>
      <td>3.784704</td>
      <td>9.371648</td>
    </tr>
    <tr>
      <th>49</th>
      <td>b2_t3</td>
      <td>j5</td>
      <td>20.263875</td>
      <td>1.614145</td>
      <td>0.783822</td>
      <td>3.751936</td>
      <td>8.847360</td>
    </tr>
  </tbody>
</table>
</div>


    #> ip-10-0-133-152.ec2.internal [b2_t4]



<div>
<style scoped>
    .dataframe tbody tr th:only-of-type {
        vertical-align: middle;
    }

    .dataframe tbody tr th {
        vertical-align: top;
    }

    .dataframe thead th {
        text-align: right;
    }
</style>
<table border="1" class="dataframe">
  <thead>
    <tr style="text-align: right;">
      <th></th>
      <th>battery_id</th>
      <th>job_Id</th>
      <th>sync_lat_max_ms</th>
      <th>sync_lat_mean_ms</th>
      <th>sync_lat_stddev_ms</th>
      <th>sync_lat_p99_ms</th>
      <th>sync_lat_p99.9_ms</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>0</th>
      <td>b2_t4</td>
      <td>a1</td>
      <td>82.157969</td>
      <td>1.712503</td>
      <td>0.959877</td>
      <td>4.685824</td>
      <td>11.075584</td>
    </tr>
    <tr>
      <th>1</th>
      <td>b2_t4</td>
      <td>a2</td>
      <td>84.258343</td>
      <td>1.756673</td>
      <td>1.073758</td>
      <td>5.144576</td>
      <td>13.172736</td>
    </tr>
    <tr>
      <th>2</th>
      <td>b2_t4</td>
      <td>a3</td>
      <td>82.106066</td>
      <td>1.626919</td>
      <td>0.860998</td>
      <td>3.915776</td>
      <td>10.158080</td>
    </tr>
    <tr>
      <th>3</th>
      <td>b2_t4</td>
      <td>a4</td>
      <td>34.026425</td>
      <td>1.633420</td>
      <td>0.842392</td>
      <td>3.915776</td>
      <td>10.420224</td>
    </tr>
    <tr>
      <th>4</th>
      <td>b2_t4</td>
      <td>a5</td>
      <td>64.642143</td>
      <td>1.701093</td>
      <td>0.917508</td>
      <td>4.423680</td>
      <td>10.551296</td>
    </tr>
    <tr>
      <th>5</th>
      <td>b2_t4</td>
      <td>b1</td>
      <td>27.682156</td>
      <td>1.759722</td>
      <td>0.985698</td>
      <td>5.079040</td>
      <td>11.730944</td>
    </tr>
    <tr>
      <th>6</th>
      <td>b2_t4</td>
      <td>b2</td>
      <td>86.332541</td>
      <td>1.649717</td>
      <td>0.877783</td>
      <td>3.784704</td>
      <td>10.682368</td>
    </tr>
    <tr>
      <th>7</th>
      <td>b2_t4</td>
      <td>b3</td>
      <td>19.102149</td>
      <td>1.654040</td>
      <td>0.821403</td>
      <td>3.817472</td>
      <td>10.420224</td>
    </tr>
    <tr>
      <th>8</th>
      <td>b2_t4</td>
      <td>b4</td>
      <td>18.097099</td>
      <td>1.703117</td>
      <td>0.850724</td>
      <td>3.948544</td>
      <td>10.682368</td>
    </tr>
    <tr>
      <th>9</th>
      <td>b2_t4</td>
      <td>b5</td>
      <td>82.894287</td>
      <td>1.630997</td>
      <td>0.880190</td>
      <td>3.620864</td>
      <td>10.813440</td>
    </tr>
    <tr>
      <th>10</th>
      <td>b2_t4</td>
      <td>c1</td>
      <td>34.250775</td>
      <td>1.688473</td>
      <td>0.907226</td>
      <td>4.358144</td>
      <td>11.730944</td>
    </tr>
    <tr>
      <th>11</th>
      <td>b2_t4</td>
      <td>c2</td>
      <td>50.890176</td>
      <td>1.540552</td>
      <td>0.757315</td>
      <td>3.096576</td>
      <td>10.158080</td>
    </tr>
    <tr>
      <th>12</th>
      <td>b2_t4</td>
      <td>c3</td>
      <td>81.638564</td>
      <td>1.653208</td>
      <td>0.865012</td>
      <td>3.883008</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>13</th>
      <td>b2_t4</td>
      <td>c4</td>
      <td>34.058662</td>
      <td>1.679135</td>
      <td>0.840935</td>
      <td>4.046848</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>14</th>
      <td>b2_t4</td>
      <td>c5</td>
      <td>35.630164</td>
      <td>1.620467</td>
      <td>0.794594</td>
      <td>3.555328</td>
      <td>10.158080</td>
    </tr>
    <tr>
      <th>15</th>
      <td>b2_t4</td>
      <td>d1</td>
      <td>59.792853</td>
      <td>1.627862</td>
      <td>0.838632</td>
      <td>3.620864</td>
      <td>10.551296</td>
    </tr>
    <tr>
      <th>16</th>
      <td>b2_t4</td>
      <td>d2</td>
      <td>22.930208</td>
      <td>1.601489</td>
      <td>0.768104</td>
      <td>3.391488</td>
      <td>9.633792</td>
    </tr>
    <tr>
      <th>17</th>
      <td>b2_t4</td>
      <td>d3</td>
      <td>18.953083</td>
      <td>1.682410</td>
      <td>0.846683</td>
      <td>3.883008</td>
      <td>10.551296</td>
    </tr>
    <tr>
      <th>18</th>
      <td>b2_t4</td>
      <td>d4</td>
      <td>35.577028</td>
      <td>1.690741</td>
      <td>0.880741</td>
      <td>4.112384</td>
      <td>11.075584</td>
    </tr>
    <tr>
      <th>19</th>
      <td>b2_t4</td>
      <td>d5</td>
      <td>82.663219</td>
      <td>1.613168</td>
      <td>0.859680</td>
      <td>3.719168</td>
      <td>10.944512</td>
    </tr>
    <tr>
      <th>20</th>
      <td>b2_t4</td>
      <td>e1</td>
      <td>84.178326</td>
      <td>1.616357</td>
      <td>0.827707</td>
      <td>3.489792</td>
      <td>10.158080</td>
    </tr>
    <tr>
      <th>21</th>
      <td>b2_t4</td>
      <td>e2</td>
      <td>84.137220</td>
      <td>1.585113</td>
      <td>0.826806</td>
      <td>3.391488</td>
      <td>10.420224</td>
    </tr>
    <tr>
      <th>22</th>
      <td>b2_t4</td>
      <td>e3</td>
      <td>65.512945</td>
      <td>1.600341</td>
      <td>0.796826</td>
      <td>3.391488</td>
      <td>10.158080</td>
    </tr>
    <tr>
      <th>23</th>
      <td>b2_t4</td>
      <td>e4</td>
      <td>42.574045</td>
      <td>1.694389</td>
      <td>0.903739</td>
      <td>4.423680</td>
      <td>11.075584</td>
    </tr>
    <tr>
      <th>24</th>
      <td>b2_t4</td>
      <td>e5</td>
      <td>54.098514</td>
      <td>1.656733</td>
      <td>0.841158</td>
      <td>3.751936</td>
      <td>10.289152</td>
    </tr>
    <tr>
      <th>25</th>
      <td>b2_t4</td>
      <td>f1</td>
      <td>80.975664</td>
      <td>1.721286</td>
      <td>1.012981</td>
      <td>4.620288</td>
      <td>12.517376</td>
    </tr>
    <tr>
      <th>26</th>
      <td>b2_t4</td>
      <td>f2</td>
      <td>82.165180</td>
      <td>1.736041</td>
      <td>0.998473</td>
      <td>4.816896</td>
      <td>11.337728</td>
    </tr>
    <tr>
      <th>27</th>
      <td>b2_t4</td>
      <td>f3</td>
      <td>38.448971</td>
      <td>1.645838</td>
      <td>0.830153</td>
      <td>3.653632</td>
      <td>10.420224</td>
    </tr>
    <tr>
      <th>28</th>
      <td>b2_t4</td>
      <td>f4</td>
      <td>20.558225</td>
      <td>1.663913</td>
      <td>0.839331</td>
      <td>3.850240</td>
      <td>10.682368</td>
    </tr>
    <tr>
      <th>29</th>
      <td>b2_t4</td>
      <td>f5</td>
      <td>17.461157</td>
      <td>1.641694</td>
      <td>0.815392</td>
      <td>3.620864</td>
      <td>10.944512</td>
    </tr>
    <tr>
      <th>30</th>
      <td>b2_t4</td>
      <td>g1</td>
      <td>22.709828</td>
      <td>1.636465</td>
      <td>0.814237</td>
      <td>3.620864</td>
      <td>10.420224</td>
    </tr>
    <tr>
      <th>31</th>
      <td>b2_t4</td>
      <td>g2</td>
      <td>73.773492</td>
      <td>1.599612</td>
      <td>0.820261</td>
      <td>3.424256</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>32</th>
      <td>b2_t4</td>
      <td>g3</td>
      <td>71.800190</td>
      <td>1.619913</td>
      <td>0.814386</td>
      <td>3.522560</td>
      <td>10.158080</td>
    </tr>
    <tr>
      <th>33</th>
      <td>b2_t4</td>
      <td>g4</td>
      <td>20.252410</td>
      <td>1.573605</td>
      <td>0.779804</td>
      <td>3.522560</td>
      <td>10.027008</td>
    </tr>
    <tr>
      <th>34</th>
      <td>b2_t4</td>
      <td>g5</td>
      <td>84.670361</td>
      <td>1.642198</td>
      <td>0.888350</td>
      <td>3.784704</td>
      <td>10.289152</td>
    </tr>
    <tr>
      <th>35</th>
      <td>b2_t4</td>
      <td>h1</td>
      <td>82.534891</td>
      <td>1.669151</td>
      <td>0.915968</td>
      <td>3.883008</td>
      <td>10.944512</td>
    </tr>
    <tr>
      <th>36</th>
      <td>b2_t4</td>
      <td>h2</td>
      <td>69.176836</td>
      <td>1.716879</td>
      <td>0.905877</td>
      <td>4.227072</td>
      <td>10.944512</td>
    </tr>
    <tr>
      <th>37</th>
      <td>b2_t4</td>
      <td>h3</td>
      <td>83.234735</td>
      <td>1.724542</td>
      <td>0.969917</td>
      <td>4.554752</td>
      <td>11.599872</td>
    </tr>
    <tr>
      <th>38</th>
      <td>b2_t4</td>
      <td>h4</td>
      <td>35.095336</td>
      <td>1.746813</td>
      <td>0.937789</td>
      <td>4.489216</td>
      <td>11.206656</td>
    </tr>
    <tr>
      <th>39</th>
      <td>b2_t4</td>
      <td>h5</td>
      <td>22.740948</td>
      <td>1.668419</td>
      <td>0.838676</td>
      <td>3.948544</td>
      <td>10.289152</td>
    </tr>
    <tr>
      <th>40</th>
      <td>b2_t4</td>
      <td>i1</td>
      <td>19.667939</td>
      <td>1.727930</td>
      <td>0.893797</td>
      <td>4.423680</td>
      <td>10.682368</td>
    </tr>
    <tr>
      <th>41</th>
      <td>b2_t4</td>
      <td>i2</td>
      <td>82.139685</td>
      <td>1.690698</td>
      <td>0.945605</td>
      <td>4.292608</td>
      <td>11.337728</td>
    </tr>
    <tr>
      <th>42</th>
      <td>b2_t4</td>
      <td>i3</td>
      <td>84.682646</td>
      <td>1.678174</td>
      <td>0.936211</td>
      <td>4.014080</td>
      <td>11.862016</td>
    </tr>
    <tr>
      <th>43</th>
      <td>b2_t4</td>
      <td>i4</td>
      <td>19.903843</td>
      <td>1.637586</td>
      <td>0.820174</td>
      <td>3.784704</td>
      <td>10.682368</td>
    </tr>
    <tr>
      <th>44</th>
      <td>b2_t4</td>
      <td>i5</td>
      <td>68.709482</td>
      <td>1.681608</td>
      <td>0.891130</td>
      <td>3.817472</td>
      <td>10.813440</td>
    </tr>
    <tr>
      <th>45</th>
      <td>b2_t4</td>
      <td>j1</td>
      <td>82.784139</td>
      <td>1.657394</td>
      <td>0.906569</td>
      <td>3.719168</td>
      <td>10.551296</td>
    </tr>
    <tr>
      <th>46</th>
      <td>b2_t4</td>
      <td>j2</td>
      <td>76.739871</td>
      <td>1.614540</td>
      <td>0.831806</td>
      <td>3.457024</td>
      <td>10.289152</td>
    </tr>
    <tr>
      <th>47</th>
      <td>b2_t4</td>
      <td>j3</td>
      <td>21.593767</td>
      <td>1.728508</td>
      <td>0.897712</td>
      <td>4.292608</td>
      <td>10.813440</td>
    </tr>
    <tr>
      <th>48</th>
      <td>b2_t4</td>
      <td>j4</td>
      <td>86.788914</td>
      <td>1.668683</td>
      <td>0.936373</td>
      <td>4.177920</td>
      <td>10.944512</td>
    </tr>
    <tr>
      <th>49</th>
      <td>b2_t4</td>
      <td>j5</td>
      <td>19.679278</td>
      <td>1.615724</td>
      <td>0.792559</td>
      <td>3.489792</td>
      <td>10.289152</td>
    </tr>
  </tbody>
</table>
</div>

