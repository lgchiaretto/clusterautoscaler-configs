#!/bin/bash

# Variables
IFS=$'\n' # make newlines the only separator
AWK_CMD=$(which awk)
ECHO_CMD=$(which echo)
OC_CMD=$(which oc)
DEFAULT_TIMEOUT=3
DEBUG=false #change to true to enable DEBUG
CLUSTERAUTOSCALER_CONFIGURED=false
MACHINEAUTOSCALER_CONFIGURED=false

# Functions
err() {
    $ECHO_CMD; $ECHO_CMD;
    $ECHO_CMD -e "\e[97m\e[101m[ERROR]\e[0m ${1}"; shift; $ECHO_CMD;
    while [[ $# -gt 0 ]]; do $ECHO_CMD "    $1"; shift; done
    $ECHO_CMD; exit 1;
}

log(){
    $ECHO_CMD "[$(date +'%d:%m:%y %H:%M:%S')] - " $1
}

check_autoscaler_configured() {
  CLUSTERAUTOSCALER=`$OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get clusterautoscaler default 2> /dev/null`
  if [[ -z $CLUSTERAUTOSCALER ]]; then
    log "You don't have ClusterAutoscaler configured"
    log   "--------------------------------"
  else
    CLUSTERAUTOSCALER_CONFIGURED=true
  fi
}

check_machinescaler_configured() {
  MACHINEAUTOSCALER=`$OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get machineautoscaler -n openshift-machine-api 2> /dev/null`
  if [[ -z $MACHINEAUTOSCALER ]]; then
    log "You don't have MachineAutoscaler configured"
    log   "--------------------------------"
  else
    MACHINEAUTOSCALER_CONFIGURED=true
  fi
}

# check if connected on OCP
check_connected(){
  $OC_CMD --request-timeout="$DEFAULT_TIMEOUT" project -q > /dev/null
  OPENSHIFT_CONNECTED=$?
  if [[ $OPENSHIFT_CONNECTED == 1 ]]; then
    err "You are not connected in an Openshift 4 cluster"
    exit 1
  fi
}

check_machinesets(){
  MACHINESETS=$($OC_CMD get  machineset -n openshift-machine-api -o 'jsonpath={range .items[*]}{.metadata.name}{"\n"}{end}' --no-headers  --request-timeout=3)
  if [ -z "$MACHINESETS" ]; then
    err "There's no MachineSet created on cluster and it's prereq to configure ClusterAutoScaler"
    exit 1
  fi

  for machineset in $MACHINESETS; 
  do
    ms_current_size=$($OC_CMD get -o 'jsonpath={.status.replicas}' --no-headers  --request-timeout=3 machineset -n openshift-machine-api $machineset)
    log "Machineset $machineset has found and the MaxReplicas on MachineAutoscaler for MachineSet $machineset must be higher than: $ms_current_size"
  done
  log   "--------------------------------"
}

get_nodes(){
  NODES_LIST=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get nodes -o 'jsonpath={range .items[*]}{.metadata.name}{"\n"}{end}')
  NUMBER_OF_NODES=0
  for node in $NODES_LIST;
  do
    ((NUMBER_OF_NODES++))
    if [[ "${DEBUG}" == "true" ]]; then
      log   $node
      node_memory=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" --request-timeout="$DEFAULT_TIMEOUT" get nodes $node -o 'jsonpath={.status.capacity.memory}' | $AWK_CMD '{$0=$0/(1024^2); print $1,"GB";}')
      node_cpu=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get nodes $node -o 'jsonpath={.status.capacity.cpu}')
      log   "Memory: ${node_memory}"
      log   "CPU: ${node_cpu}"
      log   "---------------"
    fi
  done
}

print_clusterautoscaler(){
  if [[ "${CLUSTERAUTOSCALER_CONFIGURED}" == "true" ]]; then
    log "You have ClusterAutoscaler 'default' configured"
    log   "--------------------------------"
    MAX_CORES=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get clusterautoscaler default -o 'jsonpath={.spec.resourceLimits.cores.max}')
    MAX_MEMORY=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get clusterautoscaler default -o 'jsonpath={.spec.resourceLimits.memory.max}')
    MAX_NODES=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get clusterautoscaler default -o 'jsonpath={.spec.resourceLimits.maxNodesTotal}')
    log "Current value on spec.resourceLimits.cores.max for ClusterAutoscaler object 'default' is: $MAX_CORES"
    log "Current value on spec.resourceLimits.memory.max for clusterAutoscaler object 'default' is: $MAX_MEMORY GB"
    log "Current value on spec.resourceLimits.maxNodesTotal for clusterAutoscaler object 'default' is: $MAX_NODES"
    log   "--------------------------------"
  fi
}

print_machineautoscaler(){
  if [[ "${MACHINEAUTOSCALER_CONFIGURED}" == "true" ]]; then
    log "You have MachineAutoscaler configured"
    MACHINEAUTOSCALER=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get machineautoscaler -n openshift-machine-api -o 'jsonpath={range .items[*]}{.metadata.name}{"\n"}{end}')
    log   "--------------------------------"
    for ma in $MACHINEAUTOSCALER; do
       MAX_REPLICAS=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get machineautoscaler -n openshift-machine-api $ma -o 'jsonpath={.spec.maxReplicas}')
       MIN_REPLICAS=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get machineautoscaler -n openshift-machine-api $ma -o 'jsonpath={.spec.minReplicas}')
       log "machineAutoscaler '$ma' has found"
       log "minReplicas on '$ma' is: $MIN_REPLICAS"
       log "maxReplicas on '$ma' is: $MAX_REPLICAS"
       log   "---------------"
    done
  fi
}

print_recommendations(){
  CPU_CLUSTER_COUNT=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get nodes -o 'jsonpath={range .items[*]}{.status.capacity.cpu}{"\n"}{end}' | $AWK_CMD '{s+=$1} END {print s}')
  MEMORY_CLUSTER_COUNT=$($OC_CMD --request-timeout="$DEFAULT_TIMEOUT" get nodes -o 'jsonpath={range .items[*]}{.status.capacity.memory}{"\n"}{end}' | $AWK_CMD '{s+=$1} END {print s}')
  MEMORY_CLUSTER_COUNT_GB=$($ECHO_CMD $MEMORY_CLUSTER_COUNT | $AWK_CMD '{$0=$0/(1024^2); print int($1),"GB";}')

  log   "ClusterAutoscaler configs"
  log   "spec.cores.max must be higher than:  $CPU_CLUSTER_COUNT"
  log   "spec.memory.max must be higher than: $MEMORY_CLUSTER_COUNT_GB"
  log   "spec.maxNodesTotal must be higher than:   $NUMBER_OF_NODES"
  log   "--------------------------------"
}

# Begin
check_connected
check_machinesets
get_nodes
print_recommendations
check_autoscaler_configured
print_clusterautoscaler
check_machinescaler_configured
print_machineautoscaler

log "For more vist https://docs.openshift.com/container-platform/4.11/machine_management/applying-autoscaling.html"
