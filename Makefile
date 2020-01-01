default: help
help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s %s\n\033[0m", $$1, $$2}'

# general
APP_NAME	 := hostdb-server
APP_PASSWORD := password
APP_RELEASE	 := hostdb
APP_TAG      := latest
DB_PASSWORD  := badpassword
DB_RELEASE   := mariadb
DB_USERNAME  := app
NAMESPACE	 := hostdb
WORK_DIR	 := $(shell pwd)

# k8s
HELM_VERSION    := 3.1.1
KUBECTL_VERSION := 1.17.0

# cert
PEM ?= $(WORK_DIR)/hostdb.pem
KEY ?= $(WORK_DIR)/hostdb.key

.PHONY: aws_creds
aws_creds: config_check ## create secret with aws access key
ifeq ($(strip $(AWS_ACCESS_KEY_ID)),)
	$(error value required (e.g. make aws_creds AWS_ACCESS_KEY_ID=keyid))
endif
ifeq ($(strip $(AWS_SECRET_ACCESS_KEY)),)
	$(error value required (e.g. make aws_creds AWS_SECRET_ACCESS_KEY=sekret))
endif
	-@kubectl create secret generic hostdb-collector-aws --namespace $(NAMESPACE) --from-literal=id='$(AWS_ACCESS_KEY_ID)' --from-literal=key='$(AWS_SECRET_ACCESS_KEY)'

.PHONY: clean
clean: config_check uninstall_all delete_app_creds delete_db_creds delete_ssl delete_namespace ## uninstalls any helm releases, db creds, app creds, ssl cert and namespace
	@rm -f $(WORK_DIR)/$(APP_NAME)/config.yaml

.PHONY: config_check
config_check: ## check for kube/config
ifeq (,$(wildcard $(HOME)/.kube/config))
	$(error missing kubeconfig)
endif

.PHONY: collector_creds
collector_creds: aws_creds oneview_creds openstack_creds ucs_creds vrops_creds ## create secrets with collector creds

.PHONY: db_creds
db_creds: config_check ## create secret with database creds
ifeq ($(strip $(DB_USERNAME)),)
	$(error Username required (e.g. make db_creds DB_USERNAME=username DB_PASSWORD=password))
endif
ifeq ($(strip $(DB_PASSWORD)),)
	$(error Password required (e.g. make db_creds DB_USERNAME=app DB_PASSWORD=sekret))
endif
	-@kubectl create secret generic $(APP_NAME)-db --namespace $(NAMESPACE) --from-literal=username='$(DB_USERNAME)' --from-literal=password='$(DB_PASSWORD)'

.PHONY: delete_db_creds
delete_db_creds: config_check ## delete db_creds kubernetes secret
	-@kubectl delete secret $(APP_NAME)-db --namespace $(NAMESPACE)

.PHONY: delete_app_creds
delete_app_creds: config_check ## delete app creds kubernetes secret
	-@kubectl delete secret $(APP_NAME)-admin --namespace $(NAMESPACE)

.PHONY: delete_namespace
delete_namespace: config_check ## delete kubernetes namespace
	-@kubectl delete namespace $(NAMESPACE)

.PHONY: delete_ssl
delete_ssl: config_check ## delete the SSL kubernetes secret
	-@kubectl delete secret hostdb-tls --namespace $(NAMESPACE)

.PHONY: everything
everything: namespace collector_creds db_creds password ssl install_all ## setup everything; k8s namespace, secrets, SSL cert, db instance, and the app itself.  consider setting NAMESPACE=pdxfixit1234

.PHONY: get_password
get_password: config_check ## get the hostdb-server-admin secret
	@kubectl get secret $(APP_NAME)-admin --namespace $(NAMESPACE) -o go-template='{{ .data.password }}' | base64 --decode

.PHONY: install
install: config_check ## install HostDB application
ifeq (,$(wildcard $(WORK_DIR)/$(APP_NAME)/config.yaml))
	cp $(WORK_DIR)/../$(APP_NAME)/config.yaml $(WORK_DIR)/$(APP_NAME)/config.yaml
endif
	@helm install --namespace $(NAMESPACE) $(APP_RELEASE) $(WORK_DIR)/$(APP_NAME)

.PHONY: install_all
install_all: ## install everything
	@$(MAKE) install_db
	sleep 30
	@$(MAKE) install

.PHONY: install_db
install_db: config_check ## install MariaDB cluster
	@helm install --namespace $(NAMESPACE) $(DB_RELEASE) $(WORK_DIR)/mariadb --set db.user="$(DB_USERNAME)",db.password="$(DB_PASSWORD)"

.PHONY: install_kubectl
install_kubectl: ## install kubectl
	curl -LO https://storage.googleapis.com/kubernetes-release/release/v$(KUBECTL_VERSION)/bin/linux/amd64/kubectl
	chmod +x ./kubectl
	sudo mv ./kubectl /usr/local/bin/kubectl

.PHONY: install_helm
install_helm: ## install helm
	curl -LO https://get.helm.sh/helm-v$(HELM_VERSION)-linux-amd64.tar.gz
	tar -zxvf helm-v$(HELM_VERSION)-linux-amd64.tar.gz
	sudo mv linux-amd64/helm /usr/local/bin/helm
	rm -rf linux-amd64

.PHONY: k8s_describe
k8s_describe: config_check ## run kubectl describe pod <hostdb>
	@kubectl describe pod --namespace $(NAMESPACE) -l "release=$(APP_RELEASE)"

# TODO: create a k8s_jobs that distills the status of the cronjobs

.PHONY: k8s_logs
k8s_logs: config_check ## show the k8s HostDB logs
	@kubectl logs $$(kubectl get pods --namespace $(NAMESPACE) -l "release=$(APP_RELEASE)" --no-headers -o custom-columns=:metadata.name) --namespace $(NAMESPACE) | grep -v "/health"

.PHONE: namespace
namespace: config_check ## create a k8s namespace
	-@kubectl create namespace $(NAMESPACE)

.PHONY: oneview_creds
oneview_creds: config_check ## create secret with oneview creds
ifeq ($(strip $(ONEVIEW_PASSWORD)),)
	$(error value required (e.g. make oneview_creds ONEVIEW_PASSWORD=sekret))
endif
	-@kubectl create secret generic hostdb-collector-oneview --namespace $(NAMESPACE) --from-literal=password='$(ONEVIEW_PASSWORD)'

.PHONY: openstack_creds
openstack_creds: config_check ## create secret with openstack creds
ifeq ($(strip $(OPENSTACK_PASSWORD)),)
	$(error value required (e.g. make openstack_creds OPENSTACK_PASSWORD=sekret))
endif
	-@kubectl create secret generic hostdb-collector-openstack --namespace $(NAMESPACE) --from-literal=password='$(OPENSTACK_PASSWORD)'

.PHONY: password
password: config_check ## create the hostdb-server-admin secret
ifeq ($(strip $(APP_PASSWORD)),)
	$(error Password required (e.g. make password APP_PASSWORD=sekret))
endif
	-@kubectl create secret generic $(APP_NAME)-admin --namespace $(NAMESPACE) --from-literal=password='$(APP_PASSWORD)'

.PHONY: replace_ssl
replace_ssl: split_ssl delete_ssl ssl ## replace the SSL certificate

.PHONY: split_ssl
split_ssl: ## split apart a pkcs12 PFX into PEM and KEY components
ifeq ($(strip ${PEM}),)
	$(error Certificate filepath required (e.g. PEM=hostdb.PEM))
endif
ifeq ($(strip ${KEY}),)
	$(error Private key filepath required (e.g. KEY=hostdb.key))
endif
ifeq ($(strip ${PFX}),)
	$(error Path to PFX required (e.g. PFX=hostdb.pfx))
endif
	openssl pkcs12 -in ${PFX} -out ${PEM} -nokeys
	openssl pkcs12 -in ${PFX} -out ${KEY} -nocerts -nodes

.PHONY: ssl
ssl: config_check ## create secret with SSL certificate
ifeq ($(strip ${PEM}),)
	$(error Certificate filepath required)
endif
ifeq ($(strip ${KEY}),)
	$(error Private key filepath required)
endif
	@if [[ ! $$(kubectl get namespaces | grep $(NAMESPACE)) ]]; then $(MAKE) namespace; fi
	-@kubectl create secret tls hostdb-tls --namespace $(NAMESPACE) --cert ${PEM} --key ${KEY}

.PHONY: ucs_creds
ucs_creds: config_check ## create secret with ucs creds
ifeq ($(strip $(UCS_PASSWORD)),)
	$(error value required (e.g. make ucs_creds UCS_PASSWORD=sekret))
endif
	-@kubectl create secret generic hostdb-collector-ucs --namespace $(NAMESPACE) --from-literal=password='$(UCS_PASSWORD)'

.PHONY: uninstall
uninstall: config_check ## uninstall HostDB application
	-@helm uninstall --namespace $(NAMESPACE) $(APP_RELEASE)

.PHONY: uninstall_all
uninstall_all: uninstall uninstall_db ## uninstall everything

.PHONY: uninstall_db
uninstall_db: config_check ## uninstall MariaDB cluster
	-@helm uninstall --namespace $(NAMESPACE) $(DB_RELEASE)
	-@kubectl delete pvc --namespace $(NAMESPACE) data-mariadb-master-0 data-mariadb-slave-0

.PHONY: upgrade
upgrade: config_check ## upgrade HostDB application (use APP_TAG=foo to specify a hostdb container tag)
ifeq (,$(wildcard $(WORK_DIR)/$(APP_NAME)/config.yaml))
	$(error hostdb-server/config.yaml missing)
endif
	@helm upgrade $(APP_RELEASE) $(WORK_DIR)/$(APP_NAME) --namespace $(NAMESPACE) --set-string image.tag=$(APP_TAG)

.PHONY: upgrade_db
upgrade_db: config_check ## upgrade MariaDB cluster
	@helm upgrade $(DB_RELEASE) $(WORK_DIR)/mariadb --namespace $(NAMESPACE)

.PHONY: vrops_creds
vrops_creds: config_check ## create secret with vrops creds
ifeq ($(strip $(VROPS_PASSWORD)),)
	$(error value required (e.g. make vrops_creds VROPS_PASSWORD=sekret))
endif
	-@kubectl create secret generic hostdb-collector-vrops --namespace $(NAMESPACE) --from-literal=password='$(VROPS_PASSWORD)'
