<?php
/*
 * curl_ssl_test.php
 *
 * Copyright (C) 2016 KISS IT Consulting <http://www.kissitconsulting.com/>
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
 *
 * 
 * Instructions:
 * 1. To test the default configuration, simply run as is: php curl_ssl_test.php
 * 2. Or, to test a specific version, pass in the number corresponding to the CURL_SSLVERSION you wish to force.
 *    For example, to force TLSv1.2: php curl_ssl_test.php 6
 *
 * For reference, here are the current options
 * CURL_SSLVERSION_DEFAULT (0)
 * CURL_SSLVERSION_TLSv1 (1)
 * CURL_SSLVERSION_SSLv2 (2)
 * CURL_SSLVERSION_SSLv3 (3)
 * CURL_SSLVERSION_TLSv1_0 (4)
 * CURL_SSLVERSION_TLSv1_1 (5)
 * CURL_SSLVERSION_TLSv1_2 (6)
*/

$options = array (
    CURLOPT_URL => "https://www.howsmyssl.com/a/check",
    CURLOPT_RETURNTRANSFER => 1,
    CURLOPT_SSL_VERIFYPEER => false,
    CURLOPT_SSL_VERIFYHOST => false,
    CURLOPT_TIMEOUT => 30);

$force_version = 0;
if(isset($argv[1])) {
    $force_version = (int)$argv[1];
    if($force_version < 0 || $force_version > 6) {
        $force_version = 0;
    }
}

if($force_version > 0) {
    $options[CURLOPT_SSLVERSION] = $force_version;
}

$curl = curl_init();
curl_setopt_array($curl, $options);
$return = curl_exec($curl);

if(curl_errno($curl) > 0) {
    echo "CURL Error: " . curl_error($curl) . "\n";
} else {
    echo "Result: \n";
    var_dump(json_decode($return));
}
curl_close($curl);

?>
