#!/usr/bin/env bash

# Copyright 2020 PingCAP, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# See the License for the specific language governing permissions and
# limitations under the License.

if [ -z "$ROOT" ]; then
    echo "error: ROOT should be initialized"
    exit 1
fi

OS=$(go env GOOS)
ARCH=$(go env GOARCH)
OUTPUT=${ROOT}/output
OUTPUT_BIN=${OUTPUT}/bin
TERRAFORM_BIN=${OUTPUT_BIN}/terraform
TERRAFORM_VERSION=${TERRAFORM_VERSION:-0.12.12}
KUBECTL_VERSION=${KUBECTL_VERSION:-1.22.17}
KUBECTL_BIN=$OUTPUT_BIN/kubectl
HELM_BIN=$OUTPUT_BIN/helm
DOCS_BIN=$OUTPUT_BIN/gen-crd-api-reference-docs
CFSSL_BIN=$OUTPUT_BIN/cfssl
CFSSLJSON_BIN=$OUTPUT_BIN/cfssljson
JQ_BIN=$OUTPUT_BIN/jq
CFSSL_VERSION=${CFSSL_VERSION:-1.2}
K8S_VERSION=${K8S_VERSION:-0.22.17}
JQ_VERSION=${JQ_VERSION:-1.6}
HELM_VERSION=${HELM_VERSION:-3.11.0}
KIND_VERSION=${KIND_VERSION:-0.11.1}
KIND_BIN=$OUTPUT_BIN/kind
KUBETEST2_VERSION=v0.1.0
KUBETEST2_BIN=$OUTPUT_BIN/kubetest2
AWS_K8S_TESTER_VERSION=v1.1.5
AWS_K8S_TESTER_BIN=$OUTPUT_BIN/aws-k8s-tester
GO_SUBMODULES=(
    "github.com/pingcap/tidb-operator/pkg/apis"
    "github.com/pingcap/tidb-operator/pkg/client"
)
GO_SUBMODULE_DIRS=(
    "pkg/apis"
    "pkg/client"
)

test -d "$OUTPUT_BIN" || mkdir -p "$OUTPUT_BIN"

