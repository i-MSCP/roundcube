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
 * @author    Peter Wyss
 * @link      http://www.i-mscp.net i-MSCP Home Site
 * @license   http://www.gnu.org/licenses/gpl-2.0.html GPL v2
 */
define('AUTORESPONDER_ERROR', 2);
define('AUTORESPONDER_CONNECT_ERROR', 3);
define('AUTORESPONDER_SUCCESS', 0);

class imscp_autoresponder extends rcube_plugin{

	public $task = 'settings';

	function init(){
		$rcmail = rcmail::get_instance();
		// add Tab label
		$this->add_texts('localization/', true);
		//$rcmail->output->add_label('autoresponder');
		$this->register_action('plugin.imscp_autoresponder', array($this, 'autoresponder_init'));
		$this->register_action('plugin.imscp_autoresponder-save', array($this, 'autoresponder_save'));
		$this->include_script('autoresponder.js');
	}

	function autoresponder_init(){
		$this->add_texts('localization/');
		$this->register_handler('plugin.body', array($this, 'autoresponder_form'));

		$rcmail = rcmail::get_instance();
		$rcmail->output->set_pagetitle($this->gettext('editautoresponder'));
		$rcmail->output->send('plugin');
	}

	function autoresponder_save(){
		$rcmail = rcmail::get_instance();
		$this->load_config();

		$this->add_texts('localization/');
		$this->register_handler('plugin.body', array($this, 'autoresponder_form'));
		$rcmail->output->set_pagetitle($this->gettext('editautoresponder'));

		if (!isset($_POST['_enabled'])) {
			$enabled = false;
		}
		else {
			$enabled = get_input_value('_enabled', RCUBE_INPUT_POST) == '1' ? true : false;
		}
		
		if (!isset($_POST['_message'])) {
			$message = '';
		}
		else {
			$message = get_input_value('_message', RCUBE_INPUT_POST);
		}
		
		if ($enabled && trim($message) == '') {
			$rcmail->output->command('display_message', $this->gettext('nomessage'), 'error');
		}
		else {
		  if (!($res = $this->_save($enabled, $message))) {
			$rcmail->output->command('display_message', $this->gettext('successfullysaved'), 'confirmation');
		  } else
			$rcmail->output->command('display_message', $res, 'error');
		}

		rcmail_overwrite_action('plugin.imscp_autoresponder');
		$rcmail->output->send('plugin');
	}

	function autoresponder_form(){
		$rcmail = rcmail::get_instance();
		$this->load_config();

		$rcmail->output->set_env('product_name', $rcmail->config->get('product_name'));

		$current_values = $this->_load();
		
		if (is_array($current_values)) {
			$current_enabled = $current_values['enabled'] == '1';
			$current_message = $current_values['message'];
        }
		
		$table = new html_table(array('cols' => 2));

		// show message textbox
		$field_id = 'autoresponsemessage';
		$input_message = new html_textarea(array('name' => '_message', 'id' => $field_id,
		  'cols' => 40, 'rows' => 7));

		$table->add('title', html::label($field_id, Q($this->gettext('autorespondermessage'))));
		$table->add(null, $input_message->show($current_message));

		// show enable/disable checkbox
		$field_id = 'autoresponseenabled';
		$input_enabled = new html_checkbox(array('value' => 1, 'name' => '_enabled', 'id' => $field_id));

		$table->add('title', html::label($field_id, Q($this->gettext('enableautoresponder'))));
		$table->add(null, $input_enabled->show($current_enabled?1:0));

		$out = html::div(array('class' => 'box'),
		  html::div(array('id' => "prefs-title", 'class' => 'boxtitle'), $this->gettext('editautoresponder')) .
		  html::div(array('class' => 'boxcontent'), $table->show() .
			html::p(null,
			  $rcmail->output->button(array(
				'command' => 'plugin.imscp_autoresponder-save',
				'type' => 'input',
				'class' => 'button mainaction',
				'label' => 'save'
			)))
		  )
		);

		$rcmail->output->add_gui_object('passform', 'imscp_autoresponder-form');

		return $rcmail->output->form_tag(
			array(
				'id' => 'imscp_autoresponder-form',
				'name' => 'imscp_autoresponder-form',
				'method' => 'post',
				'action' => './?_task=settings&_action=plugin.imscp_autoresponder-save',
			),
			$out
		);
	}

	private function _load()
    {
        $config = rcmail::get_instance()->config;
        $driver = $config->get('autoresponder_driver', 'sql');
        $class  = "rcube_{$driver}_imscp_autoresponder";
        $file   = $this->home . "/drivers/$driver.php";
	
        if (!file_exists($file)) {
            raise_error(array(
                'code' => 600,
                'type' => 'php',
                'file' => __FILE__, 'line' => __LINE__,
                'message' => "Auto-Response plugin: Unable to open driver file ($file)"
            ), true, false);
            return $this->gettext('internalerror');
        }

        include_once $file;

        if (!class_exists($class, false) || !method_exists($class, 'load')) {
            raise_error(array(
                'code' => 600,
                'type' => 'php',
                'file' => __FILE__, 'line' => __LINE__,
                'message' => "Auto-Response plugin: Broken driver $driver"
            ), true, false);
            return $this->gettext('internalerror');
        }

        $object = new $class;
		return $object->load();
    }
	
	private function _save($enable, $message)
    {
        $config = rcmail::get_instance()->config;
        $driver = $config->get('autoresponder_driver', 'sql');
        $class  = "rcube_{$driver}_imscp_autoresponder";
        $file   = $this->home . "/drivers/$driver.php";

        if (!file_exists($file)) {
            raise_error(array(
                'code' => 600,
                'type' => 'php',
                'file' => __FILE__, 'line' => __LINE__,
                'message' => "Auto-Response plugin: Unable to open driver file ($file)"
            ), true, false);
            return $this->gettext('internalerror');
        }

        include_once $file;

        if (!class_exists($class, false) || !method_exists($class, 'save')) {
            raise_error(array(
                'code' => 600,
                'type' => 'php',
                'file' => __FILE__, 'line' => __LINE__,
                'message' => "Auto-Response plugin: Broken driver $driver"
            ), true, false);
            return $this->gettext('internalerror');
        }

        $object = new $class;
        $result = $object->save($enable, $message);

		switch ($result) {
			case AUTORESPONDER_SUCCESS:
				return;
			case AUTORESPONDER_CONNECT_ERROR;
				return $this->gettext('connecterror');
			case AUTORESPONDER_ERROR:
			default:
				return $this->gettext('internalerror');
		}

        return $reason;
    }
}
?>
