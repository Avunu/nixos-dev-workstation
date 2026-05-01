let
  kevin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOv4SpIhHJqtRaYBRQOin4PTDUxRwo7ozoQHTUFjMGLW";
  developer = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILtMd4jTM9A36iVI2R6zw8cApkd7HQExr0ayfHcwaOp/";

  allKeys = [
    kevin
    developer
  ];
in
{
  "secrets/rclone.age".publicKeys = allKeys;
}
