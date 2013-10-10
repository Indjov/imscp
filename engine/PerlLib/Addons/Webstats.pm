#!/usr/bin/perl

=head1 NAME

Addons::Webstats - i-MSCP Webstats addon

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2013 by internet Multi Server Control Panel
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# @category    i-MSCP
# @copyright   2010-2013 by i-MSCP | http://i-mscp.net
# @author      Laurent Declercq <l.declercq@nuxwin.com>
# @link        http://i-mscp.net i-MSCP Home Site
# @license     http://www.gnu.org/licenses/gpl-2.0.html GPL v2

package Addons::Webstats;

use strict;
use warnings;

use iMSCP::Debug;
use iMSCP::Getopt;
use iMSCP::Execute;
use parent 'Common::SingletonClass';

=head1 DESCRIPTION

 Webstats addon for i-MSCP.

 This addon provide Web statistics for i-MSCP customers. For now only AWStats is available.

=head1 PUBLIC METHODS

=over 4

=item registerSetupHooks(\%hooksManager)

 Register Webstats setup hook functions.

 Param iMSCP::HooksManager instance
 Return int 0 on success, 1 on failure

=cut

sub registerSetupHooks($$)
{
	my ($self, $hooksManager) = @_;

	$hooksManager->register(
		'beforeSetupDialog', sub { my $dialogStack = shift; push(@$dialogStack, sub { $self->showDialog(@_) }); 0; }
	);
}

=item showDialog(\%dialog)

 Show Webstats addon question.

 Param iMSCP::Dialog::Dialog|iMSCP::Dialog::Whiptail $dialog
 Return int 0 or 30

=cut

sub showDialog($$)
{
	my ($self, $dialog, $rs) = (shift, shift, 0);

	my $addons = [split ',', main::setupGetQuestion('WEBSTATS_ADDONS')];

	if(
		$main::reconfigure ~~ ['webstats', 'all', 'forced'] || ! @{$addons} ||
		grep { not $_ ~~ ['Awstats', 'No'] } @{$addons}
	) {
		($rs, $addons) = $dialog->checkbox(
			"\nPlease, select the Webstats addon you want install:",
			['Awstats'],
			('No' ~~ @{$addons}) ? () : (@{$addons} ? @{$addons} : ('Awstats'))
		);
	}

	if($rs != 30) {
		main::setupSetQuestion('WEBSTATS_ADDONS', (@{$addons}) ? join ',', @{$addons} : 'No');

		if(not 'No' ~~ @{$addons}) {
			for(@{$addons}) {
				my $addon = "Addons::Webstats::${_}::Installer";
				eval "require $addon";

				if(! $@) {
					$addon =  $addon->getInstance();
					$rs = $addon->showDialog($dialog) if $addon->can('showDialog');
					last if $rs;
				} else {
					error($@);
					return 1;
				}
			}
		}
	}

	$rs;
}

=item preinstall()

 Process Webstats addon preinstall tasks.

 Note: This method also trigger uninstallation of unselected Webstats addons.

 Return int 0 on success, other on failure

=cut

sub preinstall
{
	my $self = shift;

	my $rs = 0;
	my @addons = split ',', main::setupGetQuestion('WEBSTATS_ADDONS');
	my $addonsToInstall = [grep { $_ ne 'No'} @addons];
	my $addonsToUninstall = [grep { not $_ ~~  @{$addonsToInstall}} ('Awstats')];

	if(@{$addonsToUninstall}) {
		my $packages = [];

		for(@{$addonsToUninstall}) {
			my $addon = "Addons::Webstats::${_}::Uninstaller";
			eval "require $addon";

			if(! $@) {
				$addon = $addon->getInstance();
				$rs = $addon->uninstall(); # Mandatory method
				return $rs if $rs;

				@{$packages} = (@{$packages}, @{$addon->getPackages()}) if $addon->can('getPackages');
			} else {
				error($@);
				return 1;
			}
		}

		$rs = $self->_removePackages($packages) if @${packages};
		return $rs if $rs;
	}

	if(@{$addonsToInstall}) {
		my $packages = [];

		for(@{$addonsToInstall}) {

			my $addon = "Addons::Webstats::${_}::Installer";
			eval "require $addon";

			if(! $@) {
				$addon = $addon->getInstance();
				$rs = $addon->preinstall() if $addon->can('preinstall');
				return $rs if $rs;

				@{$packages} = (@{$packages}, @{$addon->getPackages()}) if $addon->can('getPackages');
			} else {
				error($@);
				return 1;
			}
		}

		$rs = $self->_installPackages($packages) if @{$packages};
		return $rs if $rs;
	}

	$rs;
}

=item install()

 Process Webstats addon install tasks.

 Return int 0 on success, other on failure

=cut

sub install
{
	my @addons = split ',', main::setupGetQuestion('WEBSTATS_ADDONS');

	if(not 'No' ~~ @addons) {
		for(@addons) {
			my $addon = "Addons::Webstats::${_}::Installer";
			eval "require $addon";

			if(! $@) {
				$addon = $addon->getInstance();
				my $rs = $addon->install() if $addon->can('install');
				return $rs if $rs;
			} else {
				error($@);
				return 1;
			}
		}
	}

	0;
}

=item setGuiPermissions()

 Set Webstats addon files permissions.

 Return int 0 on success, other on failure

=cut

sub setGuiPermissions
{
	my @addons = split ',', $main::imscpConfig{'WEBSTATS_ADDONS'};

	if(not 'No' ~~ @addons) {
		for(@addons) {
			my $addon = "Addons::Webstats::${_}::Installer";
			eval "require $addon";

			if(! $@) {
				$addon = $addon->getInstance();
				my $rs = $addon->setGuiPermissions() if $addon->can('setGuiPermissions');
				return $rs if $rs;
			} else {
				error($@);
				return 1;
			}
		}
	}

	0;
}

