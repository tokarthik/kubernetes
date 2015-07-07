#!/bin/bash

# Copyright 2015 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# kubernetes-e2e-{gce, gke, gke-ci} jobs: This script is triggered by
# the kubernetes-build job, or runs every half hour. We abort this job
# if it takes more than 75m. As of initial commit, it typically runs
# in about half an hour.
#
# The "Workspace Cleanup Plugin" is installed and in use for this job,
# so the ${WORKSPACE} directory (the current directory) is currently
# empty.

set -o errexit
set -o nounset
set -o pipefail
set -o xtrace

echo "--------------------------------------------------------------------------------"
echo "Initial Environment:"
printenv | sort
echo "--------------------------------------------------------------------------------"

if [[ "${CIRCLECI:-}" == "true" ]]; then
    JOB_NAME="circleci-${CIRCLE_PROJECT_USERNAME}-${CIRCLE_PROJECT_REPONAME}"
    BUILD_NUMBER=${CIRCLE_BUILD_NUM}
    WORKSPACE=`pwd`
else
    # Jenkins?
    export HOME=${WORKSPACE} # Nothing should want Jenkins $HOME
fi

# Additional parameters that are passed to hack/e2e.go
E2E_OPT=${E2E_OPT:-""}

# Set environment variables shared for all of the GCE Jenkins projects.
if [[ ${JOB_NAME} =~ ^kubernetes-.*-gce ]]; then
  KUBERNETES_PROVIDER="gce"
  : ${E2E_ZONE:="us-central1-f"}
  : ${MASTER_SIZE:="n1-standard-2"}
  : ${MINION_SIZE:="n1-standard-2"}
  : ${NUM_MINIONS:="2"}
fi

if [[ "${KUBERNETES_PROVIDER}" == "aws" ]]; then
  if [[ "${PERFORMANCE:-}" == "true" ]]; then
    : ${MASTER_SIZE:="m3.xlarge"}
    : ${NUM_MINIONS:="100"}
    : ${GINKGO_TEST_ARGS:="--ginkgo.focus=\[Performance\ssuite\]"}
  else
    : ${MASTER_SIZE:="t2.small"}
    : ${NUM_MINIONS:="2"}
  fi
fi

# Specialized tests which should be skipped by default for projects.
GCE_DEFAULT_SKIP_TEST_REGEX="Skipped|Density|Reboot|Restart|Example"
# The following tests are known to be flaky, and are thus run only in their own
# -flaky- build variants.
GCE_FLAKY_TEST_REGEX="Addon|Elasticsearch|Nodes.*network\spartition|Proxy.*logs|Shell.*services|MaxPods.*"
# Tests which are not able to be run in parallel.
GCE_PARALLEL_SKIP_TEST_REGEX="${GCE_DEFAULT_SKIP_TEST_REGEX}|Etcd|NetworkingNew|Nodes\sNetwork|Nodes\sResize|MaxPods"
# Tests which are known to be flaky when run in parallel.
# TODO: figure out why GCE_FLAKY_TEST_REGEX is not a perfect subset of this list.
GCE_PARALLEL_FLAKY_TEST_REGEX="Addon|Elasticsearch|Hostdir.*MOD|Networking.*intra|PD|Proxy.*logs|ServiceAccounts|Service\sendpoints\slatency|Services.*change\sthe\stype|Services.*functioning\sexternal\sload\sbalancer|Services.*identically\snamed|Services.*release.*load\sbalancer|Shell|multiport\sendpoints"

