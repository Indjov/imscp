# i-MSCP Listener::Nginx::HSTS listener file
# Copyright (C) 2015-2017 Rene Schuster <mail@reneschuster.de>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA

#
## Add HTTP Strict Transport Security (HSTS) header field where appliable.
#

package Listener::Nginx::HSTS;

use strict;
use warnings;
use iMSCP::EventManager;
use iMSCP::TemplateParser;

return 1 unless defined $main::execmode && $main::execmode = 'setup';

iMSCP::EventManager->getInstance()->register(
    'afterFrontEndBuildConfFile',
    sub {
        my ($tplContent, $tplName) = @_;

        return 0 unless index($tplName, '00_master_ssl.conf') == 0;

        ${$tplContent} = replaceBloc(
            "# SECTION custom BEGIN.\n",
            "# SECTION custom END.\n",
            getBloc("# SECTION custom BEGIN.\n", "# SECTION custom END.\n", ${$tplContent})
                ."add_header Strict-Transport-Security max-age=31536000\n",
            ${$tplContent},
            'preserveTags'
        );

        0;
    }
);

1;
__END__
