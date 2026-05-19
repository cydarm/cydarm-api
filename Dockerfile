# syntax=docker/dockerfile:1.7-labs
### STAGE: INSTALLATION OF TOOLS
ARG OPENAPI_GENERATOR_VERSION=v7.15.0
FROM openapitools/openapi-generator-cli:${OPENAPI_GENERATOR_VERSION} AS tools

ARG GO_VERSION=1.25.3
#--latest-npm used later
ARG NVM_VERSION=0.40.3
ARG NODE_VERSION=24
ARG TARGETARCH
ARG BUILDARCH

# needed to load /root/.bashrc properly which has our updated PATH
SHELL ["/bin/bash", "--login", "-i", "-c"]

RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update && apt-get install -y vim rsync curl git openssh-client lld make jq

### GO + go-swagger
ENV GOCACHE=/go/cache
ENV GOMODCACHE=/go/pkg/mod
ENV GOPRIVATE=github.com/cydarm
RUN mkdir -p /go/cache /go/pkg/mod

# Install go for go-swagger
#ADD https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz /tmp/go.tar.gz
ADD https://go.dev/dl/go${GO_VERSION}.linux-${BUILDARCH}.tar.gz /tmp/go.tar.gz
RUN <<"EOF"
set -eux
tar -C /usr/local -xzf /tmp/go.tar.gz
echo "export PATH="/root/go/bin:/usr/local/go/bin:$PATH"" >> /root/.bashrc
EOF

### Install nvm for api-spec-converter + redocly
RUN <<"EOF"
set -euo pipefail
set -x
### Stage(REDOCLY): Join the OpenAPI specs together
# install node so we can run redocly
curl -s -o- "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
. "$HOME/.nvm/nvm.sh"
nvm install ${NODE_VERSION} --latest-npm
nvm use ${NODE_VERSION}
EOF

# Install go-swagger
RUN --mount=type=ssh \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/go/cache \
    <<EOF
set -eux
export PATH="/root/go/bin:/usr/local/go/bin:$PATH"
CGO_ENABLED=0 go install github.com/go-swagger/go-swagger/cmd/swagger@latest
EOF

# Install api-spec-converter and redocly cli
RUN <<"EOF"
#source /root/.bashrc

# Install redocly
# redocly/cli join api-spec-converter_cydarm-api.yaml api-new/api_gen/api/openapi.yaml
# version 2.0.5 fixes a bug which happens to break this for us at the moment as we don't specify servers consistently in the old (go-swagger) and new (api-new) specs
# https://github.com/Redocly/redocly-cli/pull/2133
#npm install -g @redocly/cli@2.0.4
npm install -g @redocly/cli@latest

# Install api-spec-converter
npm install -g api-spec-converter
EOF

### CONFIG

FROM tools AS config

# Set up git for pulling down private cydarm go packages
RUN <<"EOF"
set -eux
git config --global url."git@github.com:".insteadOf "https://github.com"
mkdir ~/.ssh/
ssh-keyscan -t rsa github.com > ~/.ssh/known_hosts
EOF

WORKDIR /build

# yq is used to modify the spec to match what the API actually does as our annotations are not always accurate
COPY --from=mikefarah/yq /usr/bin/yq /usr/bin/yq

VOLUME /go/pkg/mod
VOLUME /go/cache
VOLUME /repos

COPY ./entrypoint.sh /entrypoint.sh
COPY ./generate_api_docs.sh /src/

SHELL ["/bin/bash", "--login", "-c"]
ENTRYPOINT ["/entrypoint.sh"]
CMD ["make", "--makefile=/src/Makefile.in-docker", "--always-make"]
