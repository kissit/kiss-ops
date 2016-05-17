<?php
/*  CURLOPT_SSLVERSION
	One of CURL_SSLVERSION_DEFAULT (0), CURL_SSLVERSION_TLSv1 (1), CURL_SSLVERSION_SSLv2 (2), CURL_SSLVERSION_SSLv3 (3), CURL_SSLVERSION_TLSv1_0 (4), CURL_SSLVERSION_TLSv1_1 (5) or CURL_SSLVERSION_TLSv1_2 (6).
*/

$options = array (
    CURLOPT_URL => "https://www.howsmyssl.com/a/check",
    CURLOPT_RETURNTRANSFER => 1,
    CURLOPT_SSL_VERIFYPEER => false,
    CURLOPT_SSL_VERIFYHOST => false,
    CURLOPT_SSLVERSION => 6,
    CURLOPT_TIMEOUT => 60);

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
