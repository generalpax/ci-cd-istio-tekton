# CI/CD on OpenShift with Tekton and Istio
## Introduction
OpenShift is a powerful and secure platform for deploying containerized workloads. Combined with OpenShift Service Mesh and OpenShift Pipelines, it becomes a platform for enterprise agility, enabling continuous integration and continuous deployment via pipelines that build and push new code into managed canary rollouts. <br><br>With OpenShift Service Mesh, based on the Istio project; OpenShift Pipelines, based on Tekton; and Argo CD, a project that enables a GitOps approach to application management, developers can push changes to source code and within minutes see those changes deployed to a small subset of users. This iterative approach to software development means enterprises can rapidly and safely build new features and deploy them to end-users.

## Architecture

This GitHub repository provides a demonstration of how a Tekton pipeline can be used in tandem with a service mesh to deploy workloads automatically with a canary rollout.

![pipeline-flow](images/flow-tekton-istio.png)

### Installation

#### Prereqs
- OpenShift 4.x
- OpenShift Pipelines Operator
- Argo CD Operator
- Jaeger
- Kiali
- Istio
#### Install and configure Istio on OCP

Since mesh federation is not supported on OSSM (maistra.io) we use plain istio platform: 

[Platform Setup](https://istio.io/latest/docs/setup/platform-setup/openshift/)

and install dependencies:

```sh
oc apply -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/addons/grafana.yaml -n istio-system
oc apply -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/addons/prometheus.yaml -n istio-system
```
#### Install and configure ArgoCD

Deploy the OCP Argo CD Operator to Openshift-Operators namespace and install default instance in the same namespace. 

[Installation steps for Argo CD Operator](https://argocd-operator.readthedocs.io/en/latest/install/openshift/)

Don't miss the ClusterRoleBinding:

```sh
oc adm policy add-cluster-role-to-user cluster-admin -z cicd-bookinfo-argo-argocd-application-controller -n cicd-bookinfo
```

Deploy github repo credentials

```sh
apiVersion: v1
kind: Secret
metadata:
  name: cicd-bookinfo-repo-creds
  namespace: cicd-bookinfo
  labels:
    argocd.argoproj.io/secret-type: repo-creds
stringData:
  url: git@github.com:generalpax/ci-cd-istio-tekton.git
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
```

and add it to the ArgoCD Operator CM data:

```sh
data:
  admin.enabled: 'true'
  statusbadge.enabled: 'false'
  resource.exclusions: ''
  ga.trackingid: ''
  repositories: |
    - sshPrivateKeySecret:
        key: sshPrivateKey
        name: cicd-bookinfo-repo-creds
      url: "git@github.com:generalpax/ci-cd-istio-tekton.git"
```

#### Install and configure Openshift Pipelines

Within the `tekton/auth` folder, create a file called `secrets.yaml`. Fill out the information in the angle brackets below, and then run `oc apply -f secrets.yaml -n cicd-bookinfo`.

```
apiVersion: v1
kind: Secret
metadata:
  name: basic-user-pass
  annotations:
    tekton.dev/docker-0: https://quay.io # Described below
type: kubernetes.io/basic-auth
stringData:
  username: user
  password: pw
---
apiVersion: v1
kind: Secret
metadata:
  name: basic-user-pass-2
  annotations:
    tekton.dev/git-0: https://github.com # Described below
type: kubernetes.io/basic-auth
stringData:
  username: user
  password: pw
```

Tekton will take the specified credentials and convert them into a format sufficient for the application to consume. From the [OpenShift/TektonCD documentation](https://github.com/openshift/tektoncd-pipeline/blob/release-v0.11.3/docs/auth.md).

Add Persisten Storage to your Pipeline:

Tekton provides a `Workspace` resource, which combined with a `persistentVolumeClaim` (PVC), enables the sharing of data from one `Task` to the next within a `Pipeline`. 

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cicd-bookinfo
spec:
  storageClassName: slow
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```
The `PipelineRun` resource specifies the `Workspace` required for the `Pipeline` to execute successfully.

#### Tasks, Pipelines, and PipelineRuns

The `Pipeline` in this repository consists of three `Tasks`. The first, `git-clone`, clones code from a GitHub repository and stores it in a `Workspace`. The second, `build-service`, builds a new image and pushes it to an image repository. Finally, `canary-rollout` creates and pushes new manifest files to GitHub, which include a Kubernetes `Deployment` specifying the new image to use, as well as Istio resources to enable a canary rollout of the new code.


To initiate a `Pipeline` we create a `PipelineRun`:
```
oc create -f pipeline-run.yaml
```

```
  params:
    - name: GIT_URL
      value: https://github.com/generalpax/ci-cd-istio-tekton 
    - name: BUILDER_IMAGE
      value: https://quay.io/buildah/stable:v1.14.0
    - name: REVISION
      value: master
    - name: SERVICE_NAME
      value: productpage
    - name: IMAGE_REPOSITORY
      value: quay.io/jkap
    - name: SERVICE_VERSION
      value: v2
```

## References

[Bookinfo application demo](https://github.com/tnscorcoran/openshift-servicemesh)