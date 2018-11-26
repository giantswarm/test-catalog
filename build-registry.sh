#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly REPONAME=$1
readonly PERSONAL_ACCESS_TOKEN=$2

readonly APPS_FILE=./APPS
readonly HELM_URL=https://storage.googleapis.com/kubernetes-helm
readonly HELM_TARBALL=helm-v2.9.1-linux-amd64.tar.gz
readonly HELM_REPO_URL=https://giantswarm.github.com/${REPONAME}

main() {
    setup_helm_client

    if ! download_latest_charts; then
        log_error "Not all charts could be downloaded!"
    fi

    setup_git

    if ! sync_repo "$HELM_REPO_URL"; then
        log_error "Not all charts could be packaged and synced!"
    fi
}

setup_helm_client() {
    echo "Setting up Helm client..."

    curl --user-agent curl-ci-sync -sSL -o "$HELM_TARBALL" "$HELM_URL/$HELM_TARBALL"
    tar xzfv "$HELM_TARBALL"

    PATH="$(pwd)/linux-amd64/:$PATH"

    helm init --client-only
    helm repo add "$REPONAME" "$HELM_REPO_URL"
}


setup_git() {
    echo "Setting up git..."
    git config credential.helper 'cache --timeout=60'
    git config user.email "dev@giantswarm.io"
    git config user.name "Taylor Bot"

}

download_latest_charts() {
  while IFS="" read -r app || [ -n "$app" ]
  do
      local url=$(curl -s https://api.github.com/repos/${app}/releases/latest | jq -r .assets[0].browser_download_url)
      local chart=$(echo ${url} | tr "/" " " | awk '{print $NF}')

      # Check if release exists and not already present
      if [ "${url}" == "null" ];then
        echo "No GitHub release '$app' found!"
        exit 1
      elif [ -e "${chart}" ];then
        echo "${chart} already present, skipping!"
      else
        echo "Downloading chart '$chart'..."
        wget -q -P sync ${url}
      fi
  done < ${APPS_FILE}
}

sync_repo() {
    local repo_url="${1?Specify repo url}"

    echo "Syncing repo..."
    if helm repo index --url "$repo_url" --merge "index.yaml" "sync"; then
        mv -f ./sync/* .

        git add *.tgz
        git add index.yaml

        git commit -m "Auto-commit ${repo_url}"
    else
        log_error "Exiting because unable to update index. Not safe to push update."
        exit 1
    fi
    return 0
}



# publish() {
#   echo "Publishing ${1} to https://giantswarm.github.com/${REPONAME}"

#   # NOTE: Creation time of all charts updated, since local existing charts take priority
#   # Fix this, by deleting (old) checked out charts first
#   helm repo index ./ --merge ./index.yaml --url https://giantswarm.github.com/${REPONAME}
#   git add ./${1} ./index.yaml
#   git commit -m "Auto-commit ${1}"
#   git push -q https://${PERSONAL_ACCESS_TOKEN}@github.com/giantswarm/${REPONAME}.git master
#   echo "Successfully pushed ${1} to giantswarm/${REPONAME}"
# }

# Set up git
# git checkout -f master

log_error() {
    printf '\e[31mERROR: %s\n\e[39m' "$1" >&2
}

main
