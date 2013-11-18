#!/usr/bin/python2.7
import urllib2, json
print "$%.2f" % float(json.loads(urllib2.urlopen('https://mtgox.com/api/1/BTCUSD/ticker').read())['return']['last']['value'])
