#!/bin/sh
# shellcheck disable=1090,2046,2086,1091
set -x
set -e
ramen_hack_directory_path_name=$(dirname $0)
. $ramen_hack_directory_path_name/exit_stack.sh
. $ramen_hack_directory_path_name/true_if_exit_status_and_stderr.sh
exit_stack_push unset -f true_if_exit_status_and_stderr
. $ramen_hack_directory_path_name/until_true_or_n.sh
exit_stack_push unset -f until_true_or_n
. $ramen_hack_directory_path_name/olm.sh
exit_stack_push olm_unset
exit_stack_push unset -v ramen_hack_directory_path_name
rook_ceph_deploy_spoke()
{
	PROFILE=$1 $ramen_hack_directory_path_name/minikube-rook-setup.sh create
}
exit_stack_push unset -f rook_ceph_deploy_spoke
rook_ceph_mirrors_deploy()
{
	PRIMARY_CLUSTER=$1 SECONDARY_CLUSTER=$2 $ramen_hack_directory_path_name/minikube-rook-mirror-setup.sh
	PRIMARY_CLUSTER=$2 SECONDARY_CLUSTER=$1 $ramen_hack_directory_path_name/minikube-rook-mirror-setup.sh
	PRIMARY_CLUSTER=$1 SECONDARY_CLUSTER=$2 $ramen_hack_directory_path_name/minikube-rook-mirror-test.sh
	PRIMARY_CLUSTER=$2 SECONDARY_CLUSTER=$1 $ramen_hack_directory_path_name/minikube-rook-mirror-test.sh
}
exit_stack_push unset -f rook_ceph_mirrors_deploy
rook_ceph_undeploy_spoke()
{
	PROFILE=$1 $ramen_hack_directory_path_name/minikube-rook-setup.sh delete
}
exit_stack_push unset -f rook_ceph_undeploy_spoke
minio_deploy()
{
	kubectl --context $1 apply -f $ramen_hack_directory_path_name/minio-deployment.yaml
	date
	kubectl --context $1 -n minio wait deployments/minio --for condition=available --timeout 60s
	date
}
exit_stack_push unset -f minio_deploy
minio_undeploy()
{
	kubectl --context $1 delete -f $ramen_hack_directory_path_name/minio-deployment.yaml
}
exit_stack_push unset -f minio_undeploy
minio_deploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do minio_deploy $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f minio_deploy_spokes
minio_undeploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do minio_undeploy $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f minio_undeploy_spokes
image_registry_port_number=5000
exit_stack_push unset -v image_registry_port_number
image_registry_address=localhost:$image_registry_port_number
exit_stack_push unset -v image_registry_address
image_registry_container_name=myregistry
exit_stack_push unset -v image_registry_container_name
image_registry_deploy_command="docker run -d --name $image_registry_container_name -p $image_registry_port_number:$image_registry_port_number docker.io/library/registry:2"
exit_stack_push unset -v image_registry_deploy_command
image_registry_undeploy_command="docker container stop $image_registry_container_name;docker container rm -v $image_registry_container_name"
exit_stack_push unset -v image_registry_undeploy_command
image_registry_deploy_localhost()
{
	$image_registry_deploy_command
}
exit_stack_push unset -f image_registry_deploy_localhost
image_registry_undeploy_localhost()
{
	eval $image_registry_undeploy_command
}
exit_stack_push unset -f image_registry_undeploy_localhost
image_registry_deploy_cluster()
{
#	minikube -p $cluster_name addons enable registry
	minikube -p $cluster_name ssh -- "$image_registry_deploy_command"
}
exit_stack_push unset -f image_registry_deploy_cluster
image_registry_undeploy_cluster()
{
#	minikube -p $cluster_name addons disable registry
	minikube -p $cluster_name ssh -- "$image_registry_undeploy_command"
}
exit_stack_push unset -f image_registry_undeploy_cluster
image_registry_deploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do image_registry_deploy_cluster $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f image_registry_deploy_spokes
image_registry_undeploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do image_registry_undeploy_cluster $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f image_registry_undeploy_spokes
image_archive()
{
	set -- $1 $(echo $1|tr : _)
	set -- $1 $HOME/.minikube/cache/images/$(dirname $2) $(basename $2)
	mkdir -p $2
	set -- $1 $2/$3
	# docker-archive doesn't support modifying existing images
	rm -f $2
	docker image save $1 -o $2
}
exit_stack_push unset -f image_archive
image_load_cluster()
{
	minikube -p $1 image load $2
}
exit_stack_push unset -f image_load_cluster
image_and_containers_exited_using_remove_cluster()
{
	minikube -p $1 ssh -- docker container rm \$\(docker container ls --all --filter ancestor=$2 --filter status=exited --quiet\)\;docker image rm $2
}
exit_stack_push unset -f image_and_containers_exited_using_remove_cluster
image_remove_cluster()
{
	minikube -p $1 ssh -- docker image rm $2
}
exit_stack_push unset -f image_remove_cluster
image_push_cluster()
{
	minikube -p $1 ssh -- docker image push $2
}
exit_stack_push unset -f image_push_cluster
ramen_image_directory_name=${ramen_image_directory_name-ramendr}
exit_stack_push unset -v ramen_image_directory_name
ramen_image_name_prefix=ramen
exit_stack_push unset -v ramen_image_name_prefix
ramen_image_tag=${ramen_image_tag-canary}
exit_stack_push unset -v ramen_image_tag
ramen_image_reference()
{
	echo ${1:+$1/}${ramen_image_directory_name:+$ramen_image_directory_name/}$ramen_image_name_prefix-$2:$ramen_image_tag
}
exit_stack_push unset -f ramen_image_reference
ramen_image_reference_registry_local()
{
	ramen_image_reference $image_registry_address $1
}
exit_stack_push unset -f ramen_image_reference_registry_local
ramen_manager_image_reference=$(ramen_image_reference "${ramen_manager_image_registry_address-localhost}" operator)
exit_stack_push unset -v ramen_manager_image_reference
ramen_manager_image_build()
{
# ENV variable to skip building ramen
#   - expects docker image named:
#     [$ramen_manager_image_registry_address/][$ramen_image_directory_name/]ramen-operator:$ramen_image_tag
	if test "${skip_ramen_build:-false}" != false; then
		return
	fi
	${ramen_hack_directory_path_name}/docker-uninstall.sh ${HOME}/.local/bin
	. ${ramen_hack_directory_path_name}/podman-docker-install.sh
	. ${ramen_hack_directory_path_name}/go-install.sh; go_install ${HOME}/.local; unset -f go_install
	make -C $ramen_directory_path_name docker-build IMG=$ramen_manager_image_reference
}
exit_stack_push unset -f ramen_manager_image_build
ramen_manager_image_archive()
{
	image_archive $ramen_manager_image_reference
}
exit_stack_push unset -f ramen_manager_image_archive
ramen_manager_image_load_cluster()
{
	image_load_cluster $1 $ramen_manager_image_reference
}
exit_stack_push unset -f ramen_manager_image_load_cluster
ramen_manager_image_remove_cluster()
{
	image_remove_cluster $1 $ramen_manager_image_reference
}
exit_stack_push unset -f ramen_manager_image_remove_cluster
ramen_bundle_image_reference()
{
	ramen_image_reference_registry_local $1-operator-bundle
}
exit_stack_push unset -f ramen_bundle_image_reference
ramen_bundle_image_spoke_reference=$(ramen_bundle_image_reference dr-cluster)
exit_stack_push unset -v ramen_bundle_image_spoke_reference
ramen_bundle_image_build()
{
	make -C $ramen_directory_path_name bundle-$1-build\
		IMG=$ramen_manager_image_reference\
		BUNDLE_IMG_DRCLUSTER=$ramen_bundle_image_spoke_reference\
		IMAGE_TAG=$ramen_image_tag\

}
exit_stack_push unset -f ramen_bundle_image_build
ramen_bundle_image_spoke_build()
{
	ramen_bundle_image_build dr-cluster
}
exit_stack_push unset -f ramen_bundle_image_spoke_build
ramen_bundle_image_spoke_push()
{
	podman push --tls-verify=false $ramen_bundle_image_spoke_reference
}
exit_stack_push unset -f ramen_bundle_image_spoke_push
ramen_bundle_image_spoke_archive()
{
	image_archive $ramen_bundle_image_spoke_reference
}
exit_stack_push unset -f ramen_bundle_image_spoke_archive
ramen_bundle_image_spoke_load_cluster()
{
	image_load_cluster $1 $ramen_bundle_image_spoke_reference
}
exit_stack_push unset -f ramen_bundle_image_spoke_load_cluster
ramen_bundle_image_spoke_remove_cluster()
{
	image_and_containers_exited_using_remove_cluster $1 $ramen_bundle_image_spoke_reference
}
exit_stack_push unset -f ramen_bundle_image_spoke_remove_cluster
ramen_bundle_image_spoke_push_cluster()
{
	image_push_cluster $1 $ramen_bundle_image_spoke_reference
}
exit_stack_push unset -f ramen_bundle_image_spoke_push_cluster
ramen_catalog_image_reference=$(ramen_image_reference_registry_local operator-catalog)
exit_stack_push unset -v ramen_catalog_image_reference
ramen_catalog_image_build()
{
	make -C $ramen_directory_path_name catalog-build\
		BUNDLE_IMGS=$1\
		BUNDLE_PULL_TOOL=none\ --skip-tls\
		CATALOG_IMG=$ramen_catalog_image_reference\

}
exit_stack_push unset -f ramen_catalog_image_build
ramen_catalog_image_spoke_build()
{
	ramen_catalog_image_build $ramen_bundle_image_spoke_reference
}
exit_stack_push unset -f ramen_catalog_image_spoke_build
ramen_catalog_image_archive()
{
	image_archive $ramen_catalog_image_reference
}
exit_stack_push unset -f ramen_catalog_image_archive
ramen_catalog_image_load_cluster()
{
	image_load_cluster $1 $ramen_catalog_image_reference
}
exit_stack_push unset -f ramen_catalog_image_load_cluster
ramen_catalog_image_remove_cluster()
{
	image_remove_cluster $1 $ramen_catalog_image_reference
}
exit_stack_push unset -f ramen_catalog_image_remove_cluster
ramen_catalog_image_push_cluster()
{
	image_push_cluster $1 $ramen_catalog_image_reference
}
exit_stack_push unset -f ramen_catalog_image_push_cluster
ramen_images_build()
{
	ramen_manager_image_build
	ramen_bundle_image_spoke_build
	image_registry_deploy_localhost
	exit_stack_push image_registry_undeploy_localhost
	ramen_bundle_image_spoke_push
	ramen_catalog_image_spoke_build
	exit_stack_pop
}
exit_stack_push unset -f ramen_images_build
ramen_images_archive()
{
	ramen_manager_image_archive
	ramen_bundle_image_spoke_archive
	ramen_catalog_image_archive
}
exit_stack_push unset -f ramen_images_archive
ramen_images_build_and_archive()
{
	ramen_images_build
	ramen_images_archive
}
exit_stack_push unset -f ramen_images_build_and_archive
ramen_images_load_spoke()
{
	ramen_manager_image_load_cluster $1
	ramen_bundle_image_spoke_load_cluster $1
	ramen_catalog_image_load_cluster $1
}
exit_stack_push unset -f ramen_images_load_spoke
ramen_images_push_spoke()
{
	ramen_bundle_image_spoke_push_cluster $1
	ramen_catalog_image_push_cluster $1
}
exit_stack_push unset -f ramen_images_push_spoke
ramen_images_deploy_spoke()
{
	ramen_images_load_spoke	$1
	image_registry_deploy_cluster $1
	ramen_images_push_spoke	$1
}
exit_stack_push unset -f ramen_images_deploy_spoke
ramen_images_undeploy_spoke()
{
	ramen_catalog_image_remove_cluster $1
	ramen_bundle_image_spoke_remove_cluster $1
	ramen_manager_image_remove_cluster $1
}
exit_stack_push unset -f ramen_images_undeploy_spoke
ramen_images_deploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do ramen_images_deploy_spoke $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f ramen_images_deploy_spokes
ramen_images_undeploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do ramen_images_undeploy_spoke $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f ramen_images_undeploy_spokes
kube_context_set()
{
	exit_stack_push kubectl config use-context $(kubectl config current-context)
	kubectl config use-context ${1}
}
exit_stack_push unset -f kube_context_set
kube_context_set_undo()
{
	exit_stack_pop
}
exit_stack_push unset -f kube_context_set_undo
ramen_deploy_hub_or_spoke()
{
	ramen_manager_image_load_cluster $1
	. $ramen_hack_directory_path_name/go-install.sh; go_install $HOME/.local; unset -f go_install
	kube_context_set $1
	make -C $ramen_directory_path_name deploy-$2 IMG=$ramen_manager_image_reference
	kube_context_set_undo
	kubectl --context $1 -n ramen-system wait deployments --all --for condition=available --timeout 60s
	ramen_config_deploy_hub_or_spoke $1 $2
}
exit_stack_push unset -f ramen_deploy_hub_or_spoke
ramen_config_deploy_hub_or_spoke()
{
	# Add s3 profile to ramen config
	cat <<-EOF | kubectl --context $1 apply -f -
	apiVersion: v1
	kind: Secret
	metadata:
	  name: s3secret
	  namespace: ramen-system
	stringData:
	  AWS_ACCESS_KEY_ID: "minio"
	  AWS_SECRET_ACCESS_KEY: "minio123"
	EOF
	ramen_config_map_name=ramen-$2-operator-config
	until_true_or_n 90 kubectl --context $1 -n ramen-system get configmap $ramen_config_map_name
	cp $ramen_directory_path_name/config/$2/manager/ramen_manager_config.yaml /tmp/ramen_manager_config.yaml
	set -- $1 $2 $spoke_cluster_names
	cat <<-EOF >>/tmp/ramen_manager_config.yaml
	s3StoreProfiles:
	- s3ProfileName: minio-on-$3
	  s3Bucket: bucket
	  s3CompatibleEndpoint: $(minikube --profile $3 -n minio service --url minio)
	  s3Region: us-east-1
	  s3SecretRef:
	    name: s3secret
	    namespace: ramen-system
	- s3ProfileName: minio-on-$4
	  s3Bucket: bucket
	  s3CompatibleEndpoint: $(minikube --profile $4 -n minio service --url minio)
	  s3Region: us-west-1
	  s3SecretRef:
	    name: s3secret
	    namespace: ramen-system
	drClusterOperator:
	  namespaceName: ramen-system
	  catalogSourceImageName: $ramen_catalog_image_reference
	EOF

	kubectl --context $1 -n ramen-system\
		create configmap ${ramen_config_map_name}\
		--from-file=/tmp/ramen_manager_config.yaml -o yaml --dry-run=client |
		kubectl --context $1 -n ramen-system replace -f -
	unset -v ramen_config_map_name
}
exit_stack_push unset -f ramen_config_deploy_hub_or_spoke
ramen_config_deploy_spoke()
{
	ramen_config_deploy_hub_or_spoke $1 dr-cluster
}
exit_stack_push unset -f ramen_config_deploy_hub_or_spoke
ramen_deploy_hub()
{
	ramen_deploy_hub_or_spoke $hub_cluster_name hub
	ramen_samples_channel_and_drpolicy_deploy
}
exit_stack_push unset -f ramen_deploy_hub
ramen_deploy_spoke()
{
	ramen_deploy_hub_or_spoke $1 dr-cluster
}
exit_stack_push unset -f ramen_deploy_spoke
ramen_undeploy_hub_or_spoke()
{
	kube_context_set $1
	make -C $ramen_directory_path_name undeploy-$2
	# Error from server (NotFound): error when deleting "STDIN": namespaces "ramen-system" not found
	# Error from server (NotFound): error when deleting "STDIN": serviceaccounts "ramen-hub-operator" not found
	# Error from server (NotFound): error when deleting "STDIN": roles.rbac.authorization.k8s.io "ramen-hub-leader-election-role" not found
	# Error from server (NotFound): error when deleting "STDIN": rolebindings.rbac.authorization.k8s.io "ramen-hub-leader-election-rolebinding" not found
	# Error from server (NotFound): error when deleting "STDIN": configmaps "ramen-hub-operator-config" not found
	# Error from server (NotFound): error when deleting "STDIN": services "ramen-hub-operator-metrics-service" not found
	# Error from server (NotFound): error when deleting "STDIN": deployments.apps "ramen-hub-operator" not found
	# Makefile:149: recipe for target 'undeploy-hub' failed
	# make: *** [undeploy-hub] Error 1
	kube_context_set_undo
	ramen_manager_image_remove_cluster $1
	# Error: No such image: $ramen_manager_image_reference
	# ssh: Process exited with status 1
}
exit_stack_push unset -f ramen_undeploy_hub_or_spoke
ramen_undeploy_hub()
{
	ramen_samples_channel_and_drpolicy_undeploy
	set +e # TODO remove once each resource is owned by hub or spoke but not both
	ramen_undeploy_hub_or_spoke $hub_cluster_name hub
	set -e
}
exit_stack_push unset -f ramen_undeploy_hub
ramen_undeploy_spoke()
{
	ramen_undeploy_hub_or_spoke $1 dr-cluster
}
exit_stack_push unset -f ramen_undeploy_spoke
ramen_deploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do ramen_deploy_spoke $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f ramen_deploy_spokes
ramen_undeploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do ramen_undeploy_spoke $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f ramen_undeploy_spokes
olm_deploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do olm_deploy $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f olm_deploy_spokes
olm_undeploy_spokes()
{
	for cluster_name in $spoke_cluster_names; do olm_undeploy $cluster_name; done; unset -v cluster_name
}
exit_stack_push unset -f olm_undeploy_spokes
ocm_ramen_samples_git_ref=${ocm_ramen_samples_git_ref-main}
ocm_ramen_samples_git_path=${ocm_ramen_samples_git_path-ramendr}
exit_stack_push unset -v ocm_ramen_samples_git_ref
exit_stack_push unset -v ocm_ramen_samples_git_path
ramen_samples_channel_and_drpolicy_deploy()
{
	ramen_images_deploy_spokes
	set -- ocm-ramen-samples/subscriptions
	set -- /tmp/$USER/$1 $1 $spoke_cluster_names
	mkdir -p $1
	cat <<-a >$1/kustomization.yaml
	resources:
	  - https://github.com/$ocm_ramen_samples_git_path/$2?ref=$ocm_ramen_samples_git_ref
	patchesJson6902:
	  - target:
	      group: ramendr.openshift.io
	      version: v1alpha1
	      kind: DRPolicy
	      name: dr-policy
	    patch: |-
	      - op: replace
	        path: /spec/drClusterSet
	        value:
	          - name: $3
	            s3ProfileName: minio-on-$3
	          - name: $4
	            s3ProfileName: minio-on-$4
	a
	kubectl --context $hub_cluster_name apply -k $1
	for cluster_name in $spoke_cluster_names; do
		until_true_or_n 300 kubectl --context $cluster_name -n ramen-system wait deployments ramen-dr-cluster-operator --for condition=available --timeout 0
		image_registry_undeploy_cluster $cluster_name
		ramen_config_deploy_spoke $cluster_name
	done; unset -v cluster_name
	kubectl --context $hub_cluster_name -n ramen-samples get channels/ramen-gitops
}
exit_stack_push unset -f ramen_samples_channel_and_drpolicy_deploy
ramen_samples_channel_and_drpolicy_undeploy()
{
	date
	kubectl --context $hub_cluster_name delete -k https://github.com/$ocm_ramen_samples_git_path/ocm-ramen-samples/subscriptions?ref=$ocm_ramen_samples_git_ref
	date
	for cluster_name in $spoke_cluster_names; do
		true_if_exit_status_and_stderr 1 'error: no matching resources found' \
		kubectl --context $cluster_name -n ramen-system wait deployments ramen-dr-cluster-operator --for delete
		# TODO remove once drpolicy controller does this
		kubectl --context $cluster_name delete\
			customresourcedefinitions.apiextensions.k8s.io/volumereplicationgroups.ramendr.openshift.io\

		ramen_images_undeploy_spoke $cluster_name
	done; unset -v cluster_name
}
exit_stack_push unset -f ramen_samples_channel_and_drpolicy_undeploy
application_sample_place()
{
	set -- $1 "$2" $3 $4 "$5" $6 ocm-ramen-samples subscriptions/busybox
	set -- $1 "$2" $3 https://$4/$ocm_ramen_samples_git_path/$7$5/$8$6 /tmp/$USER/$7/$8
	mkdir -p $5
	cat <<-a >$5/kustomization.yaml
	resources:
	  - $4
	namespace: busybox-sample
	patchesJson6902:
	  - target:
	      group: ramendr.openshift.io
	      version: v1alpha1
	      kind: DRPlacementControl
	      name: busybox-drpc
	    patch: |-
	      - op: add
	        path: /spec/action
	        value: $2
	      - op: add
	        path: /spec/$3Cluster
	        value: $1
	a
	kubectl --context $hub_cluster_name apply -k $5
	until_true_or_n 90 eval test \"\$\(kubectl --context ${hub_cluster_name} -n busybox-sample get subscriptions/busybox-sub -ojsonpath='{.status.phase}'\)\" = Propagated
	until_true_or_n 30 eval test \"\$\(kubectl --context $hub_cluster_name -n busybox-sample get placementrules/busybox-placement -ojsonpath='{.status.decisions[].clusterName}'\)\" = $1
	if test ${1} = ${hub_cluster_name}; then
		subscription_name_suffix=-local
	else
		unset -v subscription_name_suffix
	fi
	until_true_or_n 30 eval test \"\$\(kubectl --context ${1} -n busybox-sample get subscriptions/busybox-sub${subscription_name_suffix} -ojsonpath='{.status.phase}'\)\" = Subscribed
	unset -v subscription_name_suffix
	until_true_or_n 60 kubectl --context ${1} -n busybox-sample wait pods/busybox --for condition=ready --timeout 0
	until_true_or_n 30 eval test \"\$\(kubectl --context ${1} -n busybox-sample get persistentvolumeclaims/busybox-pvc -ojsonpath='{.status.phase}'\)\" = Bound
	date
	until_true_or_n 90 kubectl --context ${1} -n busybox-sample get volumereplicationgroups/busybox-drpc
	date
}
exit_stack_push unset -f application_sample_place
application_sample_undeploy_wait_and_namespace_undeploy()
{
	date
	true_if_exit_status_and_stderr 1 'error: no matching resources found' \
	kubectl --context ${1} -n busybox-sample wait pods/busybox --for delete --timeout 2m
	date
	true_if_exit_status_and_stderr 1 'error: no matching resources found' \
	kubectl --context ${1} -n busybox-sample wait volumereplicationgroups/busybox-drpc --for delete
	date
	true_if_exit_status_and_stderr 1 'error: no matching resources found' \
	kubectl --context $1 -n busybox-sample wait persistentvolumeclaims/busybox-pvc --for delete
	# TODO remove once drplacement controller does this
	kubectl --context $hub_cluster_name -n $1 delete manifestworks/busybox-drpc-busybox-sample-ns-mw #--ignore-not-found
	true_if_exit_status_and_stderr 1 'error: no matching resources found' \
	kubectl --context $1 wait namespace/busybox-sample --for delete
}
exit_stack_push unset -f application_sample_undeploy_wait_and_namespace_undeploy
application_sample_deploy()
{
	set -- $spoke_cluster_names
	application_sample_place $1 '' preferred github.com '' \?ref=$ocm_ramen_samples_git_ref
}
exit_stack_push unset -f application_sample_deploy
application_sample_failover()
{
	set -- $spoke_cluster_names
	application_sample_place $2 Failover failover raw.githubusercontent.com /$ocm_ramen_samples_git_ref /drpc.yaml
	application_sample_undeploy_wait_and_namespace_undeploy $1
}
exit_stack_push unset -f application_sample_failover
application_sample_relocate()
{
	set -- $spoke_cluster_names
	application_sample_place $1 Relocate preferred raw.githubusercontent.com /$ocm_ramen_samples_git_ref /drpc.yaml
	application_sample_undeploy_wait_and_namespace_undeploy $2
}
exit_stack_push unset -f application_sample_relocate
application_sample_undeploy()
{
	set -- $(kubectl --context ${hub_cluster_name} -n busybox-sample get placementrules/busybox-placement -ojsonpath='{.status.decisions[].clusterName}')
	kubectl --context $hub_cluster_name delete -k https://github.com/$ocm_ramen_samples_git_path/ocm-ramen-samples/subscriptions/busybox?ref=$ocm_ramen_samples_git_ref
	application_sample_undeploy_wait_and_namespace_undeploy $1
}
exit_stack_push unset -f application_sample_undeploy
ramen_directory_path_name=${ramen_hack_directory_path_name}/..
exit_stack_push unset -v ramen_directory_path_name
hub_cluster_name=${hub_cluster_name:-hub}
exit_stack_push unset -v hub_cluster_name
spoke_cluster_names=${spoke_cluster_names:-cluster1\ $hub_cluster_name}
exit_stack_push unset -v spoke_cluster_names
rook_ceph_deploy()
{
	# volumes required: mirror sources, mirror targets, minio backend
	for cluster_name in $spoke_cluster_names; do
		rook_ceph_deploy_spoke $cluster_name
	done; unset -v cluster_name
	rook_ceph_mirrors_deploy $spoke_cluster_names
}
exit_stack_push unset -f rook_ceph_deploy
rook_ceph_undeploy()
{
	for cluster_name in $spoke_cluster_names; do
		rook_ceph_undeploy_spoke $cluster_name
	done; unset -v cluster_name
}
exit_stack_push unset -f rook_ceph_undeploy
rook_ceph_csi_image_canary_deploy()
{
	for cluster_name in $spoke_cluster_names; do
		minikube -p $cluster_name ssh -- docker image pull quay.io/cephcsi/cephcsi:canary
		kubectl --context $cluster_name -n rook-ceph rollout restart deploy/csi-rbdplugin-provisioner
	done; unset -v cluster_name
}
exit_stack_push unset -f rook_ceph_csi_image_canary_deploy
rook_ceph_volume_replication_image_latest_deploy()
{
	for cluster_name in $spoke_cluster_names; do
		minikube -p $cluster_name ssh -- docker image pull quay.io/csiaddons/volumereplication-operator:latest
		kubectl --context $cluster_name -n rook-ceph rollout restart deploy/csi-rbdplugin-provisioner
	done; unset -v cluster_name
}
exit_stack_push unset -f rook_ceph_volume_replication_image_latest_deploy
ramen_deploy()
{
	ramen_deploy_hub
}
exit_stack_push unset -f ramen_deploy
ramen_undeploy()
{
	ramen_undeploy_hub
}
exit_stack_push unset -f ramen_undeploy
deploy()
{
	hub_cluster_name=$hub_cluster_name spoke_cluster_names=$spoke_cluster_names $ramen_hack_directory_path_name/ocm-minikube.sh
	rook_ceph_deploy
	minio_deploy_spokes
	ramen_images_build_and_archive
	olm_deploy_spokes
	ramen_deploy
}
exit_stack_push unset -f deploy
undeploy()
{
	ramen_undeploy
	olm_undeploy_spokes
	minio_undeploy_spokes
	rook_ceph_undeploy
}
exit_stack_push unset -f undeploy
exit_stack_push unset -v command
for command in "${@:-deploy}"; do
	$command
done
