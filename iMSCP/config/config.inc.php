<?php

/*
 +-----------------------------------------------------------------------+
 | Local configuration for the i-MSCP Webmail installation.              |
 |                                                                       |
 | Copy more options from defaults.inc.php to this file to               |
 | override the defaults.                                                |
 |                                                                       |
 | This file is part of the Roundcube Webmail client                     |
 | Copyright (C) 2005-2013, The Roundcube Dev Team                       |
 |                                                                       |
 | Licensed under the GNU General Public License version 3 or            |
 | any later version with exceptions for skins & plugins.                |
 | See the README file for a full license statement.                     |
 +-----------------------------------------------------------------------+
*/

$config = array();

// Database connection string (DSN) for read+write operations
// Format (compatible with PEAR MDB2): db_provider://user:password@host/database
// Currently supported db_providers: mysql, pgsql, sqlite, mssql or sqlsrv
// For examples see http://pear.php.net/manual/en/package.database.mdb2.intro-dsn.php
// NOTE: for SQLite use absolute path: 'sqlite:////full/path/to/sqlite.db?mode=0646'
$config['db_dsnw'] = 'mysql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}';

// ----------------------------------
// LOGGING/DEBUGGING
// ----------------------------------

// Log successful/failed logins to <log_dir>/userlogins or to syslog
$config['log_logins'] = true;

// Log session authentication errors to <log_dir>/session or to syslog
$config['log_session'] = true;

// ----------------------------------
// IMAP
// ----------------------------------

// The mail host chosen to perform the log-in.
// Leave blank to show a textbox at login, give a list of hosts
// to display a pulldown menu or set one host as string.
// To use SSL/TLS connection, enter hostname with prefix ssl:// or tls://
// Supported replacement variables:
// %n - hostname ($_SERVER['SERVER_NAME'])
// %t - hostname without the first part
// %d - domain (http hostname $_SERVER['HTTP_HOST'] without the first part)
// %s - domain name after the '@' from e-mail address provided at login screen
// For example %n = mail.domain.tld, %t = domain.tld
// WARNING: After hostname change update of mail_host column in users table is
//          required to match old user data records with the new host.
$config['default_host'] = 'localhost';

// IMAP AUTH type (DIGEST-MD5, CRAM-MD5, LOGIN, PLAIN or null to use
// best server supported one)
$config['imap_auth_type'] = 'PLAIN';

// By default list of subscribed folders is determined using LIST-EXTENDED
// extension if available. Some servers (dovecot 1.x) returns wrong results
// for shared namespaces in this case. http://trac.roundcube.net/ticket/1486225
// Enable this option to force LSUB command usage instead.
// Deprecated: Use imap_disabled_caps = array('LIST-EXTENDED')
$config['imap_force_lsub'] = true;

// Log IMAP session identifiers after each IMAP login.
// This is used to relate IMAP session with Roundcube user sessions
$config['imap_log_session'] = true;

// Type of IMAP indexes cache. Supported values: 'db', 'apc' and 'memcache'.
$config['imap_cache'] = 'apc';

// ----------------------------------
// SMTP
// ----------------------------------

// SMTP server host (for sending mails).
// To use SSL/TLS connection, enter hostname with prefix ssl:// or tls://
// If left blank, the PHP mail() function is used
// Supported replacement variables:
// %h - user's IMAP hostname
// %n - hostname ($_SERVER['SERVER_NAME'])
// %t - hostname without the first part
// %d - domain (http hostname $_SERVER['HTTP_HOST'] without the first part)
// %z - IMAP domain (IMAP hostname without the first part)
// For example %n = mail.domain.tld, %t = domain.tld
$config['smtp_server'] = 'localhost';

// SMTP port (default is 25; use 587 for STARTTLS or 465 for the
// deprecated SSL over SMTP (aka SMTPS))
$config['smtp_port'] = 587;

// SMTP username (if required) if you use %u as the username Roundcube
// will use the current username for login
$config['smtp_user'] = '%u';

// SMTP password (if required) if you use %p as the password Roundcube
// will use the current user's password for login
$config['smtp_pass'] = '%p';

// SMTP AUTH type (DIGEST-MD5, CRAM-MD5, LOGIN, PLAIN or empty to use
// best server supported one)
$config['smtp_auth_type'] = 'PLAIN';

// ----------------------------------
// SYSTEM
// ----------------------------------

// use this folder to store temp files (must be writable for apache user)
$config['temp_dir'] = '{TMP_PATH}';

// Session lifetime in minutes
$config['session_lifetime'] = 20;

// this key is used to encrypt the users imap password which is stored
// in the session record (and the client cookie if remember password is enabled).
// please provide a string of exactly 24 chars.
$config['des_key'] = '{DES_KEY}';

// Encryption algorithm. You can use any method supported by openssl.
// Default is set for backward compatibility to DES-EDE3-CBC,
// but you can choose e.g. AES-256-CBC which we consider a better choice.
$config['cipher_method'] = 'AES-256-CBC';

// Name your service. This is displayed on the login screen and in the window title
$config['product_name'] = 'i-MSCP Webmail';

// Set identities access level:
// 0 - many identities with possibility to edit all params
// 1 - many identities with possibility to edit all params but not email address
// 2 - one identity with possibility to edit all params
// 3 - one identity with possibility to edit all params but not email address
// 4 - one identity with possibility to edit only signature
$config['identities_level'] = 3;

// Improve system security by using special URL with security token.
// This can be set to a number defining token length. Default: 16.
// Warning: This requires http server configuration. Sample:
//    RewriteRule ^/roundcubemail/[a-zA-Z0-9]{16}/(.*) /roundcubemail/$1 [PT]
//    Alias /roundcubemail /var/www/roundcubemail/
// Note: Use assets_path to not prevent the browser from caching assets
$config['use_secure_urls'] = true;

// ----------------------------------
// USER INTERFACE
// ----------------------------------

// automatically create the above listed default folders on first login
$config['create_default_folders'] = true;

// if in your system 0 quota means no limit set this option to true
$config['quota_zero_as_unlimited'] = true;

// Make use of the built-in spell checker. It is based on GoogieSpell.
// Since Google only accepts connections over https your PHP installation
// requires to be compiled with Open SSL support
$config['enable_spellcheck'] = true;
