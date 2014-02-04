<?php
/**
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
 * @author    Sascha Bay, Peter Wyss
 * @link      http://www.i-mscp.net i-MSCP Home Site
 * @license   http://www.gnu.org/licenses/gpl-2.0.html GPL v2
 */

class rcube_sql_imscp_autoresponder
{ 	 
	function load()
	{
		$rcmail = rcmail::get_instance();
		$sql = "SELECT mail_auto_respond AS enabled, mail_auto_respond_text AS message FROM `mail_users` WHERE `mail_addr` = %u LIMIT 1";

		if ($dsn = $rcmail->config->get('autoresponder_db_dsn')) {
            // #1486067: enable new_link option
            if (is_array($dsn) && empty($dsn['new_link']))
                $dsn['new_link'] = true;
            else if (!is_array($dsn) && !preg_match('/\?new_link=true/', $dsn))
                $dsn .= '?new_link=true';

			$db = rcube_db::factory($dsn, '', false);
			$db->set_debug((bool)$rcmail->config->get('sql_debug'));
			$db->db_connect('w');
		} else {
			return IMSCP_AUTORESPONDER_ERROR;
		}

		if ($err = $db->is_error()) {
			return IMSCP_AUTORESPONDER_ERROR;
		}

		$sql = str_replace('%u', $db->quote($_SESSION['username'], 'text'), $sql);

		$res = $db->query($sql);

		if (!$db->is_error() && $db->affected_rows($res) == 1) {
			return $db->fetch_assoc($res);
		}

		return IMSCP_AUTORESPONDER_ERROR;
	}
	 
	function save($enable, $message)
	{
		$rcmail = rcmail::get_instance();
		$sql = "UPDATE `mail_users` SET `mail_auto_respond` = %e, `mail_auto_respond_text` = %m, `status` = 'tochange' WHERE `mail_addr` = %u LIMIT 1";

		if ($dsn = $rcmail->config->get('autoresponder_db_dsn')) {
            // #1486067: enable new_link option
            if (is_array($dsn) && empty($dsn['new_link']))
                $dsn['new_link'] = true;
            else if (!is_array($dsn) && !preg_match('/\?new_link=true/', $dsn))
                $dsn .= '?new_link=true';

			$db = rcube_db::factory($dsn, '', false);
			$db->set_debug((bool)$rcmail->config->get('sql_debug'));
			$db->db_connect('w');
		} else {
			return IMSCP_AUTORESPONDER_ERROR;
		}

		if ($err = $db->is_error()) {
			return IMSCP_AUTORESPONDER_ERROR;
		}

		$sql = str_replace('%u', $db->quote($_SESSION['username'], 'text'), $sql);
		$sql = str_replace('%m', $db->quote($message, 'text'), $sql);
		$sql = str_replace('%e', $enable?1:0, $sql);

		$res = $db->query($sql);

		if (!$db->is_error() && $db->affected_rows($res) == 1) {
			if(!$this->imscp_send_request()) {
				return IMSCP_AUTORESPONDER_DAEMON_ERROR;
			} else {
				return IMSCP_AUTORESPONDER_SUCCESS;
			}
		}

		return IMSCP_AUTORESPONDER_ERROR;
	}

	/**
	 * Read an answer from i-MSCP daemon
	 *
	 * @param resource &$socket
	 * @return bool TRUE on success, FALSE otherwise
	 */
	function imscp_daemon_readAnswer(&$socket)
	{
		if(($answer = @socket_read($socket, 1024, PHP_NORMAL_READ)) !== false) {
			list($code) = explode(' ', $answer);
			if($code == '999') {
				return false;
			}
		} else {
			return false;
		}

		return true;
	}

	/**
	 * Send a command to i-MSCP daemon
	 *
	 * @param resource &$socket
	 * @param string $command Command
	 * @return bool TRUE on success, FALSE otherwise
	 */
	function imscp_daemon_sendCommand(&$socket, $command)
	{
		$command .= "\n";
		$commandLength = strlen($command);

		while (true) {
			if (($bytesSent = @socket_write($socket, $command, $commandLength)) !== false) {
				if ($bytesSent < $commandLength) {
					$command = substr($command, $bytesSent);
					$commandLength -= $bytesSent;
				} else {
					return true;
				}
			} else {
				return false;
			}
		}

		return false;
	}

	/**
	 * Send a request to the daemon
	 *
	 * @return bool TRUE on success, FALSE otherwise
	 */
	function imscp_send_request()
	{
		if(
			($socket = @socket_create(AF_INET, SOCK_STREAM, SOL_TCP)) !== false &&
			@socket_connect($socket, '127.0.0.1', 9876) !== false
		) {
			if(
				$this->imscp_daemon_readAnswer($socket) && // Read Welcome message from i-MSCP daemon
				$this->imscp_daemon_sendCommand($socket, "helo roundcube") && // Send helo command to i-MSCP daemon
				$this->imscp_daemon_readAnswer($socket) && // Read answer from i-MSCP daemon
				$this->imscp_daemon_sendCommand($socket, 'execute query') && // Send execute query command to i-MSCP daemon
				$this->imscp_daemon_readAnswer($socket) && // Read answer from i-MSCP daemon
				$this->imscp_daemon_sendCommand($socket, 'bye') && // Send bye command to i-MSCP daemon
				$this->imscp_daemon_readAnswer($socket) // Read answer from i-MSCP daemon
			) {
				$ret = true;
			} else {
				$ret = false;
			}

			socket_close($socket);
		} else {
			$ret = false;
		}

		return $ret;
	}
}
?>