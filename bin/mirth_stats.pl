#!/usr/bin/env perl
use warnings;
use strict;

use POSIX;
use DBI;
use NetSNMP::agent (':all');
use NetSNMP::ASN qw( ASN_OCTET_STR ASN_INTEGER );
use YAML::Syck;

# Set up some constants for the processor.
use constant {
  CONFIG_PATH => '/etc/mirth_snmp/config.yml'
};

# Flush after every write
$| = 1;

# 
# The mapping of channel ids to names. From configuration file.
# 
my $channels = {};

# 
# The path to the Mirth config.properties file. From configuration file.
#
my $mirthConfigPath = '';

#
# The OIDs/data values supported by this sub-agent. These mappings
# are created using the data in the configuration file.
#
my $oidMappings = {};

#
# The root OID number for this sub-agent. From the configuration file.
#
my $rootOid = new NetSNMP::OID('.1.3.6.1.4.1.8072.9999.9999');

#
# The base OID number for this sub-agent. From the configuration file.
#
my $oidNumber = 10;

#
# The first sub-oid number for this sub-agent.
#
my $firstSubOid = "$oidNumber.0";

#
# The database connection information. This will be populated by
# reading the connection information from the Mirth Connect
# config.properties file.
#
my $dbConn = {
  'db' => '',
  'user' => '',
  'password' => '',
  'adapter' => 'mysql'
};

