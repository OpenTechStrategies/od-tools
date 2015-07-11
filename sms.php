<?php
/**
 * This receives notification from twilio that a txt to your virtual number has been received and emails it.
 * 
 * All the fields posted are as follows:
 *  'ToCountry' => 'US',
 *  'ToState' => 'CT',
 *  'SmsMessageSid' => 'SMfd8d335dad8b878e0366db3f88fc39ed',
 *  'NumMedia' => '0',
 *  'ToCity' => 'STAMFORD',
 *  'FromZip' => '07050',
 *  'SmsSid' => 'SMfd8d335dad8b878e0366db3f88fc39ed',
 *  'FromState' => 'NJ',
 *  'SmsStatus' => 'received',
 *  'FromCity' => 'ORANGE',
 *  'Body' => 'Your Ripple code is 8657884',
 *  'FromCountry' => 'US',
 *  'To' => '+12032930012',
 *  'ToZip' => '06880',
 *  'MessageSid' => 'SMfd8d335dad8b878e0366db3f88fc39ed',
 *  'AccountSid' => 'AC6183bc0b3c2ca8bed47c867998d010ae',
 *  'From' => '+12019030094',
 *  'ApiVersion' => '2010-04-01',
 */
mail(
	'aran@organicdesign.co.nz',
	'SMS message from ' . $_POST['From'],
	$_POST['Body']
);
