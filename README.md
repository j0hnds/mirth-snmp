# mirth-snmp

This project is an implementation of an SNMP sub-agent to
pull statistics from your [Mirth Connect 3.2+](https://www.mirth.com/) 
server.

This sub-agent was designed to be fairly configurable to allow
it to be used in a number of different environments and to allow
collected statistics to be expanded when new channels are 
added.

See 'Configuration' for details on configuration.

For each configured channel, the sub-agent will determine the
number of messages received on the channel in the last 1 hour
and the number of messages received on the channel in the 
last 6 hours.

In our case we use the 6-hour value as a criteria for alerting
when a channel isn't receiving messages in a timely manner.

## Installation

These instructions assume you have already installed the SNMP server and
have it up and running.

To manually install this sub-agent on a RHEL7 machine, copy the following 
files to the /usr/share/snmp/ directory:

* config/snmpd.local.conf
* bin/mirth_stats.pl

Then, create the directory '/etc/mirth_snmp' and place the config/config.yml
file into it. Then, edit the configuration file to your needs.

Finally, restart the SNMP server:

    $ sudo systemctl restart snmpd

## Configuration

Upon startup, the sub-agent will read the configuration file
located at '/etc/mirth_snmp/config.yml'.

The configuration file allows you to configure the following:

1. (mirth_config) The location of the Mirth Connect configuration file. This
   file is used to determine the database credentials for 
	 the Mirth Connect server. Defaults to: /opt/mirthconnect/conf/mirth.properties

2. (root_oid) The root OID for the subagent. You should provide your enterprise's
   OID here. The default is: '.1.3.6.1.4.1.8072.9999.9999' (SNMPv2-SMI::enterprises.8072.9999.9999).

3. (oid_number) The OID suffix for this sub-agent. This number is appended to the
   root OID for the sub-agent. The default is 11, meaning the default OID for
	 the sub-agent is (if the root OID is not changed): SNMPv2-SMI::enterprises.8072.9999.9999.11.

4. (channels) The set of channels for which you want statistics. This is
   a hash with the key being the GUID of the channel for which you want statistics 
   (this is from the 'id' column in the 'CHANNELS' table of your Mirth Connect
   database) and the value being the friendly name of the channel.

The following is an example configuration:

    ---
    mirth_config: /opt/mirthconnect/conf/mirth.properties

    root_oid: '.1.3.6.1.4.1.8072.9999.9091'

    oid_number: 10

    channels:
      'afaddd1c-f33c-4fa7-be48-c340e318f2b4': channel1
      'ab1ecbf2-e49b-4399-a71d-96c03d482b31': channel2

## Packaging for RPM

If you're thinking of packaging this little jewel up in
an RPM, you'll want to create a source package first. Here
are the steps you can use to create the source package.

1. Make sure the version of the package is correct in the VERSION file. This file is used by the packager.
2. Run the package.sh script. There are no arguments, just run it.

The source tar-ball will be created in the base directory of this
project: mirth_snmp-<version>.tar.bz2.

That's all.

# Copyright

Copyright (c) 2016 Dave Sieh

See LICENSE.txt for details.