# Define environment variables based on the Jenkins project name.
case ${JOB_NAME} in
  # Runs all non-flaky tests on GCE, sequentially.
  kubernetes-e2e-gce)
    : ${E2E_CLUSTER_NAME:="jenkins-gce-e2e"}
    : ${E2E_DOWN:="false"}
    : ${E2E_NETWORK:="e2e-gce"}
    : ${GINKGO_TEST_ARGS:="--ginkgo.skip=${GCE_DEFAULT_SKIP_TEST_REGEX}|${GCE_FLAKY_TEST_REGEX}"}
    : ${KUBE_GCE_INSTANCE_PREFIX="e2e-gce"}
    : ${PROJECT:="k8s-jkns-e2e-gce"}
    ;;

  # Runs the flaky tests on GCE, sequentially.
  kubernetes-e2e-gce-flaky)
    : ${E2E_CLUSTER_NAME:="jenkins-gce-e2e-flaky"}
    : ${E2E_DOWN:="false"}
    : ${E2E_NETWORK:="e2e-flaky"}
    : ${GINKGO_TEST_ARGS:="--ginkgo.skip=${GCE_DEFAULT_SKIP_TEST_REGEX} --ginkgo.focus=${GCE_FLAKY_TEST_REGEX}"}
    : ${KUBE_GCE_INSTANCE_PREFIX:="e2e-flaky"}
    : ${PROJECT:="k8s-jkns-e2e-gce-flaky"}
    ;;

  # Runs all non-flaky tests on GCE in parallel.
  kubernetes-e2e-gce-parallel)
    : ${E2E_CLUSTER_NAME:="jenkins-gce-e2e-parallel"}
    : ${E2E_NETWORK:="e2e-parallel"}
    : ${GINKGO_PARALLEL:="y"}
    : ${GINKGO_TEST_ARGS:="--ginkgo.skip=${GCE_DEFAULT_SKIP_TEST_REGEX}|${GCE_PARALLEL_SKIP_TEST_REGEX}|${GCE_PARALLEL_FLAKY_TEST_REGEX}"}
    : ${KUBE_GCE_INSTANCE_PREFIX:="e2e-test-parallel"}
    : ${PROJECT:="kubernetes-jenkins"}
    # Override GCE defaults.
    NUM_MINIONS="6"
    ;;

  # Runs the flaky tests on GCE in parallel.
  kubernetes-e2e-gce-parallel-flaky)
    : ${E2E_CLUSTER_NAME:="parallel-flaky"}
    : ${E2E_NETWORK:="e2e-parallel-flaky"}
    : ${GINKGO_PARALLEL:="y"}
    : ${GINKGO_TEST_ARGS:="--ginkgo.skip=${GCE_DEFAULT_SKIP_TEST_REGEX}|${GCE_PARALLEL_SKIP_TEST_REGEX} --ginkgo.focus=${GCE_PARALLEL_FLAKY_TEST_REGEX}"}
    : ${KUBE_GCE_INSTANCE_PREFIX:="parallel-flaky"}
    : ${PROJECT:="k8s-jkns-e2e-gce-prl-flaky"}
    # Override GCE defaults.
    NUM_MINIONS="4"
    ;;

  # Runs only the reboot tests on GCE.
  kubernetes-e2e-gce-reboot)
    : ${E2E_CLUSTER_NAME:="jenkins-gce-e2e-reboot"}
    : ${E2E_DOWN:="false"}
    : ${E2E_NETWORK:="e2e-reboot"}
    : ${GINKGO_TEST_ARGS:=" --ginkgo.focus=Reboot"}
    : ${KUBE_GCE_INSTANCE_PREFIX:="e2e-reboot"}
    : ${PROJECT:="kubernetes-jenkins"}
    ;;

  # Runs the performance/scalability tests on GCE. A larger cluster is used.
  kubernetes-e2e-gce-scalability)
    : ${E2E_CLUSTER_NAME:="jenkins-gce-e2e-scalability"}
    : ${E2E_NETWORK:="e2e-scalability"}
    : ${GINKGO_TEST_ARGS:="--ginkgo.focus=Performance\ssuite|should\sbe\sable\sto\shandle"}
    : ${KUBE_GCE_INSTANCE_PREFIX:="e2e-scalability"}
    : ${PROJECT:="kubernetes-jenkins"}
    # Override GCE defaults.
    MASTER_SIZE="n1-standard-4"
    MINION_SIZE="n1-standard-2"
    MINION_DISK_SIZE="50GB"
    NUM_MINIONS="100"
    ;;

  # Runs a subset of tests on GCE in parallel. Run against all pending PRs.
  kubernetes-pull-build-test-e2e-gce)
    : ${E2E_CLUSTER_NAME:="jenkins-pull-gce-e2e-${EXECUTOR_NUMBER}"}
    : ${E2E_NETWORK:="pull-e2e-parallel-${EXECUTOR_NUMBER}"}
    : ${GINKGO_PARALLEL:="y"}
    # This list should match the list in kubernetes-e2e-gce-parallel. It
    # currently also excludes a slow namespace test.
    : ${GINKGO_TEST_ARGS:="--ginkgo.skip=${GCE_DEFAULT_SKIP_TEST_REGEX}|${GCE_PARALLEL_SKIP_TEST_REGEX}|${GCE_PARALLEL_FLAKY_TEST_REGEX}"}
    : ${KUBE_GCE_INSTANCE_PREFIX:="pull-e2e-${EXECUTOR_NUMBER}"}
    : ${KUBE_GCS_STAGING_PATH_SUFFIX:="-${EXECUTOR_NUMBER}"}
    : ${PROJECT:="kubernetes-jenkins-pull"}
    # Override GCE defaults.
    MASTER_SIZE="n1-standard-1"
    MINION_SIZE="n1-standard-1"
    NUM_MINIONS="2"
    ;;
