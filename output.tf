output "instance_privkey" {
  value = tls_private_key.wireguard_ssh_privkey.private_key_pem
  sensitive = true
}
output "instance_ip" {
  value = aws_instance.wireguard_ec2.public_ip
}
