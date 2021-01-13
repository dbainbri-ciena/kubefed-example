CLUSTER_CONFIG ?= kind-cluster.cfg
LOCAL_KUBECONFIG ?= $(shell pwd)/kube-config.cfg
LOCAL_KUBECONTEXT ?= fed

help: ## print this message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make <target>\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "        %-15s %s\n", $$1, $$2 } /^##@/ { printf "\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

create-clusters: ## create the clusters that are part of the multi-cluster example
	kind get clusters | grep -qc fed || kind create cluster --quiet --kubeconfig $(LOCAL_KUBECONFIG) --config $(CLUSTER_CONFIG) --name fed
	kind get clusters | grep -qc metro || kind create cluster --quiet --kubeconfig $(LOCAL_KUBECONFIG) --config $(CLUSTER_CONFIG) --name metro
	kind get clusters | grep -qc edge1 || kind create cluster --quiet --kubeconfig $(LOCAL_KUBECONFIG) --config $(CLUSTER_CONFIG) --name edge1
	kind get clusters | grep -qc edge2 || kind create cluster --quiet --kubeconfig $(LOCAL_KUBECONFIG) --config $(CLUSTER_CONFIG) --name edge2

deploy: ## deploy kubefed to the multi-cluster controller
	kubectl --kubeconfig=$(LOCAL_KUBECONFIG) config use-context kind-fed
	(cd kubefed; PATH=$$PATH:$$(pwd)/bin make -e KIND_CLUSTER_NAME=fed -e KUBECONFIG=$(LOCAL_KUBECONFIG) NO_JOIN_HOST_CLUSTER=1 deploy.kind)

join: ## join all clusters to the multi-cluster controller
	PATH=$$PATH:$$(pwd)/kubefed/bin kubefedctl join fed --kubeconfig=$(LOCAL_KUBECONFIG) --cluster-context=kind-fed --host-cluster-context=kind-fed
	PATH=$$PATH:$$(pwd)/kubefed/bin kubefedctl join metro --kubeconfig=$(LOCAL_KUBECONFIG) --cluster-context=kind-metro --host-cluster-context=kind-fed
	PATH=$$PATH:$$(pwd)/kubefed/bin kubefedctl join edge1 --kubeconfig=$(LOCAL_KUBECONFIG) --cluster-context=kind-edge1 --host-cluster-context=kind-fed
	PATH=$$PATH:$$(pwd)/kubefed/bin kubefedctl join edge2 --kubeconfig=$(LOCAL_KUBECONFIG) --cluster-context=kind-edge2 --host-cluster-context=kind-fed
	# Required because Kind is being used
	PATH=$$PATH:$$(pwd)/kubefed/bin KUBECONFIG=$(LOCAL_KUBECONFIG) ./kubefed/scripts/fix-joined-kind-clusters.sh

verify: ## display the status of the multi-cluster example
	kubectl --kubeconfig=$(LOCAL_KUBECONFIG) --context=kind-fed --namespace kube-federation-system get kubefedcluster

env-msg:
	@{\
		echo "# To work with the multi-cluster controller you can";\
		echo "# execute the following commands in your shell:";\
		echo "";\
		echo "export KUBECONFIG=$(LOCAL_KUBECONFIG)";\
		echo "kubectl config use-context kind-fed";\
	}

kubefed: ## clone down the kubefed@v0.6.0 repository
	git clone --quiet --config advice.detachedHead=false  --depth 1 --branch v0.6.0 https://github.com/kubernetes-sigs/kubefed kubefed
	patch kubefed/scripts/fix-joined-kind-clusters.sh < hack/kubefed.patch
	(cd kubefed; PATH=$$PATH:$$(pwd)/bin ./scripts/download-binaries.sh && PATH=$$PATH:$$(pwd)/bin ./scripts/update-bindata.sh)

delete-clusters: ## destroy the clusters that are part of the multi-cluster example
	kind delete cluster --name fed
	kind delete cluster --name metro
	kind delete cluster --name edge1
	kind delete cluster --name edge2

up: create-clusters kubefed deploy join verify env-msg ## bring up all resources that are part of the example

down: delete-clusters ## bring down all the resources that are part of the example

clean: down ## bring down everything and delete all created file system artifacts
	rm -rf kube-config.cfg kubefed