#
# Configure the OID mappings we'll be providing from this sub-agent.
#
sub configureOidMappings {
  my $index = 0;
  my $channelIndex = 0;
  my @channelKeys = keys($channels);
  my $ckkey;

  foreach $ckkey (@channelKeys) {
    my $name = $channels->{$ckkey};
    my $nextIndex = $index + 1;
    $oidMappings->{"$oidNumber.$index"} = { 
      'stats_key' => "$name-1-hour",
      'data_type' => ASN_INTEGER,
      'next' => "$oidNumber.$nextIndex"
    };
    $index += 1;
    my $hasMore = $channelIndex < ($#channelKeys);
    $oidMappings->{"$oidNumber.$index"} = { 
      'stats_key' => "$name-6-hour",
      'data_type' => ASN_INTEGER
    };
    if ($hasMore) {
      $nextIndex = $index + 1;
      $oidMappings->{"$oidNumber.$index"}->{'next'} = "$oidNumber.$nextIndex";
    }
    $index += 1;
    $channelIndex += 1;
  }
}

#
# Read the sub-agent configuration file and prepare the sub-agent
# to start processing.
#
sub loadConfiguration {
  my $config = LoadFile(::CONFIG_PATH);

  $mirthConfigPath = $config->{'mirth_config'};

  $channels = $config->{'channels'};

  $rootOid = new NetSNMP::OID($config->{'root_oid'});

  $oidNumber = $config->{'oid_number'};

  $firstSubOid = "$oidNumber.0";

  configureOidMappings();

  # Set up the OIDs we will provide
}

#
# Open up the mirth properties file and collect up the database
# connection info we'll be needing to process the requests
#
sub connectionInfo {
  open(my $fh, '<:encoding(UTF-8)', $mirthConfigPath)
    or die "Error opening the mirth properties file\n";

  while (my $row = <$fh>) {
    chomp $row;
    if ($row =~ /database\.url\s+=\s+([^\s]+)/) {
      # The name of the database is the last element in the
      # database URL
      my @elms = split(/\//, $1);
      $dbConn->{'db'} = $elms[-1];
      @elms = split(/:/, $1);
      $dbConn->{'adapter'} = $elms[1];
    } elsif ($row =~ /database\.username\s+=\s+([a-zA-Z0-9]+)/) {
      $dbConn->{'user'} = $1;
    } elsif ($row =~ /database\.password\s+=\s+([^\s]+)/) {
      $dbConn->{'password'} = $1;
    }
  }

  close $fh;
}

#
# Returns the mapping information associated with the
# specified request OID.
#
sub identifyOid {
  my $requestOid = shift;
  my $oidKey;
  my $oidData;

  foreach $oidKey (sort(keys %$oidMappings)) {
    my $currentOid = $rootOid + $oidKey;
    if ($requestOid == $currentOid) {
      $oidData = $oidMappings->{$oidKey};
      last;
    }
  }

  return $oidData;
}

#
# Generate the statistics for the configured channels
# and return them.
#
sub getMirthStats {
  my $dbName = $dbConn->{'db'};
  my $adapter = $dbConn->{'adapter'};

  my $conn = DBI->connect("DBI:$adapter:database=$dbName",
	$dbConn->{'user'},
	$dbConn->{'password'});

  my @scids = map { "'$_'" } keys(%$channels);
  my $cids = join(',', @scids);
  # my $cids = join(',', keys(%$channels));

  my $channelSQL = <<"EOF";
  SELECT 
    c.id, 
    c.name, 
    dc.local_channel_id, 
    CONCAT('D_M',dc.local_channel_id) tbl_name 
  FROM 
    CHANNEL c, 
    D_CHANNELS dc 
  WHERE 
    dc.channel_id = c.id
    AND c.id IN ($cids)
EOF

  my $ps = $conn->prepare($channelSQL) 
    or die "Couldn't prepare statement: " . DBI->errstr;

  $ps->execute()
    or die "Couldn't execute the query: " . DBI->errstr;

  my %statistics;

  while (my @data = $ps->fetchrow_array()) {
    my $tblName = $data[3];
    my $name = $data[1];
    my $channelId = $data[0];

    my $oneHourCount = lastHours($conn, $tblName, $name, 1);
    my $sixHourCount = lastHours($conn, $tblName, $name, 6);

    my $channelName = $channels->{$channelId};
    $statistics{"$channelName-1-hour"} = $oneHourCount;
    $statistics{"$channelName-6-hour"} = $sixHourCount;
  }

  $conn->disconnect();

  return \%statistics;
}

#
# Return the statistics for the specified channel for
# the specified number of hours.
#
sub lastHours {
  my ($conn, $table, $name, $hours) = @_;

  my $countSQL = <<"EOSQL";
  SELECT 
    count(*) 
  FROM 
    $table 
  WHERE 
    received_date > DATE_SUB(?, INTERVAL $hours HOUR)
EOSQL

  my $ps = $conn->prepare($countSQL) 
    or die "Couldn't prepare statement: " . DBI->errstr;

  my $now = strftime "%Y-%m-%d %H:%M:%S", localtime;
  $ps->bind_param(1, $now);

  $ps->execute();

  # Should be a single row returned.
  my @data = $ps->fetchrow_array();

  return $data[0];
}

#
# The Mirth SNMP Handler
#
sub mirth_handler {
  my ($handler, $registration_info, $request_info, $requests) = @_;
  my $stats = getMirthStats();
  my $request;

  for ($request = $requests; $request; $request = $request->next()) {
    my $oid = $request->getOID();

    if ($request_info->getMode() == MODE_GET) {
      my $oidData = identifyOid($oid);
      if ($oidData) {
        $request->setValue($oidData->{'data_type'}, $stats->{$oidData->{'stats_key'}});
      }
    } elsif ($request_info->getMode() == MODE_GETNEXT) {
      my $oidData = identifyOid($oid);
      if ($oidData && $oidData->{'next'}) {
        $request->setOID($rootOid + $oidData->{'next'});
        my $nextOidData = $oidMappings->{$oidData->{'next'}};
        $request->setValue($nextOidData->{'data_type'}, $stats->{$nextOidData->{'stats_key'}});
      } elsif ($oid < $rootOid + $firstSubOid) {
        my $oidData = $oidMappings->{$firstSubOid};
        $request->setOID($rootOid + $firstSubOid);
        $request->setValue($oidData->{'data_type'}, $stats->{$oidData->{'stats_key'}});
      }
    }
  }

}

# Read the configuration for this sub-agent
loadConfiguration();

# Get the Mirth DB connection information set up
connectionInfo();

# Now register the agent with SNMP.
my $agent = new NetSNMP::agent();
$agent->register("mirth_stats", $rootOid, \&mirth_handler);
