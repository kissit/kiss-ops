<?php
/*
 * kisslog.php
 *
 * Copyright (C) 2015 KISS IT Consulting <http://www.kissitconsulting.com/>
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above
 *    copyright notice, this list of conditions and the following
 *    disclaimer in the documentation and/or other materials
 *    provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL ANY
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
class kisslog {
	private $log_dir = '';
	private $log_file = '';
    private $debug_log = '';
	private $email_address = '';
	private $email_subject = '';
	private $display = '';
	private $summary_message = '';
	private $debug_flag = '';

	function __construct($opts = array()) {
		$this->log_dir = isset($opts['log_dir']) ? $opts['log_dir'] : realpath(dirname(__FILE__).'/../logs');
		$this->log_file	= "{$this->log_dir}/" . (isset($opts['log_file']) ? $opts['log_file'] : 'messages.log');
        $this->summary_log = "/tmp/kiss_summary.log";
		$this->debug_log = $this->log_dir . '/debug.log';
		$this->email_address = isset($opts['email_address']) ? $opts['email_address'] : '';
		$this->email_subject = isset($opts['email_subject']) ? $opts['email_subject'] : 'error log notification';
		$this->display = isset($opts['display']) ? $opts['display'] : true;
		$this->debug_flag = isset($opts['debug_flag']) ? $opts['debug_flag'] : false;
	}

    // Methods to set some things that we may want to toggle during processing for various reasons
	public function setDebug($debug) {
		$this->debug_flag = (bool)$debug;
	}
	public function setDisplay($display) {
		$this->display = (bool)$display;
	}
	public function setEmailAddress($email_address) {
		$this->email_address = (string)$email_address;
	}
	public function setEmailSubject($email_subject) {
		$this->email_subject = (string)$email_subject;
	}

    // Private methods to email, display, and write our messages as needed
    private function emailMessage($message) {
        if (!empty($this->email_address)) {
            mail($this->email_address, $this->email_subject, $message);
        }
    }
    private function displayMessage($message) {
        if ($this->display) {
            echo $message;
        }
    }
    private function writeMessage($message, $file = false) {
        $file = !empty($file) ? $file : $this->log_file;
        error_log($message, 3, $this->log_file);
    }

    // Method to log an error.  Can optionally have it sent as an email, execution stopped, 
    // and written to a summary log for batch processing
	public function error($message, $stop = false, $email_notif = false, $summary_log = false) {
		if (!empty($message)) {
			$message = date('Y-m-d H:i:s'). ": ERROR -> $message\n";
			$this->summary_message .= $message;
			
            $this->displayMessage($message);
            $this->writeMessage($message);			
            
            if($summary_log) {
                $this->writeMessage($message, $this->summary_log);
            }

            if($email_notif == true) {
                $this->emailMessage($message);
            }

			if ($stop === true) {
				exit();
			}
		}
	}
	
    // Method to log a message, no real special options here.
	public function message($message) {
		if (!empty($message)) {
			$message = date('Y-m-d H:i:s'). ": MESSAGE -> $message\n";
			$this->summary_message .= $message;
			$this->displayMessage($message);
            $this->writeMessage($message);
		}
	}

    // Method to put debug statements in your code that can be turned off but left in place at the cost of a single if check on a bool
	public function debug($message) {
		if($this->debug_flag && !empty($message)) {
			$message = date('Y-m-d H:i:s'). ": DEBUG -> $message\n";
			$this->summary_message .= $message;
			$this->displayMessage($message);
            $this->writeMessage($message);
		}
	}

    // Method to send a summary of all messages from a run of a given process.
	public function sendSummary($prepend = '') {
        if(!empty($prepend)) {
            $this->summary_message = $prepend . "\n\n" . $this->summary_message;
        }
        $this->emailMessage($this->summary_message);
	}
}
?>