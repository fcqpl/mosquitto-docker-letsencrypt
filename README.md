# alpine-mosquitto-certbot

## Changes
- updated docker-compose.yml
- updated python-alpine image from 2.7 to 3.9
- updated certbot generation (unrecognized arguments: --standalone-supported-challenges http-01)


## Original description

An automated build that integrates the [Mosquitto MQTT server](https://mosquitto.org/) with [Certbot](https://certbot.eff.org/) on top of [Alpine linux](https://www.alpinelinux.org/).

As the Internet of Things (IoT) world rapidly grows and evolves, developers need a simple and secure way to implement peer-to-peer and peer-to-server (backend) communications.  MQTT is a relatively simple message/queue-based protocol that provides exactly that. 
Unfortunately, there are a ton of Docker images available for brokers, e.g. eclipse-mosquitto; but, nearly all of them leave it up to the user to figure out how to secure the platform.  This results in many developers simply ignoring security altogether for the sake of simplicity.  Even more dangerous, many semi-technical home owners are now dabbling in the home automation space and due to the complexity of securing system, they are hanging IoT/automation devices on the internet completely unsecurred.

This docker image attempts to make it easier to implement a secure MQTT broker, either in the cloud or on premise.  The secured broker can be used with home automation platforms like [Home Assistant](https://home-assistant.io/) or simply as a means of enabling secure IoT device communications.

For those interested in some of the nuts and bolts related to the integration, reference [Brian Boucheron's](https://www.digitalocean.com/community/users/bboucheron) excellent article [How to Install and Secure the Mosquitto MQTT Messaging Broker on Ubuntu 16.04](https://www.digitalocean.com/community/tutorials/how-to-install-and-secure-the-mosquitto-mqtt-messaging-broker-on-ubuntu-16-04) which servered as a reference in creating this image.

## Standing up a server

A straigtforward way of standing up a server is to use [docker-compose](https://docs.docker.com/compose/).  Here is a sample [docker-compose.yml](https://docs.docker.com/compose/compose-file/) file:

```
version: '2'
networks:
  mqtt-net:
    driver: bridge

services:
  mqtt:
    #image: bitrox/alpine-mosquitto-certbot
    build: mosquitto-docker-letsencrypt
    networks:
      - mqtt-net
    ports:
      - 1883:1883
      - 8083:8083
      - 8883:8883
      - 80:80
    environment:
      - DOMAIN=mqtt.myserver.com
      - EMAIL=myemail@myprovider.com
    volumes:
      - ./mosquitto/conf/:/mosquitto/conf
      - ./mosquitto/log/:/mosquitto/log
      - ./letsencrypt:/etc/letsencrypt
      - ./scripts:/scripts
    container_name: mqtt
    restart: always
```

In this case, four ports are exposed, which we'll go over in more detail when describing how this configuration matches that of the mosquitto.conf file.  The first three ports are associated with Mosquitto, the forth port mapping (80:80) allows Certbot/LetsEncrypt to verify the DOMAIN.  Also shown in the yml file is a backend-net network, which you many or may not have implemented with your particular Docker environment (Docker networking is WAY beyond the scope of this discussion).

## Environment Variables

There are three environment variables useable with this image.  DOMAIN and EMAIL are required for Certbot/[Letencrypt](https://letsencrypt.org/) to obtain certificates necessary for secure communications.  The third, TESTCERT, is optional.

**DOMAIN** - This should be defined as your fully qualified domain name, i.e. mqtt.myserver.com.  The domain needs to point to your server as LetsEncrypt will verify such when obtaining certificates.

**EMAIL** - This simply needs to be an email address. It's required by certbot/LetsEncrypt to obtain certificates.

**TESTCERT** - This variable can be set to any value (e.g. TRUE).  When defined, the image will utilize certbot/LetsEncrypt --staging server and obtain non-valid test-certs.  It will also use --dry-run when simulating certificate renewal.  The variable's utility is in the fact that it enables the user to configure and test/debug the process of obtaining certificates without running into the fairly low hourly limits imposed by LetsEncrypt.  Example: If the service is configured correctly, but the server isn't reachable on port 80 due to an incorrectly configured firewall, TESTCERT defined will reveal this fact without attempting to obtain a real certificate.

## Volumes (persistence)

The scripts associated with this image assume a standard directory structure for mosquitto configuration and certbot/LetsEncrypt.  It is possible to deviate from the below defined standard, but doing so should be left to those more familiar with Docker and Mosquitto.

```
/mosquitto/conf/
	mosquitto.conf
	passwd
/mosquitto/log/
/letsencrypt/
```

The docker-compose.yml file shown above maps local (persistent) directories to the relevant container volumes:

**/mosquitto/conf/** - this directory is where Mosquitto will look for the mosquitto.conf file.

**/mosquitto/conf/mosquitto.conf** - this file is user supplied.  The startup scripts will look for exactly this file in exactly this directory. If it isn't found, the container will exit with appropriate error messages.

**/mosquitto/conf/passwd** - this file is the standard location for Mosquitto users/passwords.  An alternate file/location can be specified in mosquitto.conf, but it must be in a location persisted through docker volume mapping.  It's presence/use is optional, but allowing anonymous access to MQTT somewhat defeats the purpose of this image.

**/mosquitto/log** - This directory is the location where mosquitto will place log file(s).  Like passwd defined above, its use is optional and can be controlled based on the contents of mosquitto.conf.

**/letsencrypt** - This directory is where certbot/LetsEncrypt will place retrieved certificates.  The certbot scripts specifically require/expect this directory to exist in the container, so it should be mapped.

**/scripts** - To enable customization of the container, the run.sh script looks for this directory.  If it finds /scripts, it will look inside the directory for any file ending in .sh, e.g. myscript.sh.  It will then attempt to execuite said script(s) during container startup, immediately after dealing with certbot/LetsEncrypt, but before starting Mosquitto.  Scripts found will be executed in alpha order.  A suggested naming convention for scripts include a number followed by a dash, then the script name, ending in .sh, e.g. 00-myfirstscript.sh, 01-mysecondscript.sh, etc.  This will ensure your scripts are executed in the order intended.  An example of this functionality would be if you want additional software/utilities in the container.

The sample docker-compose.yml file shows a local directory ./scripts mapped to the container volume /scripts where run.sh will look for the above discussed user scripts to run at startup.

## Certbot/LetsEncrypt Integration

At container startup, scripts will look to see if certificates for DOMAIN exist in /letsencrypt.  If it doesn't find any certificates, it will attempt to obtain them (via certbot certonly --standalone --agree-tos --standalone-supported-challenges http-01 -n -d $DOMAIN -m $EMAIL).
If certificates do exist, then an attempt will be made to renew them (via certbot renew).
Once a week, scripts will be run to check to see if the certificates need renewal.  If so, they will be renewed, then the mosquitto server will be restarted so that it picks up the new certificates.  Unfortunately, this does mean that there will be a brief (few second) outage each time certificates are in fact renewed.  Adjust use cases for this server accordingly.

## mosquitto.conf

Documentation for Mosquitto should be consulted for details on how to properly configure this file.  However, below is a sample configuration file that matches the docker-compose.yml shown above.

 In the below configuration, we make mosquitto available via three different ports.  Port 1883 uses the standard mqtt protocol.  It is accessible without TLS/SSL, but does require user id/password verification (defined in /mosquitto/conf/passwd).  The use case for 1883 is that it is expose internally to other processes/servers on a private network.  Port 8883 provides accessiblity via the mqtt protocol, but requires TLS/SSL.  The use case is that port 8883 is exposed to the internet, accessible via DOMAIN.  And lastly, port 8083 allows the server to be accessed via websockets. It also requires TLS/SSL.  Again it's use case would be that port 8083 is exposed to the internet, accessible via DOMAIN.

 Logging is enabled and the directory for storing log files is defined as /mosquitto/log.  The highest level of detail for logging is enabled.  Consult [Mosquitto documentation](https://mosquitto.org/documentation/) for the logging parameters if you want a lesser level of logging turned on once you have the server debugged and integrated with your other devices/software.

 Anonymous access to the server is disabled, indicating all connections must be validated via user id/password.

```
# Config file for mosquitto
#
# See mosquitto.conf(5) for more information.
#

# =================================================================
# General configuration
# =================================================================

# When run as root, drop privileges to this user and its primary 
# group.
# Leave blank to stay as root, but this is not recommended.
# If run as a non-root user, this setting has no effect.
# Note that on Windows this has no effect and so mosquitto should 
# be started by the user you wish it to run as.
user mosquitto

# =================================================================
# Default listener
# =================================================================

port 1883
protocol mqtt

# =================================================================
# Extra listeners
# =================================================================

listener 8083
protocol websockets 
cafile /etc/letsencrypt/live/mqtt.bitrox.io/chain.pem
certfile /etc/letsencrypt/live/mqtt.bitrox.io/fullchain.pem
keyfile /etc/letsencrypt/live/mqtt.bitrox.io/privkey.pem

listener 8883
protocol mqtt
cafile /etc/letsencrypt/live/mqtt.bitrox.io/chain.pem
certfile /etc/letsencrypt/live/mqtt.bitrox.io/fullchain.pem
keyfile /etc/letsencrypt/live/mqtt.bitrox.io/privkey.pem

# =================================================================
# Logging
# =================================================================

log_dest file /mosquitto/log/mosquitto.log
log_type all
websockets_log_level 255
connection_messages true
log_timestamp true

# =================================================================
# Security
# =================================================================

allow_anonymous false

# -----------------------------------------------------------------
# Default authentication and topic access control
# -----------------------------------------------------------------

# Control access to the broker using a password file. This file can be
# generated using the mosquitto_passwd utility. 
password_file /mosquitto/conf/passwd

## Generating User ID/Password

Mosquitto provides a utility (mosquitto_passwd) for adding users to a password file with encrypted passwords.  Assuming the passwd file is in the standard location as shown in the mosquitto.conf file above, you can add a user/password combination (e.g. booboy myPwd123) to the file once the docker container is up and running, using the following command:

docker exec -it mqtt mosquitto_passwd -b /mosquitto/conf/passwd booboy myPwd123

This command doesn't provide any feedback if successful, but does show errors if there are problems.  You can verify success simply looking in the passwd file.  You should see an entry similar to: booboy:$6$+NKkI0p3oZmSukn9$mOUEEHUizK2zqc8Hk2l0JlHHXTW8GPzSonP9Ujrjhs1tVNQqN3lGCAFcFKnpJefOjUPwjqE5mZ
qSjBl6BCKnPA==
```

## Testing Your Server

To test your server locally (i.e. within the container), you can pop into the container and use mosquitto_pub and mosquitto_sub.  Note that you'll need to do this from two separate terminal sessions so see the effect. If you receive error messages, look in the mosquitto error log (/mosquitto/log) for diagnostic information.  You should also make sure the container came up properly using a command like:

```
docker logs mqtt
```

For the MQTT subscriber:

```
docker exec -it mqtt /bin/bash
mosquitto_sub -h <yourserveraddr> -u "booboy" -P "myPwd123" -t "testQueue"
```

The mosquitto_sub command will block waiting for messages from ++testQueue++.

To publish a message to ++testQueue++, open another terminal and use the following:

```
docker exec -it mqtt /bin/bash
mosquitto_pub -h <yourserveraddr> -u "booboy" -P "myPwd123" -t "testQueue" -m "Hello subscribers to testQueue!"
```

In the first (subscriber) terminal window, you should immediately see the message "Hello subscribers to testQueue!".

To test remotely, [mqtt-admin](https://hobbyquaker.github.io/mqtt-admin/) by [Sebastian Raff](https://hobbyquaker.github.io) is an excellent resource.  Note that you need to make sure any filewalls/routers between your container and the internet are properly configured to route requests on the ports specified before attempting to use mqtt-admin.