function hack::verify_cfssl() {
    if test -x "$CFSSL_BIN"; then
        local v_cfssl=$($CFSSL_BIN version | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+')
        local v_jq=$($JQ_BIN --version | grep -o -E '[0-9]+\.[0-9]+')
        echo "info: cfssl/cfssljson: ${v_cfssl}"
        echo "info: jq: ${v_jq}"
        [[ "$v_cfssl" == "$CFSSL_VERSION.0" && "$v_jq" == "$JQ_VERSION" ]]
        return
    fi
    return 1
}

function hack::install_cfssl() {
    echo "info: Installing cfssl/cfssljson R${CFSSL_VERSION}"
    tmpfile=$(mktemp)
    trap "test -f $tmpfile && rm $tmpfile" RETURN

    curl --retry 10 -L -o $tmpfile https://pkg.cfssl.org/R${CFSSL_VERSION}/cfssl_linux-amd64
    mv $tmpfile $CFSSL_BIN
    chmod +x $CFSSL_BIN

    curl --retry 10 -L -o $tmpfile https://pkg.cfssl.org/R${CFSSL_VERSION}/cfssljson_linux-amd64
    mv $tmpfile $CFSSLJSON_BIN
    chmod +x $CFSSLJSON_BIN

    curl --retry 10 -L -o $tmpfile https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    mv $tmpfile $JQ_BIN
    chmod +x $JQ_BIN
}

function hack::ensure_cfssl() {
    if ! hack::verify_cfssl; then
        hack::install_cfssl
    else
        echo "info: cfssl tools already installed, skip"
    fi
}

function hack::verify_terraform() {
    if test -x "$TERRAFORM_BIN"; then
        local v=$($TERRAFORM_BIN version | awk '/^Terraform v.*/ { print $2 }' | sed 's#^v##')
        [[ "$v" == "$TERRAFORM_VERSION" ]]
        return
    fi
    return 1
}

function hack::install_terraform() {
    echo "Installing terraform v$TERRAFORM_VERSION..."
    local tmpdir=$(mktemp -d)
    trap "test -d $tmpdir && rm -r $tmpdir" RETURN
    pushd $tmpdir > /dev/null
    wget https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip
    unzip terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip
    mv terraform $TERRAFORM_BIN
    popd > /dev/null
    chmod +x $TERRAFORM_BIN
}

function hack::ensure_terraform() {
    if ! hack::verify_terraform; then
        hack::install_terraform
    fi
}

function hack::verify_kubectl() {
    if test -x "$KUBECTL_BIN"; then
        [[ "$($KUBECTL_BIN version --client --short | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+')" == "$KUBECTL_VERSION" ]]
        return
    fi
    return 1
}

function hack::ensure_kubectl() {
    if hack::verify_kubectl; then
        return 0
    fi
    echo "Installing kubectl v$KUBECTL_VERSION..."
    tmpfile=$(mktemp)
    trap "test -f $tmpfile && rm $tmpfile" RETURN
    curl --retry 10 -L -o $tmpfile https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl
    mv $tmpfile $KUBECTL_BIN
    chmod +x $KUBECTL_BIN
}

function hack::verify_helm() {
    if test -x "$HELM_BIN"; then
        local v=$($HELM_BIN version --short --client | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+')
        [[ "$v" == "$HELM_VERSION" ]]
        return
    fi
    return 1
}

function hack::ensure_helm() {
    if hack::verify_helm; then
        return 0
    fi
    echo "Installing helm ${HELM_VERSION}..."
    local HELM_URL=https://get.helm.sh/helm-v${HELM_VERSION}-${OS}-${ARCH}.tar.gz
    echo "Installing helm from tarball: ${HELM_URL} ..."
    curl --fail --retry 3 -L -s "$HELM_URL" | tar --strip-components 1 -C $OUTPUT_BIN -zxf - ${OS}-${ARCH}/helm
}

function hack::verify_kind() {
    if test -x "$KIND_BIN"; then
        [[ "$($KIND_BIN --version 2>&1 | cut -d ' ' -f 3)" == "$KIND_VERSION" ]]
        return
    fi
    return 1
}

function hack::ensure_kind() {
    if hack::verify_kind; then
        return 0
    fi
    echo "Installing kind v$KIND_VERSION..."
    tmpfile=$(mktemp)
    trap "test -f $tmpfile && rm $tmpfile" RETURN
    curl --retry 10 -L -o $tmpfile https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/kind-${OS}-${ARCH}
    mv $tmpfile $KIND_BIN
    chmod +x $KIND_BIN
}

# hack::version_ge "$v1" "$v2" checks whether "v1" is greater or equal to "v2"
function hack::version_ge() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# Usage:
#
#	hack::wait_for_success 120 5 "cmd arg1 arg2 ... argn"
#
# Returns 0 if the shell command get output, 1 otherwise.
# From https://github.com/kubernetes/kubernetes/blob/v1.17.0/hack/lib/util.sh#L70
function hack::wait_for_success() {
    local wait_time="$1"
    local sleep_time="$2"
    local cmd="$3"
    while [ "$wait_time" -gt 0 ]; do
        if eval "$cmd"; then
            return 0
        else
            sleep "$sleep_time"
            wait_time=$((wait_time-sleep_time))
        fi
    done
    return 1
}

#
# Concatenates the elements with a separator between them.
#
# Usage: hack::join ',' a b c
#
function hack::join() {
	local IFS="$1"
	shift
	echo "$*"
}

function hack::__verify_kubetest2() {
    local n="$1"
    local v="$2"
    if test -x "$OUTPUT_BIN/$n"; then
        local tmpv=$($OUTPUT_BIN/$n --version 2>&1 | awk '{print $2}')
        [[ "$tmpv" == "$v" ]]
        return
    fi
    return 1
}

function hack::__ensure_kubetest2() {
    local n="$1"
    if hack::__verify_kubetest2 $n $KUBETEST2_VERSION; then
        return 0
    fi
    local tmpfile=$(mktemp)
    trap "test -f $tmpfile && rm $tmpfile" RETURN
    echo "info: downloading $n $KUBETEST2_VERSION"
    curl --retry 10 -L -o - https://github.com/cofyc/kubetest2-release/releases/download/$KUBETEST2_VERSION/$n-$OS-$ARCH.gz | gunzip > $tmpfile
    mv $tmpfile $OUTPUT_BIN/$n
    chmod +x $OUTPUT_BIN/$n
}

function hack::ensure_kubetest2() {
    hack::__ensure_kubetest2 kubetest2
    hack::__ensure_kubetest2 kubetest2-gke
    hack::__ensure_kubetest2 kubetest2-kind
    hack::__ensure_kubetest2 kubetest2-eks
}

function hack::verify_aws_k8s_tester() {
    if test -x $AWS_K8S_TESTER_BIN; then
        [[ "$($AWS_K8S_TESTER_BIN version | jq '."release-version"' -r)" == "$AWS_K8S_TESTER_VERSION" ]]
        return
    fi
    return 1
}

function hack::ensure_aws_k8s_tester() {
    if hack::verify_aws_k8s_tester; then
        return
    fi
	local DOWNLOAD_URL=https://github.com/aws/aws-k8s-tester/releases/download
    local tmpfile=$(mktemp)
    trap "test -f $tmpfile && rm $tmpfile" RETURN
    curl --retry 10 -L -o $tmpfile https://github.com/aws/aws-k8s-tester/releases/download/$AWS_K8S_TESTER_VERSION/aws-k8s-tester-$AWS_K8S_TESTER_VERSION-$OS-$ARCH
	mv $tmpfile $AWS_K8S_TESTER_BIN
	chmod +x $AWS_K8S_TESTER_BIN
}

function hack::ensure_gen_crd_api_references_docs() {
    echo "Installing gen_crd_api_references_docs..."
    GOBIN=$OUTPUT_BIN go install github.com/xhebox/gen-crd-api-reference-docs@a8a3b01e858f0de8bc8f9419d210da4334929e2d
}

function hack::ensure_misspell() {
    echo "Installing misspell..."
    GOBIN=$OUTPUT_BIN go install github.com/client9/misspell/cmd/misspell@v0.3.4
}

function hack::ensure_golangci_lint() {
  echo "Installing golangci_lint..."
  GOBIN=$OUTPUT_BIN go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.50.1
}

function hack::ensure_controller_gen() {
    echo "Installing controller_gen..."
    GOBIN=$OUTPUT_BIN go install sigs.k8s.io/controller-tools/cmd/controller-gen@v0.6.2
}

function hack::ensure_goimports() {
    echo "Installing goimports..."
    GOBIN=$OUTPUT_BIN go install golang.org/x/tools/cmd/goimports@v0.1.12
}

function hack::ensure_codegen() {
    echo "Installing codegen..."
    GOBIN=$OUTPUT_BIN go install k8s.io/code-generator/cmd/{defaulter-gen,client-gen,lister-gen,informer-gen,deepcopy-gen}@v$K8S_VERSION
}

function hack::ensure_openapi() {
    echo "Installing openpi_gen..."
    GOBIN=$OUTPUT_BIN go install k8s.io/code-generator/cmd/openapi-gen@v$K8S_VERSION
}

function version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }
