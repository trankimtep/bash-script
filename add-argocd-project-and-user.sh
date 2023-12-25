#!/bin/bash

#Select kubeconfig file
read -p "KUBECONFIG [/home/misa/.kube/misard-admin]: " config
config=${config:-"/home/misa/.kube/misard-admin"}
export KUBECONFIG="$config"

#Login to argocd
printf "\n\n------\n\nLogin to Argocd \n\n"
read -p "Server [10.0.6.133:32032]: " server
server=${server:-"10.0.6.133:32032"}
argocd login "$server"

#Create project
printf "\n\n------\n\nCreate project \n\n"
read -p "Project " project

read -p "Source ["http://10.0.6.64:8080"]: " source
source=${source:-"http://10.0.6.64:8080"}

echo "Enter destinations list: "
read -a des_list
des_list_str=""
for elem in ${des_list[@]}
do 
    des_list_str+="--dest $elem "
done

argocd proj delete $project
argocd proj create $project $des_list_str --src $source

#Create account
printf "\n\n------\n\nCreate account \n\n"
read -p "Username: " user

new_key="accounts.$user" 
new_value="apiKey,login"

#### Add user to argocd-cm
kubectl get cm argocd-cm -o yaml > tmp 
yq eval -i '.data["'$new_key'"] = "'$new_value'"' tmp
kubectl apply -f tmp
printf "\n\n------------\n\n"
kubectl get cm argocd-cm -o yaml | yq '.data' | grep "$user"
printf "\n\n------------\n\n"

#### Generate password for user 
password=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c8)
argocd account update-password --account $user --new-password $password --grpc-web

#### Add user role to argocd-rbac-cm
policy_app="p, role:$user, applications, *, $project/*, allow"
policy_exec="p, role:$user, exec, create, $project/*, allow"
group="g, $user, role:$user"

kubectl get cm argocd-rbac-cm -o yaml > tmp 
yq e '.data."policy.default"="role:readonly" }' -i tmp 
combined_policies=$(printf '%s\n%s\n%s' "$policy_app" "$policy_exec" "$group")
escaped_policies=$(echo "$combined_policies" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
yq eval -i '.data["policy.csv"] += "\n'"$escaped_policies"'"' tmp 

kubectl apply -f tmp 
printf "\n\n------------\n\n"
kubectl get cm argocd-rbac-cm -o yaml | yq '.data' | grep "$user"
printf "\n\n------------\n\n"

## print password
printf "Password is:\n"
echo "$password"