esac

# AWS variables
export KUBE_AWS_INSTANCE_PREFIX=${E2E_CLUSTER_NAME}
export KUBE_AWS_ZONE=${E2E_ZONE}

# GCE variables
export INSTANCE_PREFIX=${E2E_CLUSTER_NAME}
export KUBE_GCE_ZONE=${E2E_ZONE}
export KUBE_GCE_NETWORK=${E2E_NETWORK}
export KUBE_GCE_INSTANCE_PREFIX=${KUBE_GCE_INSTANCE_PREFIX:-}
export KUBE_GCS_STAGING_PATH_SUFFIX=${KUBE_GCS_STAGING_PATH_SUFFIX:-}

# GKE variables
export CLUSTER_NAME=${E2E_CLUSTER_NAME}
export ZONE=${E2E_ZONE}
export KUBE_GKE_NETWORK=${E2E_NETWORK}

# Shared cluster variables
export MASTER_SIZE=${MASTER_SIZE:-}
export MINION_SIZE=${MINION_SIZE:-}
export NUM_MINIONS=${NUM_MINIONS:-}
export PROJECT=${PROJECT:-}

export PATH=${PATH}:/usr/local/go/bin
export KUBE_SKIP_CONFIRMATIONS=y

# E2E Control Variables
export E2E_UP="${E2E_UP:-true}"
export E2E_TEST="${E2E_TEST:-true}"
export E2E_DOWN="${E2E_DOWN:-true}"
# Used by hack/ginkgo-e2e.sh to enable ginkgo's parallel test runner.
export GINKGO_PARALLEL=${GINKGO_PARALLEL:-}

echo "--------------------------------------------------------------------------------"
echo "Test Environment:"
printenv | sort
echo "--------------------------------------------------------------------------------"

