=head1 NAME

 Package::WebmailClients::Roundcube::Handler - i-MSCP Roundcube package handler

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2019 Laurent Declercq <l.declercq@nuxwin.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

package Package::WebmailClients::Roundcube::Handler;

use strict;
use warnings;
use Class::Autouse qw/ :nostat iMSCP::Composer /;
use File::Spec;
use File::Temp;
use iMSCP::Boolean;
use iMSCP::Crypt qw/ decryptRijndaelCBC encryptRijndaelCBC randomStr /;
use iMSCP::Cwd '$CWD';
use iMSCP::Database;
use iMSCP::Debug qw/ debug error /;
use iMSCP::Dir;
use iMSCP::EventManager;
use iMSCP::Execute qw/ execute executeNoWait /;
use iMSCP::File;
use iMSCP::Rights 'setRights';
use iMSCP::Stepper qw/ startDetail endDetail step /;
use iMSCP::TemplateParser qw/ getBloc replaceBloc process /;
use Servers::sqld;
use parent 'Common::Object';

=head1 DESCRIPTION

 i-MSCP Roundcube package handler.

=head1 PUBLIC METHODS

=over 4

=item preinstall( )

 Pre-installation tasks

 Return int 0 on success, other on failure

=cut

sub preinstall
{
    my ( $self ) = @_;

    local $CWD = $::imscpConfig{'GUI_ROOT_DIR'};

    # Needed for scripts execution
    my $rs = $self->setGuiPermissions();
    return $rs if $rs;

    eval {
        my $composer = iMSCP::Composer->new(
            user                 => $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'},
            composer_home        => "$CWD/data/persistent/.composer",
            composer_working_dir => "$CWD/vendor/imscp/roundcube/roundcubemail",
            composer_json        => 'composer.json-dist'
        );
        $composer->setStdRoutines(
            sub {},
            sub {
                chomp( $_[0] );
                return unless length $_[0];

                debug( $_[0] );
                step( undef, <<"EOT", 2, 1 );
Installing/Updating Roundcube PHP dependencies...

$_[0]

Depending on your internet connection speed, this may take few seconds...
EOT
            }
        );

        $composer->dumpComposerJson();

        startDetail();

        # Install/Update Roundcube PHP dependencies
        $composer->update( TRUE );

        # Install Roundcube Javascript dependencies
        my $stderr;
        executeNoWait(
            $self->_getSuCmd(
                "$CWD/vendor/imscp/roundcube/roundcubemail/bin/install-jsdeps.sh"
            ),
            sub {
                chomp( $_[0] );
                return unless length $_[0];

                # See https://github.com/roundcube/roundcubemail/issues/6704
                die( sprintf(
                    "Couldn't install Roundcube Javascript dependencies: %s",
                    $_[0]
                )) if $_[0] =~ /^error/i;

                debug( $_[0] );
                step( undef, <<"EOT", 2, 2 );
Installing Roundcube Javascript dependencies...

$_[0]

Depending on your internet connection speed, this may take few seconds...
EOT
            },
            sub {
                chomp( $_[0] );
                return unless length $_[0];
                $stderr .= "$_[0]";
            }
        ) == 0 or die( sprintf(
            "Couldn't install Roundcube Javascript dependencies: %s", $stderr || 'Unknown error'
        ));
        endDetail();
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $self->{'events'}->register(
        'afterFrontEndBuildConfFile', \&afterFrontEndBuildConfFile
    );
}

=item install( )

 Installation tasks

 Return int 0 on success, other on failure

=cut

sub install
{
    my ( $self ) = @_;

    local $CWD = $::imscpConfig{'GUI_ROOT_DIR'};

    my $rs ||= $self->_buildConfigFiles();
    $rs ||= $self->_buildHttpdConfigFile();
    # Need to be done before database setup as the Roundcube scripts
    # rely on SQL user to create/update database.
    $rs ||= $self->_setupSqlUser();
    $rs ||= $self->_setupDatabase();
    return $rs if $rs;

    eval {
        iMSCP::Dir->new( dirname => "$CWD/data/logs/roundcube" )->make( {
            user           => $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'},
            group          => $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'},
            mode           => 0755,
            fixpermissions => TRUE
        } );
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item postinstall( )

 Post-installation tasks

 Return int 0 on success, other on failure

=cut

sub postinstall
{
    local $CWD = $::imscpConfig{'GUI_ROOT_DIR'};

    if ( -l "$CWD/public/tools/Roundcube" ) {
        my $rs = iMSCP::File->new(
            filename => "$CWD/public/tools/Roundcube"
        )->delFile();
        return $rs if $rs;
    }

    unless ( symlink( File::Spec->abs2rel(
        "$CWD/vendor/imscp/roundcube/roundcubemail/public_html", "$CWD/public/tools"
    ),
        "$CWD/public/tools/roundcube"
    ) ) {
        error( sprintf( "Couldn't create symlink for Roundcube webmail" ));
        return 1;
    }

    0;
}

=item uninstall( )

 Uninstallation tasks

 Return int 0 on success, other on failure

=cut

sub uninstall
{
    my ( $self ) = @_;

    local $CWD = $::imscpConfig{'GUI_ROOT_DIR'};

    if ( -l "$CWD/public/tools/roundcube" ) {
        my $rs = iMSCP::File->new(
            filename => "$CWD/public/tools/roundcube"
        )->delFile();
        return $rs if $rs;
    }

    if ( -f '/etc/nginx/imscp_roundcube.conf' ) {
        my $rs = iMSCP::File->new(
            filename => '/etc/nginx/imscp_roundcube.conf'
        )->delFile();
        return $rs if $rs;
    }

    eval {
        iMSCP::Dir->new( dirname => "$CWD/data/logs/roundcube" )->remove();

        local $self->{'dbh'}->{'RaiseError'} = TRUE;

        $self->{'dbh'}->do(
            "DROP DATABASE IF EXISTS @{ [ $self->{'dbh'}->quote_identifier( $::imscpConfig{'DATABASE_NAME'} . '_roundcube' ) ] }"
        );

        my ( $databaseUser ) = @{ $self->{'dbh'}->selectcol_arrayref(
            "SELECT `value` FROM `config` WHERE `name` = 'ROUNDCUBE_SQL_USER'"
        ) };

        if ( defined $databaseUser ) {
            $databaseUser = decryptRijndaelCBC(
                $::imscpDBKey, $::imscpDBiv, $databaseUser
            );

            for my $host (
                $::imscpOldConfig{'DATABASE_USER_HOST'},
                $::imscpConfig{'DATABASE_USER_HOST'}
            ) {
                next unless length $host;
                Servers::sqld->factory()->dropUser( $databaseUser, $host );
            }
        }

        $self->{'dbh'}->do(
            "DELETE FROM `config` WHERE `name` LIKE 'ROUNDCUBE_%'"
        );
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item setGuiPermissions

 Set GUI permissions

 Return int 0 on success, other on failure

=cut

sub setGuiPermissions
{
    local $CWD = $::imscpConfig{'GUI_ROOT_DIR'};

    setRights( "$CWD/vendor/imscp/roundcube/roundcubemail/bin", {
        dirmode   => '0755',
        filemode  => '0755',
        recursive => TRUE
    } );
}

=item deleteMail( \%moduleData )

 Process deleteMail tasks
 Param hashref \%moduleData Data as provided by the Mail module
 Return int 0 on success, other on failure 

=cut

sub deleteMail
{
    my ( $self, $moduleData ) = @_;

    return unless $moduleData->{'MAIL_TYPE'} =~ /_mail/;

    eval {
        local $self->{'dbh'}->{'RaiseError'} = TRUE;
        $self->{'dbh'}->do(
            "
                DELETE FROM @{ [ $self->{'dbh'}->quote_identifier( $::imscpConfig{'DATABASE_NAME'} . '_roundcube' ) ] }.`users`
                WHERE `username` = ?
            ",
            undef,
            $moduleData->{'MAIL_ADDR'}
        );
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    1;
}

=back

=head1 EVENT LISTENERS

=over 4

=item afterFrontEndBuildConfFile( )

 Event listener that injects Httpd configuration for Roundcube into the i-MSCP
 control panel Nginx vhost files

 Return int 0 on success, other on failure

=cut

sub afterFrontEndBuildConfFile
{
    my ( $tplContent, $tplName ) = @_;

    return 0 unless grep (
        $_ eq $tplName, '00_master.nginx', '00_master_ssl.nginx'
    );

    ${ $tplContent } = replaceBloc(
        "# SECTION custom BEGIN.\n",
        "# SECTION custom END.\n",
        "    # SECTION custom BEGIN.\n"
            . getBloc(
                "# SECTION custom BEGIN.\n",
                "# SECTION custom END.\n",
                ${ $tplContent }
            )
            . "    include imscp_roundcube.conf;\n"
            . "    # SECTION custom END.\n",
        ${ $tplContent }
    );

    0;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _init( )

 Initialize instance

 Return Package::WebmailClients::Roundcube::Handler

=cut

sub _init
{
    my ( $self ) = @_;

    $self->{'events'} = iMSCP::EventManager->getInstance();
    $self->{'dbh'} = iMSCP::Database->factory()->getRawDb();
    $self;
}

=item _buildConfigFiles( )

 Build PhpMyadminConfiguration files 

 Return int 0 on success, other on failure
  
=cut

sub _buildConfigFiles
{
    my ( $self ) = @_;

    my $rs = eval {
        local $self->{'dbh'}->{'RaiseError'} = TRUE;

        my %config = @{ $self->{'dbh'}->selectcol_arrayref(
            "SELECT `name`, `value` FROM `config` WHERE `name` LIKE 'ROUNDCUBE_%'",
            { Columns => [ 1, 2 ] }
        ) };

        ( $config{'ROUNDCUBE_DES_KEY'} = decryptRijndaelCBC(
            $::imscpDBKey, $::imscpDBiv, $config{'ROUNDCUBE_DES_KEY'} // ''
        ) || randomStr( 24, iMSCP::Crypt::ALPHA64 ) );

        ( $config{'ROUNDCUBE_SQL_USER'} = decryptRijndaelCBC(
            $::imscpDBKey, $::imscpDBiv, $config{'ROUNDCUBE_SQL_USER'} // ''
        ) || 'roundcube_' . randomStr( 6, iMSCP::Crypt::ALPHA64 ) );

        ( $config{'ROUNDCUBE_SQL_USER_PASSWD'} = decryptRijndaelCBC(
            $::imscpDBKey,
            $::imscpDBiv,
            $config{'ROUNDCUBE_SQL_USER_PASSWD'} // ''
        ) || randomStr( 16, iMSCP::Crypt::ALPHA64 ) );

        (
            $self->{'_roundcube_sql_user'},
            $self->{'_roundcube_control_user_passwd'}
        ) = (
            $config{'ROUNDCUBE_SQL_USER'}, $config{'ROUNDCUBE_SQL_USER_PASSWD'}
        );

        local $self->{'dbh'}->{'RaiseError'} = TRUE;
        $self->{'dbh'}->do(
            '
                INSERT INTO `config` (`name`,`value`)
                VALUES (?,?),(?,?),(?,?)
                ON DUPLICATE KEY UPDATE `name` = `name`
            ',
            undef,
            'ROUNDCUBE_DES_KEY',
            encryptRijndaelCBC(
                $::imscpDBKey, $::imscpDBiv, $config{'ROUNDCUBE_DES_KEY'}
            ),
            'ROUNDCUBE_SQL_USER',
            encryptRijndaelCBC(
                $::imscpDBKey, $::imscpDBiv, $config{'ROUNDCUBE_SQL_USER'}
            ),
            'ROUNDCUBE_SQL_USER_PASSWD',
            encryptRijndaelCBC(
                $::imscpDBKey,
                $::imscpDBiv,
                $config{'ROUNDCUBE_SQL_USER_PASSWD'}
            )
        );

        my $data = {
            DES_KEY           => $config{'ROUNDCUBE_DES_KEY'},
            DATABASE_HOSTNAME => ::setupGetQuestion( 'DATABASE_HOST' ),
            DATABASE_PORT     => ::setupGetQuestion( 'DATABASE_PORT' ),
            DATABASE_NAME     => ::setupGetQuestion( 'DATABASE_NAME' ) . '_roundcube',
            DATABASE_USER     => $config{'ROUNDCUBE_SQL_USER'},
            DATABASE_PASSWORD => $config{'ROUNDCUBE_SQL_USER_PASSWD'},
            LOG_DIR           => $CWD . '/data/logs/roundcube',
            TMP_DIR           => $CWD . '/data/tmp/'
        };

        my $rs = $self->{'events'}->trigger(
            'onLoadTemplate', 'roundcube', 'config.inc.php', \my $cfgTpl, $data
        );
        return $rs if $rs;

        unless ( defined $cfgTpl ) {
            $cfgTpl = iMSCP::File->new(
                filename => "$CWD/vendor/imscp/roundcube/src/config.inc.php"
            )->get();
            return 1 unless defined $cfgTpl;
        }

        $cfgTpl = process( $data, $cfgTpl );

        my $file = iMSCP::File->new(
            filename => "$CWD/vendor/imscp/roundcube/roundcubemail/config/config.inc.php"
        );
        $file->set( $cfgTpl );
        $rs = $file->save();
        $rs ||= $file->owner(
            $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'},
            $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'}
        );

        # Cron and logrotate configuration files
        for my $dir ( 'cron.d', 'logrotate.d' ) {
            next unless -f "$CWD/vendor/imscp/roundcube/src/$dir/imscp_roundcube";

            my $fileC = iMSCP::File->new(
                filename => "$CWD/vendor/imscp/roundcube/src/$dir/imscp_roundcube"
            )->getAsRef();

            ${ $fileC } = process(
                {
                    GUI_ROOT_DIR => $CWD,
                    USER         => $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'},
                    GROUP        => $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'}
                },
                ${ $fileC }
            );

            $file = iMSCP::File->new( filename => "/etc/$dir/imscp_roundcube" );
            $file->set( ${ $fileC } );
            $rs = $file->save();
            return $rs if $rs;
        }

        0;
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $rs;
}

=item _buildHttpdConfigFile( )

 Build httpd configuration file for Roundcube 

 Return int 0 on success, other on failure

=cut

sub _buildHttpdConfigFile
{
    my $rs = iMSCP::File->new(
        filename => "$CWD/vendor/imscp/roundcube/src/nginx.conf"
    )->copyFile( '/etc/nginx/imscp_roundcube.conf' );
    return $rs if $rs;

    my $file = iMSCP::File->new( filename => '/etc/nginx/imscp_roundcube.conf' );
    return 1 unless defined( my $fileC = $file->getAsRef());

    ${ $fileC } = process( { GUI_ROOT_DIR => $CWD }, ${ $fileC } );

    $file->save();
}

=item _setupSqlUser( )

 Setup SQL user for Roundcube 

 Return int 0 on success, other on failure

=cut

sub _setupSqlUser
{
    my ( $self ) = @_;

    eval {
        my $database = ::setupGetQuestion( 'DATABASE_NAME' ) . '_roundcube';
        my $dbUserHost = ::setupGetQuestion( 'DATABASE_USER_HOST' );
        my $sqlServer = Servers::sqld->factory();

        for my $host ( $::imscpOldConfig{'DATABASE_USER_HOST'}, $dbUserHost ) {
            next unless length $host;
            $sqlServer->dropUser( $self->{'_roundcube_sql_user'}, $host );
        }

        $sqlServer->createUser(
            $self->{'_roundcube_sql_user'},
            $dbUserHost,
            $self->{'_roundcube_control_user_passwd'}
        );

        local $self->{'dbh'}->{'RaiseError'} = TRUE;

        # Grant 'all' privileges on the imscp_roundcube database
        # No need to escape wildcard characters.
        $self->{'dbh'}->do(
            "
                GRANT ALL PRIVILEGES ON @{ [ $self->{'dbh'}->quote_identifier( $database =~ s/([%_])/\\$1/gr ) ] }.*
                TO ?\@?
            ",
            undef,
            $self->{'_roundcube_sql_user'},
            $dbUserHost
        );

        # Grant 'select' privileges on the imscp.mail table
        # No need to escape wildcard characters.
        # See https://bugs.mysql.com/bug.php?id=18660
        $self->{'dbh'}->do(
            "
                GRANT SELECT (`mail_addr`, `mail_pass`), UPDATE (`mail_pass`)
                ON @{ [ $self->{'dbh'}->quote_identifier( ::setupGetQuestion( 'DATABASE_NAME' )) ] }.`mail_users`
                TO ?\@?
            ",
            undef,
            $self->{'_roundcube_sql_user'},
            $dbUserHost
        );
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item _setupDatabase( )

 Setup datbase for Roundcube

 Return int 0 on success, other on failure

=cut

sub _setupDatabase
{
    my ( $self ) = @_;

    eval {
        local $self->{'dbh'}->{'RaiseError'} = TRUE;

        my $database = ::setupGetQuestion( 'DATABASE_NAME' ) . '_roundcube';
        my $quotedDatabase = $self->{'dbh'}->quote_identifier( $database );

        if ( !$self->{'dbh'}->selectrow_hashref( 'SHOW DATABASES LIKE ?', undef, $database )
            || !$self->{'dbh'}->selectrow_hashref( "SHOW TABLES FROM $quotedDatabase" )
        ) {
            $self->{'dbh'}->do(
                "
                    CREATE DATABASE IF NOT EXISTS $quotedDatabase
                    CHARACTER SET utf8 COLLATE utf8_unicode_ci
                "
            );

            # Create Roundcube database
            my $rs = execute(
                $self->_getSuCmd(
                    "$CWD/vendor/imscp/roundcube/roundcubemail/bin/initdb.sh",
                    '--dir', "$CWD/vendor/imscp/roundcube/roundcubemail/SQL",
                    '--package', 'roundcube'
                ),
                \my $stdout,
                \my $stderr
            );
            debug( $stdout ) if length $stdout;
            $rs == 0 or die( $stderr || 'Unknown error' );
        } else {
            # Update Roundcube database
            my $rs = execute(
                $self->_getSuCmd(
                    "$CWD/vendor/imscp/roundcube/roundcubemail/bin/updatedb.sh",
                    '--dir', "$CWD/vendor/imscp/roundcube/roundcubemail/SQL",
                    '--package', 'roundcube'
                ),
                \my $stdout,
                \my $stderr
            );
            debug( $stdout ) if length $stdout;
            $rs == 0 or die( $stderr || 'Unknown error' );

            # Ensure tha `users`.`mail_host` entries are set with expected hostname
            my $hostname = 'localhost';
            $self->{'events'}->trigger(
                'beforeUpdateRoundCubeMailHostEntries', \$hostname
            );

            $self->{'dbh'}->do(
                "UPDATE IGNORE $quotedDatabase.`users` SET `mail_host` = ?",
                undef,
                $hostname
            );
            $self->{'dbh'}->do(
                "DELETE FROM $quotedDatabase.`users` WHERE `mail_host` <> ?",
                undef,
                $hostname
            );
        }
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item _getSuCmd( @_ )

 Return SU command

 Param list @_ Command
 Return array command

=cut

sub _getSuCmd
{
    shift;

    [
        '/bin/su',
        '-l', $::imscpConfig{'SYSTEM_USER_PREFIX'} . $::imscpConfig{'SYSTEM_USER_MIN_UID'},
        '-s', '/bin/sh',
        '-c', "@_"
    ];
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
