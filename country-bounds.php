<!DOCTYPE html>
<html>
<head>
<title>Country bounds</title>
<meta charset="UTF-8" />
<script type="text/javascript" src="https://maps.googleapis.com/maps/api/js?sensor=false&libraries=places"></script>
</head>
<body><?php

ini_set("display_errors", "on");
ini_set('error_reporting', E_ALL);

$countries = array(
	'AF' => array( "Afghanistan", '33', '65', 'AFA' ),
	'AL' => array( "Albania", '41', '20', 'ALL' ),
	'DZ' => array( "Algeria", '28', '3', 'DZD' ),
	'AS' => array( "American Samoa", '-14.3333', '-170', 'USD' ),
	'AD' => array( "Andorra", '42.5', '1.6', 'EUR' ),
	'AI' => array( "Anguilla", '18.25', '-63.1667', 'XCD' ),
	'AO' => array( "Angola", '-12.5', '18.5', 'AON' ),
	'AG' => array( "Antigua and Barbuda", '17.05', '-61.8', 'XCD' ),
	'AR' => array( "Argentina", '-34', '-64', 'ARS' ),
	'AM' => array( "Armenia", '40', '45', 'AMD' ),
	'AW' => array( "Aruba", '12.5', '-69.9667', 'AWG' ),
	'AU' => array( "Australia", '-27', '133', 'AUD' ),
	'AT' => array( "Austria", '47.3333', '13.3333', 'EUR' ),
	'AZ' => array( "Azerbaijan", '40.5', '47.5', 'AZM' ),
	'BS' => array( "Bahamas", '24.25', '-76', 'BSD' ),
	'BH' => array( "Bahrain", '26', '50.55', 'BHD' ),
	'BD' => array( "Bangladesh", '24', '90', 'BDT' ),
	'BB' => array( "Barbados", '13.1667', '-59.5333', 'BBD' ),
	'BY' => array( "Belarus", '53', '28', 'BYB' ),
	'BE' => array( "Belgium", '50.8333', '4', 'EUR' ),
	'BZ' => array( "Belize", '17.25', '-88.75', 'BZD' ),
	'BJ' => array( "Benin", '9.5', '2.25', 'XOF' ),
	'BM' => array( "Bermuda", '32.3333', '-64.75', 'BMD' ),
	'BT' => array( "Bhutan", '27.5', '90.5', 'BTN' ),
	'BO' => array( "Bolivia", '-17', '-65', 'BOB' ),
	'BA' => array( "Bosnia and Herzegovina", '44', '18', 'BAM' ),
	'BW' => array( "Botswana", '-22', '24', 'BWP' ),
	'BR' => array( "Brazil", '-10', '-55', 'BRL' ),
	'IO' => array( "British Indian Ocean Territory", '-6', '71.5', 'USD' ),
	'BN' => array( "Brunei", '4.5', '114.6667', 'BND' ),
	'BG' => array( "Bulgaria", '43', '25', 'BGL' ),
	'BF' => array( "Burkina Faso", '13', '-2', 'XOF' ),
	'BI' => array( "Burundi", '-3.5', '30', 'BIF' ),
	'KH' => array( "Cambodia", '13', '105', 'KHR' ),
	'CM' => array( "Cameroon", '6', '12', 'XAF' ),
	'CA' => array( "Canada", '60', '-95', 'CAD' ),
	'CV' => array( "Cape Verde", '16', '-24', 'CVE' ),
	'KY' => array( "Cayman Islands", '19.5', '-80.5', 'KYD' ),
	'CF' => array( "Central African Republic", '7', '21', 'XAF' ),
	'TD' => array( "Chad", '15', '19', 'XAF' ),
	'CL' => array( "Chile", '-30', '-71', 'CLP' ),
	'CN' => array( "China", '35', '105', 'CNY' ),
	'CX' => array( "Christmas Island", '-10.5', '105.6667', 'AUD' ),
	'CC' => array( "Cocos Islands", '-12.5', '96.8333', 'AUD' ),
	'CO' => array( "Colombia", '4', '-72', 'COP' ),
	'KM' => array( "Comoros", '-12.1667', '44.25', 'KMF' ),
	'CK' => array( "Cook Islands", '-21.2333', '-159.7667', 'NZD' ),
	'CG' => array( "Congo", '-1', '15', 'XAF' ),
	'CR' => array( "Costa Rica", '10', '-84', 'CRC' ),
	'CI' => array( "Côte d'Ivoire", '8', '-5', 'XOF' ),
	'HR' => array( "Croatia", '45.1667', '15.5', 'HRK' ),
	'CU' => array( "Cuba", '21.5', '-80', 'CUP' ),
	'CY' => array( "Cyprus", '35', '33', 'CYP' ),
	'CZ' => array( "Czech Republic", '49.75', '15.5', 'CZK' ),
	'DK' => array( "Denmark", '56', '10', 'DKK' ),
	'DJ' => array( "Djibouti", '11.5', '43', 'DJF' ),
	'CD' => array( "Democratic Republic of the Congo", '0', '25', 'CDF' ),
	'DM' => array( "Dominica", '15.4167', '-61.3333', 'XCD' ),
	'DO' => array( "Dominican Republic", '19', '-70.6667', 'DOP' ),
	'EC' => array( "Ecuador", '-2', '-77.5', 'ECS' ),
	'EG' => array( "Egypt", '27', '30', 'EGP' ),
	'SV' => array( "El Salvador", '13.8333', '-88.9167', 'SVC' ),
	'GQ' => array( "Equatorial Guinea", '2', '10', 'XAF' ),
	'ER' => array( "Eritrea", '15', '39', 'ERN' ),
	'EE' => array( "Estonia", '59', '26', 'EEK' ),
	'ET' => array( "Ethiopia", '8', '38', 'ETB' ),
	'FJ' => array( "Fiji", '-18', '175', 'FJD' ),
	'FI' => array( "Finland", '64', '26', 'EUR' ),
	'FR' => array( "France", '46', '2', 'EUR' ),
	'GF' => array( "French Guiana", '4', '-53', '' ),
	'GA' => array( "Gabon", '-1', '11.75', 'XAF' ),
	'GM' => array( "Gambia", '13.4667', '-16.5667', 'GMD' ),
	'DE' => array( "Germany", '51', '9', 'EUR' ),
	'GH' => array( "Ghana", '8', '-2', 'GHC' ),
	'GL' => array( "Greenland", '72', '-40', 'DKK' ),
	'GR' => array( "Greece", '39', '22', 'EUR' ),
	'GD' => array( "Grenada", '12.1167', '-61.6667', 'XCD' ),
	'GU' => array( "Guam", '13.4667', '144.7833', 'USD' ),
	'GP' => array( "Guadeloupe", '16.25', '-61.5833', '' ),
	'GT' => array( "Guatemala", '15.5', '-90.25', 'QTQ' ),
	'GN' => array( "Guinea", '11', '-10', 'GNF' ),
	'GW' => array( "Guinea-Bissau", '12', '-15', 'XOF' ),
	'GY' => array( "Guyana", '5', '-59', 'GYD' ),
	'HT' => array( "Haiti", '19', '-72.4167', 'HTG' ),
	'HN' => array( "Honduras", '15', '-86.5', 'HNL' ),
	'HK' => array( "Hong Kong", '22.25', '114.1667', 'HKD' ),
	'HU' => array( "Hungary", '47', '20', 'HUF' ),
	'IS' => array( "Iceland", '65', '-18', 'ISK' ),
	'IN' => array( "India", '20', '77', 'INR' ),
	'ID' => array( "Indonesia", '-5', '120', 'IDR' ),
	'IR' => array( "Iran", '32', '53', 'IRR' ),
	'IQ' => array( "Iraq", '33', '44', 'IQD' ),
	'IE' => array( "Ireland", '53', '-8', 'EUR' ),
	'IL' => array( "Israel", '31.5', '34.75', 'ILS' ),
	'IT' => array( "Italy", '42.8333', '12.8333', 'EUR' ),
	'JM' => array( "Jamaica", '18.25', '-77.5', 'JMD' ),
	'JP' => array( "Japan", '36', '138', 'JPY' ),
	'JO' => array( "Jordan", '31', '36', 'JOD' ),
	'KZ' => array( "Kazakhstan", '48', '68', 'KZT' ),
	'KE' => array( "Kenya", '1', '38', 'KES' ),
	'KW' => array( "Kuwait", '29.3375', '47.6581', 'KWD' ),
	'KG' => array( "Kyrgyzstan", '41', '75', 'KGS' ),
	'LA' => array( "Laos", '18', '105', 'LAK' ),
	'LV' => array( "Latvia", '57', '25', 'LVL' ),
	'LB' => array( "Lebanon", '33.8333', '35.8333', 'LBP' ),
	'LS' => array( "Lesotho", '-29.5', '28.5', 'LSL' ),
	'LR' => array( "Liberia", '6.5', '-9.5', 'LRD' ),
	'LY' => array( "Libya", '25', '17', 'LYD' ),
	'LI' => array( "Liechtenstein", '47.1667', '9.5333', 'CHF' ),
	'LT' => array( "Lithuania", '56', '24', 'LTL' ),
	'LU' => array( "Luxembourg", '49.75', '6.1667', 'EUR' ),
	'MO' => array( "Macau", '22.1667', '113.55', 'MOP' ),
	'MK' => array( "Macedonia", '41.8333', '22', 'MKD' ),
	'MG' => array( "Madagascar", '-20', '47', 'MGF' ),
	'MW' => array( "Malawi", '-13.5', '34', 'MWK' ),
	'MY' => array( "Malaysia", '2.5', '112.5', 'MYR' ),
	'MV' => array( "Maldives", '3.25', '73', 'MVR' ),
	'ML' => array( "Mali", '17', '-4', 'XOF' ),
	'MT' => array( "Malta", '35.8333', '14.5833', 'MTL' ),
	'MH' => array( "Marshall Islands", '9', '168', 'USD' ),
	'MQ' => array( "Martinique", '14.6667', '-61', '' ),
	'MR' => array( "Mauritania", '20', '-12', 'MRO' ),
	'MU' => array( "Mauritius", '-20.2833', '57.55', 'MUR' ),
	'MX' => array( "Mexico", '23', '-102', 'MXN' ),
	'FM' => array( "Micronesia", '6.9167', '158.25', 'USD' ),
	'MD' => array( "Moldova", '47', '29', 'MDL' ),
	'MC' => array( "Monaco", '43.7333', '7.4', 'EUR' ),
	'MN' => array( "Mongolia", '46', '105', 'MNT' ),
	'ME' => array( "Montenegro", '42', '19', 'EUR' ),
	'MS' => array( "Montserrat", '16.75', '-62.2', '' ),
	'MA' => array( "Morocco", '32', '-5', 'MAD' ),
	'MZ' => array( "Mozambique", '-18.25', '35', 'MZM' ),
	'MM' => array( "Myanmar", '22', '98', 'MMK' ),
	'NA' => array( "Namibia", '-22', '17', 'NAD' ),
	'NR' => array( "Nauru", '-0.5333', '166.9167', 'AUD' ),
	'NP' => array( "Nepal", '28', '84', 'NPR' ),
	'NL' => array( "The Netherlands", '52.5', '5.75', 'EUR' ),
	'AN' => array( "Netherlands Antilles", '12.25', '-68.75', 'ANG' ),
	'NZ' => array( "New Zealand", '-36.84846', '174.76333', 'NZD' ),
	'NI' => array( "Nicaragua", '13', '-85', 'NIC' ),
	'NE' => array( "Niger", '16', '8', 'XOF' ),
	'NG' => array( "Nigeria", '10', '8', 'NGN' ),
	'NU' => array( "Niue", '-19.0333', '-169.8667', 'NZD' ),
	'MP' => array( "Northern Mariana Islands", '15.2', '145.75', 'USD' ),
	'KP' => array( "North Korea", '40', '127', 'KPW' ),
	'NO' => array( "Norway", '62', '10', 'NOK' ),
	'OM' => array( "Oman", '21', '57', 'OMR' ),
	'PK' => array( "Pakistan", '30', '70', 'PKR' ),
	'PW' => array( "Palau", '7.5', '134.5', 'USD' ),
	'PS' => array( "Palestinian Territories", '32', '35.25', 'ILS' ),
	'PA' => array( "Panama", '9', '-80', 'PAB' ),
	'PG' => array( "Papua New Guinea", '-6', '147', 'PGK' ),
	'PY' => array( "Paraguay", '-23', '-58', 'PYG' ),
	'PE' => array( "Peru", '-10', '-76', 'PEN' ),
	'PH' => array( "Philippines", '13', '122', 'PHP' ),
	'PN' => array( "Pitcairn Islands", '-24.7', '-127.4', 'NZD' ),
	'PL' => array( "Poland", '52', '20', 'PLZ' ),
	'PT' => array( "Portugal", '39.5', '-8', 'EUR' ),
	'QA' => array( "Qatar", '25.5', '51.25', 'QAR' ),
	'RO' => array( "Romania", '46', '25', 'ROL' ),
	'RU' => array( "Russia", '60', '100', 'RUB' ),
	'RW' => array( "Rwanda", '-2', '30', 'RWF' ),
	'SH' => array( "Saint Helena", '-15.9333', '-5.7', 'SHP' ),
	'KN' => array( "Saint Kitts and Nevis", '17.3333', '-62.75', 'XCD' ),
	'VC' => array( "Saint Vincent and the Grenadines", '13.25', '-61.2', 'XCD' ),
	'LC' => array( "Saint Lucia", '13.8833', '-61.1333', 'XCD' ),
	'WS' => array( "Samoa", '-13.5833', '-172.3333', 'WST' ),
	'SM' => array( "San Marino", '43.7667', '12.4167', 'EUR' ),
	'ST' => array( "São Tomé and Príncipe", '1', '7', 'STD' ),
	'SA' => array( "Saudi Arabia", '25', '45', 'SAR' ),
	'SN' => array( "Senegal", '14', '-14', 'XOF' ),
	'RS' => array( "Serbia", '44', '21', 'RSD' ),
	'SC' => array( "Seychelles", '-4.5833', '55.6667', 'SCR' ),
	'SL' => array( "Sierra Leone", '8.5', '-11.5', 'SLL' ),
	'SG' => array( "Singapore", '1.3667', '103.8', 'SGD' ),
	'SK' => array( "Slovakia", '48.6667', '19.5', 'SKK' ),
	'SI' => array( "Slovenia", '46', '15', 'EUR' ),
	'SB' => array( "Solomon Islands", '-8', '159', 'SBD' ),
	'SO' => array( "Somalia", '10', '49', 'SOD' ),
	'ZA' => array( "South Africa", '-29', '24', 'ZAR' ),
	'KR' => array( "South Korea", '37', '127.5', 'KRW' ),
	'ES' => array( "Spain", '40', '-4', 'EUR' ),
	'LK' => array( "Sri Lanka", '7', '81', 'LKR' ),
	'SD' => array( "Sudan", '15', '30', 'SDD' ),
	'SR' => array( "Suriname", '4', '-56', 'SRG' ),
	'SZ' => array( "Swaziland", '-26.5', '31.5', 'SZL' ),
	'SE' => array( "Sweden", '62', '15', 'SEK' ),
	'CH' => array( "Switzerland", '47', '8', 'CHF' ),
	'SY' => array( "Syria", '35', '38', 'SYP' ),
	'TW' => array( "Taiwan", '23.5', '121', 'TWD' ),
	'TJ' => array( "Tajikistan", '39', '71', 'TJR' ),
	'TZ' => array( "Tanzania", '-6', '35', 'TZS' ),
	'TH' => array( "Thailand", '15', '100', 'THB' ),
	'TL' => array( "Timor-Leste", '-8.55', '125.5167', 'USD' ),
	'TK' => array( "Tokelau", '-9', '-172', 'NZD' ),
	'TG' => array( "Togo", '8', '1.1667', 'XOF' ),
	'TO' => array( "Tonga", '-20', '-175', 'TOP' ),
	'TT' => array( "Trinidad and Tobago", '11', '-61', 'TTD' ),
	'TN' => array( "Tunisia", '34', '9', 'TND' ),
	'TR' => array( "Turkey", '39', '35', 'TRL' ),
	'TM' => array( "Turkmenistan", '40', '60', 'TMM' ),
	'TV' => array( "Tuvalu", '-8', '178', 'AUD' ),
	'UG' => array( "Uganda", '1', '32', 'UGS' ),
	'UA' => array( "Ukraine", '49', '32', 'UAG' ),
	'AE' => array( "United Arab Emirates", '24', '54', 'AED' ),
	'GB' => array( "United Kingdom", '54', '-2', 'GBP' ),
	'US' => array( "United States", '38', '-97', 'USD' ),
	'UY' => array( "Uruguay", '-33', '-56', 'UYP' ),
	'UZ' => array( "Uzbekistan", '41', '64', 'UZS' ),
	'WF' => array( "Wallis and Futuna", '-13.3', '-176.2', 'XPF' ),
	'VU' => array( "Vanuatu", '-16', '167', 'VUV' ),
	'VE' => array( "Venezuela", '8', '-66', 'VEB' ),
	'VN' => array( "Vietnam", '16', '106', 'VND' ),
	'YE' => array( "Yemen", '15', '48', 'YER' ),
	'ZM' => array( "Zambia", '-15', '30', 'ZMK' ),
	'ZW' => array( "Zimbabwe", '-20', '30', 'ZWD' )
);

?>
<script type="text/javascript">
	var geo = new google.maps.Geocoder();
	var i = 0;
	window.doGeo = function() {
		var j = c[i];
		geo.geocode( { 'address': j }, function(results, status) {
			document.body.innerHTML = document.body.innerHTML + j + ': ';
			if (status == google.maps.GeocoderStatus.OK) {
				var b = results[0].geometry.bounds;
				var sw = b.getSouthWest();
				var ne = b.getNorthEast();
				document.body.innerHTML = document.body.innerHTML + sw.lat() + ', ' + sw.lng() + ', ' + ne.lat() + ', ' + ne.lng() + '<br>\n';
			} else document.body.innerHTML = document.body.innerHTML + 'failed<br>\n';
		});
		i++;
		if( i == c.length ) return;
		window.setTimeout(window.doGeo,1000);
	}

	var c = [];
	var i = 0;
	<?php foreach( $countries as $i ) print "c.push(\"$i[0]\");\n"; ?>
	doGeo();

</script>
</body>
