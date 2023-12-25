#!/bin/bash
user=$1
namespace=$2
cluster=$3
new_config=$user-config


kubectl create namespace $namespace || flag=1

openssl genrsa -out "$user.key" 2048
openssl req -new -key "$user.key" -out "$user.csr" -subj "/CN=$user"

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: $user
spec:
  request: $(cat "$user.csr" | base64 | tr -d "\n")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400  # one day
  usages:
  - client auth
EOF

kubectl certificate approve $user

kubectl get csr $user -o jsonpath='{.status.certificate}' | base64 -d > "$user.crt"

:> tmp
kubectl config set-credentials $user --client-key="$user.key" --client-certificate="$user.crt" --embed-certs=true --kubeconfig=./$new_config 

kubectl config set-context $user --user=$user --cluster=$cluster --namespace=$namespace

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $user-role
  namespace: $namespace
rules:
- apiGroups:
  - '*'
  - extensions
  - apps
  resources:
  - '*'
  verbs:
  - '*'
EOF

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $user-rolebinding
  namespace: $namespace
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $user-role
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: $user

EOF

source_config="/home/misa/.kube/minikube/config"
cp $source_config .

touch context
kubectl config view > context

yq -i '.contexts = load("context").contexts' $new_config 
yq -i '.clusters = load("config").clusters' $new_config  
yq ".current-context = \"${user}\"" -i $new_config 
