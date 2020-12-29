# freenas-iocage-lychee
Script to create a FreeNAS jail and install [Lychee photo manager](https://github.com/LycheeOrg/Lychee) in it

# Installation
Change to a convenient directory, clone the repository using `git clone https://github.com/LycheeOrg/Lychee`, change to the freenas-iocage-lychee directory, and create a configuration file called `lychee-config` with your favorite text editor (if you don't have a favorite text editor, `nano` is a good choice--run `nano lychee-config`).  Then run the script with `script lychee.log ./lychee-jail.sh`.

## Configuration options
In its minimal form, the configuration file would look like this:
```
JAIL_IP="192.168.1.78"
DEFAULT_GW_IP="192.168.1.1"
POOL_PATH="/mnt/tank"
```

* JAIL_IP:  The IP address to assign the jail.  You may optionally specify a netmask in CIDR notion.  If none is specified, the default is /24.  Values of less than 8 bits or more than 30 bits will also result in a 24-bit netmask.
* DEFAULT_GW_IP:  The IP address of your default gateway.
* POOL_PATH:  The path to your main data pool (e.g., `/mnt/tank`).  The Caddyfile and Lychee installation files (i.e., the web pages themselves) will be stored there, in $POOL_PATH/apps/lychee.  If you have more than one pool, choose the one you want to use for this purpose.
* JAIL_NAME:  Optional.  The name of the jail.  If not given, will default to "lychee".

## Post-install configuration
Once the script completes, point your web browser to the IP address of your jail, where you'll go through the Lychee installer.  You will not need to change anything until it asks for an admin username and password--enter whatever you like for those.

## SSL configuration (recommended)
This script uses the [Caddy](https://caddyserver.com/) web server, which supports automatic HTTPS, reverse proxying, and many other powerful features.  It is configured using a Caddyfile, which is stored at `/usr/local/www/Caddyfile` in your jail, and under `/apps/lychee/` on your main data pool.  You can edit it as desired to enable these or other features.  For further information, see [my Caddy script](https://github.com/danb35/freenas-iocage-caddy), specifically the included `Caddyfile.example`, or the [Caddy docs](https://caddyserver.com/docs/caddyfile).

This script installs Caddy from the FreeBSD binary package, which does not include any [DNS validation plugins](https://caddyserver.com/download).  If you need to use these, you'll need to build Caddy from source.  The tools to do this are installed in the jail.  To build Caddy, run these commands:
```
go get -u github.com/caddyserver/xcaddy/cmd/xcaddy
go build -o /usr/local/bin/xcaddy github.com/caddyserver/xcaddy/cmd/xcaddy
xcaddy build --output /usr/local/bin/caddy --with github.com/caddy-dns/${DNS_PLUGIN}
```
...with `${DNS_PLUGIN}` representing the name of the plugin, listed on the page linked above.  You'll then need to modify your configuration as described in the Caddy docs.

# Support
Questions and discussion should be directed to https://forum.freenas-community.org/t/scripted-installation-of-lychee-photo-manager/102