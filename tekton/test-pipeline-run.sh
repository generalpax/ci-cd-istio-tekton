tkn pipeline start build-deploy-canary --param="GIT_URL=https://github.com/generalpax/ci-cd-istio-tekton" --param="BUILDER_IMAGE=quay.io/buildah/stable:v1.14.8" --param="REVISION=master" --showlog
