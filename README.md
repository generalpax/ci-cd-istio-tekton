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

Each of the operators above are available via OperatorHub in the OpenShift web console.

#### Install Istio on OCP

Since mesh federation is not supported on OSSM (maistra.io) we use plain istio platform: 

[Platform Setup](https://istio.io/latest/docs/setup/platform-setup/openshift/)

and install dependencies:

```sh
oc apply -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/addons/grafana.yaml -n istio-system
oc apply -f https://raw.githubusercontent.com/istio/istio/release-1.11/samples/addons/prometheus.yaml -n istio-system
```
#### ArgoCD
Deploy the OCP Argo CD Operator to Openshift-Operators namespace and install default instance in the same namespace. 

[Installation steps for Argo CD Operator](https://argocd-operator.readthedocs.io/en/latest/install/openshift/)
## Demo

#### Service Accounts/Authentication

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

Tekton will take the specified credentials and convert them into a format sufficient for the application to consume. From the [OpenShift/TektonCD documentation](https://github.com/openshift/tektoncd-pipeline/blob/release-v0.11.3/docs/auth.md):

>In their native form, these secrets are unsuitable for consumption by Git and Docker. For Git, they need to be turned into (some form of) `.gitconfig`. For Docker, they need to be turned into a `~/.docker/config.json` file. Also, while each of these supports has multiple credentials for multiple domains, those credentials typically need to be blended into a single canonical keyring.
>
>To solve this, before any `PipelineResources` are retrieved, all pods execute a credential initialization process that accesses each of its secrets and aggregates them into their respective files in `$HOME`. [...]
>
>Credential annotation keys must begin with `tekton.dev/docker-` or `tekton.dev/git-`, and the value describes the URL of the host with which to use the credential.

For more information on ServiceAccount permissions and RBAC in Kubernetes, check out this link: [Using RBAC Authorization - Kubernetes](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#service-account-permissions)

#### Persistent Storage

Tekton provides a `Workspace` resource, which combined with a `persistentVolumeClaim` (PVC), enables the sharing of data from one `Task` to the next within a `Pipeline`. 

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cicd-bookinfo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```
The `PipelineRun` resource specifies the `Workspace` required for the `Pipeline` to execute successfully.

#### Tasks, Pipelines, and PipelineRuns

The `Pipeline` in this repository consists of three `Tasks`. The first, `git-clone`, clones code from a GitHub repository and stores it in a `Workspace`. The second, `build-service`, builds a new image and pushes it to an image repository. Finally, `canary-rollout` creates and pushes new manifest files to GitHub, which include a Kubernetes `Deployment` specifying the new image to use, as well as Istio resources to enable a canary rollout of the new code.

The last step in this demo configuration uses Argo CD to deploy the newly created manifest files from GitHub as workloads in the cluster. As mentioned above, the manifests include routing rules for the Istio control plane to split traffic between previous versions of the microservice, with 10% sent to the new version. The Istio resources include a `DestinationRule` and `VirtualService`:

```
add rules here
```

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