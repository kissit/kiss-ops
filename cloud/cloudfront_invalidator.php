<?php
/*
 * cloudfront_invalidator.php
 *
 * Heavily inspired by: https://github.com/subchild/CloudFront-PHP-Invalidator but I wanted
 * something pure PHP that didn't require additional modules.
 * 
 * Example usage:
 * 1. require 'cloudfront_invalidator.php';
 * 2. $invalidator = new cloudfront_invalidator('AWS ACCESS KEY', 'AWS SECRET', 'CLOUDFRONT DIST ID');
 * 3.   try {
 *          $invalidator->invalidate('/images/*');
 *      } catch(Exception $e) {
 *          echo $e->getMessage() . "\n";
 *      }
 * 
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
class cloudfront_invalidator {
	private $url;
	private $access_key;
    private $secret_key;
    private $dist_id;
	private $response_code = 0;
    private $response = '';

	// Our standard constructor.  Pass in url to override the standard cloudfront URL.
	function __construct($access_key = null, $secret_key = null, $dist_id = null, $url = "https://cloudfront.amazonaws.com") {
		$this->setAwsInfo($access_key, $secret_key, $dist_id, $url);
	}

    // Function to invalidate either a single passed in key or an array of keys.
    // Returns true on success, otherwise an exception is raised.
	public function invalidate($keys) {
        // Validate that we have our AWS creds
        if(!$this->validateAws()) {
            throw new Exception("Required AWS credentials not provided");
        }

        // Make and send request using cURL
        $return = false;
        if (!is_array($keys)) {
            $keys = array($keys);
        }
        $this->call($keys);
        switch ($this->response_code) {
            case 201:
                $this->response = '201: Request accepted';
                $return = true;
                break;
            case 400:
                $this->response = '400: Too many invalidations in progress. Retry in some time';
                break;
            case 403:
                $this->response = '403: Forbidden. Please check your security settings.';
                break;
            default:
                $this->response = $response->response_code . ': Unhandled response code';
                break;
        }
        if(!$return) {
            throw new Exception($this->response);
        } else {
            return true;
        }
	}
    
    // Getter for the response code
    public function getResponseCode() {
        return $this->response_code;
    }

    // Getter for the response (or message)
    public function getResponse() {
        return $this->response;
    }
    
    // Set our AWS info
    public function setAwsInfo($access_key, $secret_key, $dist_id, $url = null) {
        $this->access_key = $access_key;
		$this->secret_key = $secret_key;
		$this->dist_id = $dist_id;
        if(!empty($url)) {
		    $this->url = $url;
        }
    }

    // Validate that we have our information needed to process the request
    private function validateAws() {
        if(empty($this->access_key) || empty($this->secret_key) || empty($this->dist_id) || empty($this->url)) {
            return false;
        } else {
            return true;
        }
    }

    // Function to make a web request to the API using cURL
    private function call($keys) {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, "{$this->url}/2012-07-01/distribution/{$this->dist_id}/invalidation");
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $this->getRequestHeaders());
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $this->makeRequestBody($keys));
        $result = curl_exec($ch);
        $info = curl_getinfo($ch);
        $this->response_code = $info['http_code'];
        $this->response = $result;
        curl_close($ch);
        return $result;
    }
    
    // Build the headers required by AWS for the request
    private function getRequestHeaders() {
        $date = gmdate("D, d M Y G:i:s T");
        $headers = array();
        $headers[] = "Host: cloudfront.amazonaws.com";
        $headers[] = "Date: $date";
        $headers[] = "Authorization: " . $this->generateAuthKey($date);
        $headers[] = "Content-Type: text/xml";
        return $headers;
    }

    // Function to build a request body as per AWS API
    private function makeRequestBody($objects) {
        $body = '<?xml version="1.0" encoding="UTF-8"?>';
        $body .= '<InvalidationBatch xmlns="http://cloudfront.amazonaws.com/doc/2012-07-01/">';
        $body .= '<Paths>';
        $body .= '<Quantity>' . count($objects) . '</Quantity>';
        $body .= '<Items>';
        foreach ($objects as $object) {
            $object = (preg_match("/^\//", $object)) ? $object : "/" . $object;
            $body .= "<Path>" . $object . "</Path>";
        }
        $body .= '</Items>';
        $body .= '</Paths>';
        $body .= "<CallerReference>" . time() . "</CallerReference>";
        $body .= "</InvalidationBatch>";
        return $body;
    }


    // Generate a header string containing encoded authentication key
    private function generateAuthKey($date) {
        $signature = base64_encode(hash_hmac('sha1', $date, $this->secret_key, true));
        return "AWS " . $this->access_key . ":" . $signature;
    }
}
?>