=item setEnginePermissions()

 Set Webstats addon files permissions.

 Return int 0 on success, other on failure

=cut

sub setEnginePermissions
{
	my @addons = split ',', $main::imscpConfig{'WEBSTATS_ADDONS'};

	if(not 'No' ~~ @addons) {
		for(@addons) {
			my $addon = "Addons::Webstats::${_}::Installer";
			eval "require $addon";

			if(! $@) {
				$addon = $addon->getInstance();
				my $rs = $addon->setEnginePermissions() if $addon->can('setEnginePermissions');
				return $rs if $rs;
			} else {
				error($@);
				return 1;
			}
		}
	}

	0;
}

=item preaddDmn(\%data)

 Process preAddDmn tasks.

 Param hash_ref $data A reference to a hash containing domain data
 Return int 0 on success, other on failure

=cut

sub preaddDmn($$)
{
	my ($self, $data) = @_;

	if($data->{'FORWARD'} eq 'no') {
		my @addons = split ',', $main::imscpConfig{'WEBSTATS_ADDONS'};

		if(not 'No' ~~ @addons) {
			for(@addons) {
				my $addon = "Addons::Webstats::${_}::Awstats";
				eval "require $addon";

				if(! $@) {
					$addon = $addon->getInstance();
					my $rs = $addon->preaddDmn($data) if $addon->can('preaddDmn');
					return $rs if $rs;
				} else {
					error($@);
					return 1;
				}
			}
		}
	}

	0;
}

=item addDmn(\%data)

 Process addDmn tasks.

 Return int 0 on success, other on failure

=cut

sub addDmn($$)
{
	my ($self, $data) = @_;

	my @addons = split ',', $main::imscpConfig{'WEBSTATS_ADDONS'};

	if(not 'No' ~~ @addons) {
		if($data->{'FORWARD'} eq 'no') {
			for(@addons) {
				my $addon = "Addons::Webstats::${_}::Awstats";
				eval "require $addon";

				if(! $@) {
					$addon = $addon->getInstance();
					my $rs = $addon->addDmn($data) if $addon->can('addDmn');
					return $rs if $rs;
				} else {
					error($@);
					return 1;
				}
			}
		}
	}

	0;
}

=item deleteDmn(\%data)

 Process deleteDmn tasks.

 Return int 0 on success, other on failure

=cut

sub deleteDmn($$)
{
	my ($self, $data) = @_;

	my @addons = split ',', $main::imscpConfig{'WEBSTATS_ADDONS'};

	if(not 'No' ~~ @addons) {
		if($data->{'FORWARD'} eq 'no') {
			for(@addons) {
				my $addon = "Addons::Webstats::${_}::Awstats";
				eval "require $addon";

				if(! $@) {
					$addon = $addon->getInstance();
					my $rs = $addon->deleteDmn($data) if $addon->can('deleteDmn');
					return $rs if $rs;
				} else {
					error($@);
					return 1;
				}
			}
		}
	}

	0;
}

=item preaddSub(\%data)

 Process preaddSub tasks.

 Return int 0 on success, other on failure

=cut

sub preaddSub($$)
{
	my ($self, $data) = @_;

	$self->preaddDmn($data);
}

=item addSub(\%data)

 Process addSub tasks.

 Return int 0 on success, other on failure

=cut

sub addSub($$)
{
	my ($self, $data) = @_;

	$self->addDmn($data);
}

=item deleteSub(\%data)

 Process deleteSub tasks.

 Return int 0 on success, other on failure

=cut

sub deleteSub($$)
{
	my ($self, $data) = @_;

	$self->deleteDmn($data);
}

=back

=head1 PRIVATE METHODS

=over 4

=item _installPackages(\@packages)

 Install AWStats addon packages.

 Param array_ref $packages List of packages to install
 Return int 0 on success, other on failure

=cut

sub _installPackages($$)
{
	my ($self, $packages) = @_;

	my $command = 'apt-get';
	my $preseed = iMSCP::Getopt->preseed;

	iMSCP::Dialog->factory()->endGauge();

	$command = 'debconf-apt-progress --logstderr -- ' . $command if ! $preseed && ! $main::noprompt;

	my ($stdout, $stderr);
	my $rs = execute(
		"$command -y -o DPkg::Options::='--force-confdef' install @{$packages} --auto-remove --purge",
		($preseed || $main::noprompt) ? \$stdout : undef, \$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	error('Unable to install anti-rootkits packages') if $rs && ! $stderr;

	$rs;
}

=item _removePackages(\@packages)

 Remove AWStats addon packages.

 Param array_ref $packages List of packages to remove
 Return int 0 on success, other on failure

=cut

sub _removePackages($$)
{
	my ($self, $packages) = @_;

	my $command = 'apt-get';
	my $preseed = iMSCP::Getopt->preseed;

	iMSCP::Dialog->factory()->endGauge();

	$command = 'debconf-apt-progress --logstderr -- ' . $command if ! $preseed && ! $main::noprompt;

	my ($stdout, $stderr);
	my $rs = execute(
		"$command -y remove @{$packages} --auto-remove --purge",
		($preseed || $main::noprompt) ? \$stdout : undef, \$stderr
	);
	debug($stdout) if $stdout;
	error($stderr) if $stderr && $rs;
	error('Unable to remove anti-rootkits addons packages') if $rs && ! $stderr;

	$rs;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
