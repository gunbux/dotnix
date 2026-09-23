## Devshell for the Firecracker-on-EKS work trial.
##
## Scope: run Firecracker inside a Kubernetes pod on EKS, take a cold (disk-only)
## snapshot of a dev workspace and restore it; stretch goal is a hot snapshot
## that also captures guest memory.
##
## Usage from any project directory:
##   nix develop ~/dotnix#firecracker-eks
{pkgs}:
pkgs.mkShell {
  name = "firecracker-eks";

  packages = with pkgs; [
    ## AWS access and auth
    awscli2
    aws-iam-authenticator
    ssm-session-manager-plugin

    ## EKS / Kubernetes
    eksctl
    kubectl
    kubernetes-helm
    kustomize
    k9s
    stern

    ## Infrastructure as code (eksctl covers the cluster; tofu for anything else)
    opentofu

    ## Firecracker itself. `firecracker` also ships `jailer`.
    firecracker
    firectl

    ## Building container images that carry the Firecracker binary + rootfs
    docker-client
    skopeo
    crane
    dive

    ## Building guest rootfs / kernel images and inspecting snapshot files
    e2fsprogs
    squashfsTools
    qemu-utils
    gnutar
    gzip
    xz

    ## Guest networking inside the pod (tap devices, NAT, CNI experiments)
    iproute2
    iptables
    bridge-utils
    socat
    cni-plugins

    ## Scripting and glue
    jq
    yq-go
    curl
    gnumake
    shellcheck
    python3
  ];

  shellHook = ''
    echo "firecracker-eks devshell"
    echo "  firecracker $(firecracker --version 2>/dev/null | head -n1 | awk '{print $NF}')"
    echo "  kubectl     $(kubectl version --client 2>/dev/null | awk '/Client/{print $3}')"
    echo "  eksctl      $(eksctl version 2>/dev/null)"
    echo "  aws         $(aws --version 2>/dev/null | cut -d' ' -f1)"
    if [ -w /dev/kvm ]; then
      echo "  /dev/kvm    writable (local Firecracker runs will work)"
    else
      echo "  /dev/kvm    not writable; local Firecracker runs need KVM, EKS nodes need a metal or nested-virt instance type"
    fi
  '';
}
