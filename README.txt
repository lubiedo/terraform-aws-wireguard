Setup the secrets:
locals {
  aws_access_key = "<YOUR_ACCESS_KEY>"
  aws_secret_key = "<YOUR_SECRET_KEY>"
}

To provision a new instance:

$ terraform init
$ terraform plan -out tf.plan
$ terraform apply tf.plan

The server's [Peer] configuration for the client will be part of the remote-exec
output at the end of the apply. For example:

null_resource.wireguard_install (remote-exec): [Peer]
null_resource.wireguard_install (remote-exec): PublicKey =
ddwzaD8eSDWMrrdI0LkdYTBs2DIAPe6KVos0y/eFhR7jU=
null_resource.wireguard_install (remote-exec): Endpoint = 34.242.250.171:51820
null_resource.wireguard_install (remote-exec): AllowedIPs = 0.0.0.0/0, ::/0

In case you want to connect to the server you can use `terraform output --json`
and SSH:

$ terraform output --json|jq -r .instance_privkey.value > rsa.pem
$ ssh -v -i rsa.pem -l ubuntu 34.242.250.171