if [[ "${E2E_UP,,}" == "true" ]]; then
    if [[ ${KUBE_RUN_FROM_OUTPUT:-} =~ ^[yY]$ ]]; then
        echo "Found KUBE_RUN_FROM_OUTPUT=y; will use binaries from _output"
        cp _output/release-tars/kubernetes*.tar.gz .
    else
        echo "Pulling binaries from GCS"
        if [[ $(find . | wc -l) != 1 ]]; then
            echo $PWD not empty, bailing!
            exit 1
        fi

        # Tell kube-up.sh to skip the update, it doesn't lock. An internal
        # gcloud bug can cause racing component updates to stomp on each
        # other.
        export KUBE_SKIP_UPDATE=y
        sudo flock -x -n /var/run/lock/gcloud-components.lock -c "gcloud components update -q" || true

        if [[ ! -z ${JENKINS_EXPLICIT_VERSION:-} ]]; then
            # Use an explicit pinned version like "ci/v0.10.0-101-g6c814c4" or
            # "release/v0.19.1"
            IFS='/' read -a varr <<< "${JENKINS_EXPLICIT_VERSION}"
            bucket="${varr[0]}"
            githash="${varr[1]}"
            echo "$bucket / $githash"
        elif [[ ${JENKINS_USE_SERVER_VERSION:-} =~ ^[yY]$ ]]; then
            # For GKE, we can get the server-specified version.
            # We'll pull our TARs for tests from the release bucket.
            bucket="release"

            # Get the latest available API version from the GKE apiserver.
            # Trim whitespace out of the error message. This gives us something
            # like: ERROR:(gcloud.alpha.container.clusters.create)ResponseError:
            #       code=400,message=cluster.cluster_api_versionmustbeoneof:
            #       0.15.0,0.16.0.
            # The command should error, so we throw an || true on there.
            create_args=(
              "this-wont-work"
              "--zone=us-central1-f"
            )
            if [[ ! -z "${DOGFOOD_GCLOUD:-}" ]]; then
              create_args+=("--cluster-version=0.0.0")
            else
              create_args+=("--cluster-api-version=0.0.0")
            fi
            msg=$(gcloud ${CMD_GROUP:-alpha} container clusters create "${create_args[@]}" 2>&1 \
                | tr -d '[[:space:]]') || true
            # Strip out everything before the final colon, which gives us just
            # the allowed versions; something like "0.15.0,0.16.0." or "0.16.0."
            msg=${msg##*:}
            # Take off the final period, which gives us just comma-separated
            # allowed versions; something like "0.15.0,0.16.0" or "0.16.0"
            msg=${msg%%\.}
            # Split the version string by comma and read into an array, using
            # the last element as the githash, which will be like "v0.16.0".
            IFS=',' read -a varr <<< "${msg}"
            githash="v${varr[${#varr[@]} - 1]}"
        else
            # The "ci" bucket is for builds like "v0.15.0-468-gfa648c1"
            bucket="ci"
            # The "latest" version picks the most recent "ci" or "release" build.
            version_file="latest"
            if [[ ${JENKINS_USE_RELEASE_TARS:-} =~ ^[yY]$ ]]; then
                # The "release" bucket is for builds like "v0.15.0"
                bucket="release"
                if [[ ${JENKINS_USE_STABLE:-} =~ ^[yY]$ ]]; then
                    # The "stable" version picks the most recent "release" build.
                    version_file="stable"
                fi
            fi
            githash=$(gsutil cat gs://kubernetes-release/${bucket}/${version_file}.txt)
        fi
        # At this point, we want to have the following vars set:
        # - bucket
        # - githash
        gsutil -m cp gs://kubernetes-release/${bucket}/${githash}/kubernetes.tar.gz gs://kubernetes-release/${bucket}/${githash}/kubernetes-test.tar.gz .
    fi

    if [[ ! "${CIRCLECI:-}" == "true" ]]; then
        # Copy GCE keys so we don't keep cycling them.
        # To set this up, you must know the <project>, <zone>, and <instance> that
        # on which your jenkins jobs are running. Then do:
        #
        # # Get into the instance.
        # $ gcloud compute ssh --project="<prj>" ssh --zone="<zone>" <instance>
        #
        # # Generate a key by ssh'ing into itself, then exit.
        # $ gcloud compute ssh --project="<prj>" ssh --zone="<zone>" <instance>
        # $ ^D
        #
        # # Copy the keys to the desired location, e.g. /var/lib/jenkins/gce_keys/
        # $ sudo mkdir -p /var/lib/jenkins/gce_keys/
        # $ sudo cp ~/.ssh/google_compute_engine /var/lib/jenkins/gce_keys/
        # $ sudo cp ~/.ssh/google_compute_engine.pub /var/lib/jenkins/gce_keys/
        #
        # Move the permissions to jenkins.
        # $ sudo chown -R jenkins /var/lib/jenkins/gce_keys/
        # $ sudo chgrp -R jenkins /var/lib/jenkins/gce_keys/
        if [[ "${KUBERNETES_PROVIDER}" == "aws" ]]; then
            echo "Skipping SSH key copying for AWS"
        else
            mkdir -p ${WORKSPACE}/.ssh/
            cp /var/lib/jenkins/gce_keys/google_compute_engine ${WORKSPACE}/.ssh/
            cp /var/lib/jenkins/gce_keys/google_compute_engine.pub ${WORKSPACE}/.ssh/
        fi
    fi

    md5sum kubernetes*.tar.gz
    tar -xzf kubernetes.tar.gz
    tar -xzf kubernetes-test.tar.gz

    # Set by GKE-CI to change the CLUSTER_API_VERSION to the git version
    if [[ ! -z ${E2E_SET_CLUSTER_API_VERSION:-} ]]; then
        export CLUSTER_API_VERSION=$(echo ${githash} | cut -c 2-)
    elif [[ ${JENKINS_USE_RELEASE_TARS:-} =~ ^[yY]$ ]]; then
        release=$(gsutil cat gs://kubernetes-release/release/${version_file}.txt | cut -c 2-)
        export CLUSTER_API_VERSION=${release}
    fi
fi

cd kubernetes

# Have cmd/e2e run by goe2e.sh generate JUnit report in ${WORKSPACE}/junit*.xml
ARTIFACTS=${WORKSPACE}/_artifacts
mkdir -p ${ARTIFACTS}
export E2E_REPORT_DIR=${ARTIFACTS}

### Set up ###
if [[ "${E2E_UP,,}" == "true" ]]; then
    go run ./hack/e2e.go ${E2E_OPT} -v --down
    go run ./hack/e2e.go ${E2E_OPT} -v --up
    go run ./hack/e2e.go -v --ctl="version --match-server-version=false"
fi

### Run tests ###
# Jenkins will look at the junit*.xml files for test failures, so don't exit
# with a nonzero error code if it was only tests that failed.
if [[ "${E2E_TEST,,}" == "true" ]]; then
    go run ./hack/e2e.go ${E2E_OPT} -v --test --test_args="${GINKGO_TEST_ARGS}" && exitcode=0 || exitcode=$?
    if [[ "${E2E_PUBLISH_GREEN_VERSION:-}" == "true" && ${exitcode} == 0 && -n ${githash:-} ]]; then
        echo "publish githash to ci/latest-green.txt: ${githash}"
        echo "${githash}" > ${WORKSPACE}/githash.txt
        gsutil cp ${WORKSPACE}/githash.txt gs://kubernetes-release/ci/latest-green.txt
    fi
fi

# TODO(zml): We have a bunch of legacy Jenkins configs that are
# expecting junit*.xml to be in ${WORKSPACE} root and it's Friday
# afternoon, so just put the junit report where it's expected.
# If link already exists, non-zero return code should not cause build to fail.
for junit in ${ARTIFACTS}/junit*.xml; do
  ln -s -f ${junit} ${WORKSPACE} || true
done

### Clean up ###
if [[ "${E2E_DOWN,,}" == "true" ]]; then
    # Sleep before deleting the cluster to give the controller manager time to
    # delete any cloudprovider resources still around from the last test.
    # This is calibrated to allow enough time for 3 attempts to delete the
    # resources. Each attempt is allocated 5 seconds for requests to the
    # cloudprovider plus the processingRetryInterval from servicecontroller.go
    # for the wait between attempts.
    sleep 30
    go run ./hack/e2e.go ${E2E_OPT} -v --down
fi
