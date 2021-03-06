# == Class: puppet::server
#
# This class installs and configures a Puppet master
#
# == Description
#
# This class implements a Puppet master based around the dynamic environments
# workflow descripted in http://puppetlabs.com/blog/git-workflow-and-puppet-environments/
#
# ==  Parameters
#
# * modulepath
# * storeconfigs
# * servertype
#
# == Example
# Sample Usage:
#
#  $modulepath = [
#    "/etc/puppet/modules/site",
#    "/etc/puppet/modules/dist",
#  ]
#
#  class { "puppet::server":
#    modulepath => inline_template("<%= modulepath.join(':') %>"),
#    reporturl  => "https://dashboard.puppetlabs.com/reports";
#  }
#
class puppet::server (
  $autosign           = undef,
  $bindaddress        = '0.0.0.0',
  $ca                 = false,
  $config_version_cmd = '/usr/bin/git --git-dir $confdir/environments/$environment/.git rev-parse --short HEAD 2>/dev/null || echo',
  $dns_alt_names      = undef,
  $enc                = '',
  $enc_exec           = '',
  $ensure             = 'present',
  $directoryenvs      = true,
  $environmentpath    = undef,
  $basemodulepath     = [],
  $default_manifest   = undef,
  $manage_package     = true,
  $manifest           = '$confdir/modules/site/site.pp',
  $modulepath         = ['$confdir/modules/site', '$confdir/env/$environment/dist'],
  $parser             = undef,
  $manage_puppetdb    = false,
  $report             = true,
  $report_dir         = $puppet::params::report_dir,
  $reportfrom         = undef,
  $reports            = ['store', 'https'],
  $reporturl          = "https://${::fqdn}/reports",
  $servername         = $::fqdn,
  $serverssl_ciphers  = undef,
  $serverssl_protos   = undef,
  $servertype         = 'unicorn',
  $storeconfigs       = undef,
  $stringify_facts    = false,
  $package            = $puppet::params::master_package,
) inherits puppet::params {

  validate_bool($ca)
  validate_bool($directoryenvs)
  validate_bool($manage_puppetdb)
  if $dns_alt_names { validate_array($dns_alt_names) }
  if $reports { validate_array($reports) }
  if $parser { validate_re($parser, ['custom', 'future']) }

  $service = $servertype ? {
    'passenger'    => 'httpd',
    /unicorn|thin/ => 'nginx',
    'standalone'   => $puppet::params::master_service,
  }

  include puppet
  include puppet::server::config

  if $manage_package and ($puppet::agent::package != $package) {
    package { $package:
      ensure => $ensure,
      notify => Service[$service],
    }
  }

  # ---
  # The site.pp is set in the puppet.conf, remove site.pp here to avoid confusion.
  # Unless the manifest that was passed in is the default site.pp.
  if ($manifest != "${puppet::params::puppet_confdir}/manifests/site.pp") {
    file { "${puppet::params::puppet_confdir}/manifests/site.pp": ensure => absent; }
  }

  # ---
  # Application-server specific SSL configuration
  case $servertype {
    'passenger': {
      include puppet::server::passenger
      $ssl_client_header        = 'SSL_CLIENT_S_DN'
      $ssl_client_verify_header = 'SSL_CLIENT_VERIFY'
      $ssl_protocols            = pick($serverssl_protos, '-ALL +TLSv1.2 +TLSv1.1 +TLSv1 +SSLv3')
      $ssl_ciphers              = pick($serverssl_ciphers, 'ALL:!ADH:!EXP:!LOW:+RC4:+HIGH:+MEDIUM:!SSLv2:+SSLv3:+TLSv1:+eNULL')
    }
    'unicorn': {
      include puppet::server::unicorn
      $ssl_client_header        = 'HTTP_X_CLIENT_DN'
      $ssl_client_verify_header = 'HTTP_X_CLIENT_VERIFY'
      $ssl_protocols            = pick($serverssl_protos, 'TLSv1.2 TLSv1.1 TLSv1 SSLv3')
      $ssl_ciphers              = pick($serverssl_ciphers, 'HIGH:!aNULL:!MD5')
    }
    'thin': {
      include puppet::server::thin
      $ssl_client_header        = 'HTTP_X_CLIENT_DN'
      $ssl_client_verify_header = 'HTTP_X_CLIENT_VERIFY'
      $ssl_protocols            = pick($serverssl_protos, 'TLSv1.2 TLSv1.1 TLSv1 SSLv3')
      $ssl_ciphers              = pick($serverssl_ciphers, 'HIGH:!aNULL:!MD5')
    }
    'standalone': {
      include puppet::server::standalone
    }
    default: {
      err('Only "passenger", "thin", "unicorn" and "standalone" are valid options for servertype')
      fail('Servertype "$servertype" not implemented')
    }
  }

  # ---
  # Storeconfigs
  if $storeconfigs {
    notify { 'storeconfigs is deprecated. Use manage_puppetdb setting.': }
    class { 'puppet::storeconfig':
      backend => $storeconfigs,
    }
  }

  # enable basic puppetdb using the puppetlabs-puppetdb module
  # this will also install postgresql
  # for more detailed control over puppetdb settings, use the puppetdb
  # module directly rather than having puppet-puppet include it.
  if $manage_puppetdb {
    include puppetdb
    include puppetdb::master::config
  }

}
