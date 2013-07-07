/*
 * i-MSCP - internet Multi Server Control Panel
 * Copyright (C) 2010-2013 by i-MSCP team
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * @category  iMSCP
 * @package   iMSCP Roundcube auto-response plugin
 * @copyright 2010-2013 by i-MSCP team
 * @author    Peter Wyss
 * @link      http://www.i-mscp.net i-MSCP Home Site
 * @license   http://www.gnu.org/licenses/gpl-2.0.html GPL v2
 */

if (window.rcmail) {
	rcmail.addEventListener('init', function(evt) {
		var tab = $('<span>').attr('id', 'settingstabpluginimscp_autoresponder').addClass('tablink');
		var button = $('<a>').attr('href', rcmail.env.comm_path+'&_action=plugin.imscp_autoresponder').html(rcmail.gettext('autoresponder', 'imscp_autoresponder')).appendTo(tab);

		// add button and register commands
		rcmail.add_element(tab, 'tabs');
		rcmail.register_command('plugin.imscp_autoresponder-save', function() {
			rcmail.gui_objects.passform.submit();
		}, true);
	})
}
