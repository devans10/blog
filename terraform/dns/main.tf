resource "digitalocean_record" "sitename" {
  domain = "daveevans.us"
  type = "A"
  name = var.sitename
  value = var.ipaddress
}
