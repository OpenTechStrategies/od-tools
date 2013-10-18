/**
 * The main application singleton class
 */
function App() {

	// An identity for this client connection - python socket seems to be missing the ability to identify the stream
	this.id = Math.uuid(5)

	this.user;       // the current user data
	this.group;      // the current group private BM address
	this.views = []; // the availabe view classes - this first is the default if no view is specified by the current node
	this.view;       // the current view instance
	this.node;       // the current node name
	this.sep = '/';  // separator character used in hash fragment
	this.i18n = {};  // i18n messages loaded from /interface/i18n.json

	this.data = {};            // the current group's data
	this.queue = {};           // queue of data updates to send to the background service in the form keypath : [val, timestamp]
	this.syncTime = 1000;      // milliseconds between each sync request
	this.syncLock = false;     // prevents syncs from occurring if another is still in progress
	this.swfIdSent = false;    // this client's ID has been sent to the SWF
	this.swfConnected = false; // whether the SWF is available for receiving data

	// Populate the properties that were sent in the page
	for( var i in window.tmp ) {
		if(i == 'const') {
			for( var j in window.tmp['const'] ) window[j] = window.tmp['const'][j];
		} else this[i] = window.tmp[i];
	}

	// Dynamic application state data
	this.state = {
		bg: CONNECTED,    // State of connection to Bitgroup service
		bm: UNKNOWN,      // State of connection to Bitmessage daemon
		ip: UNKNOWN,      // State of network connection
		swf: NOTCONNECTED // Bitgroup connection type
	}

	// Run the app after the document is ready, load the i18n message and then run the app
	$(document).ready(function() {
		$.ajax({
			url: '/i18n.json',
			dataType: "json",
			context: window.app,
			success: function(i18n) {

				// Store the i18n messages
				window.i18n = i18n;

				// Load the extension scripts for this group
				for( i in this.ext ) $.getScript('/extensions/' + this.ext[i] + '.js');

				// Run the application
				this.run();

				// Regiester hash changes with our handler
				$(window).hashchange(function() { window.app.locationChange.call(window.app) });
			}
		});
		
	});

};

/**
 * Hash change handler - set the current node and view for the application from the hash fragment of the location
 */
App.prototype.locationChange = function() {
	var hash = window.location.hash;
	elements = hash.substr(1).split(this.sep);
	var oldnode = this.node;
	var newnode = elements.length > 0 ? elements[0] : false;

	// Check that the view is valid and convert to the class
	var oldview = this.view
	var newview = false;
	if(elements.length > 1) {
		for( var i = 0; i < this.views.length; i++ ) {
			var view = this.views[i];
			if(view.constructor.name.toLowerCase() == elements[1].toLowerCase()) newview = view;
		}
	}

	// Allow extensions to hook in here
	var args = {
		node: newnode,
		view: newview,
		path: elements,
	};
	$.event.trigger({type: "bgHashChange", args: args});

	// Set the new data
	this.node = args.node;
	this.view = args.view;

	// If the node or the view has changed, call the event handler for it
	if(oldnode != this.node) this.nodeChange();
	else if(oldview != this.view) this.viewChange();

	// TODO: view may want the additional URI elements
	
};

/**
 * Initialise the selected skin and render the current node and view
 */
App.prototype.run = function() {

	// Call the location change event to set the current node and view
	this.locationChange();

	// If there's no group, render the page now, otherwise wait for the group data from the first sync
	if(this.group == '') this.renderPage();

	// Initialise a poller for regular data transfers to and from the service
	setInterval( function() {
		var app = window.app;

		// If the SWF is available and we haven't sent our client ID to it yet, do it now
		if(app.swfConnected) {
			if(!app.swfIdSent) app.swfIdentify();
		}

		// Otherwise if the SWF isn't available, call the Ajax syncData method instead
		else app.syncData();

		// Allow other extensions to do something regularly too
		$.event.trigger({type: "bgPoller"});
	}, this.syncTime );
};

/**
 * Render the page
 */
App.prototype.renderPage = function() {
	var page = '';

	// Get the current skin and load it's styles
	var skin = 'skin' in this.data ? this.data.skin : 'default';
	this.loadStyleSheet('/skins/' + skin + '/style.css');

	// Render the top bar
	page += '<div id="personal"><h3>' + this.msg('personal').ucfirst() + '</h3>' + this.renderPersonal() + '</div>\n';

	// Add an area for site messages to render
	page += '<div id="notify"></div>\n';

	page += '<div id="page">\n';

	// Add a page title and sub-title holders to be filled dynamically
	page += '<h1 id="page-title"><a href="/' + this.group + '#"></a></h1>\n';
	page += '<h2 id="sub-title"></h2>\n';

	// Render the views menu
	page += '<div id="views"><h3>' + this.msg('views').ucfirst() + '</h3>' + this.renderViewsMenu() + '</div>\n'

	// Add an empty content area for the view to render into
	page += '<div id="content"></div>';
	page += '</div>\n';

	// Add our SWF for asynchronous incoming data
	page += this.swfRender();

	// Add the completed page structure to the HTML document body
	$('body').html(page);

	// Add body classes for CSS rules
	$('body').addClass('view-' + this.view.constructor.name.toLowerCase().replace(' ',''));
	if(this.node) $('body').addClass('node-' + this.node.toLowerCase().replace(' ',''));
	if(this.group) $('body').addClass('group-' + this.group.toLowerCase().replace(' ',''));

	// Define a function to connect dynamic components and render the content after the skin script has finished
	var afterSkin = function() {

		// Set the page title
		this.pageTitle();

		// Connect the dynamic application data elements
		var bgElem = $('#state-bg-data')[0];
		var bmElem = $('#state-bm-data')[0];
		var ipElem = $('#state-ip-data')[0];
		var swfElem = $('#state-swf-data')[0];
		var fStatus = function(val) { $(this).html( val > 0 && val < 10 ? app.msg('con-status-'+val) : val ) };
		bgElem.setValue = fStatus;
		bmElem.setValue = fStatus;
		ipElem.setValue = fStatus;
		swfElem.setValue = function(val) { $(this).html(app.msg('swf-status-'+val)) };
		this.componentConnect('_bg', bgElem);
		this.componentConnect('_bm', bmElem);
		this.componentConnect('_ip', ipElem);
		this.componentConnect('_swf', swfElem);

		// Call the view's render method to populate the content area
		this.view.render(this);
	};

	// Load and run the skin script
	$.ajax({
		url: '/skins/' + skin + '/' + skin + '.js',
		dataType: "script",
		context: this,
		success: afterSkin, // Execute the after skin function after the script has loaded and run
		error: afterSkin    // or execute it right now if no script was run
	});
};

/**
 * Render the personal top bar
 */
App.prototype.renderPersonal = function() {
	html = '<span id="uuid">UUID: ' + this.id + '</span>\n';
	html += '<ul id="personal-menu">';
	html += '<li id="bitgroup"><a>Bitgroup</a><ul>\n'
	html += '<li><a href="/">' + this.msg('about', 'Bitgroup') + '</a></li>\n';
	html += '<li><a href="https://bitmessage.org">' + this.msg('about', 'Bitmessage') + '</a></li>\n';
	html += '<li><a href="http://www.bitgroup.org">bitgroup.org</a></li>\n';
	html += '<li><a href="http://www.organicdesign.co.nz/bitgroup">' + this.msg('documentation') + '</a></li>\n</ul></li>\n';
	html += '<li id="profile"><a id="user-page" href="/">' + this.msg('user-page') + '</a></li>\n';
	html += '<li id="groups"><a>' + this.msg('groups') + '</a><ul id="personal-groups">\n' + this.renderGroupsList() + '</ul></li>\n';
	html += '<li id="status"><a>' + this.msg('status') + '</a><ul>\n';
	html += '<li id="state-bg"><a>' + this.msg('bg') + '</a><ul><li><a id="state-bg-data"></a></li></li>\n'
	html += '<li><a id="state-swf-data"></a></li></ul></li>\n'
	html += '<li id="state-bm"><a>' + this.msg('bm') + '</a><ul><li><a id="state-bm-data"></a></li></ul></li>\n'
	html += '<li id="state-ip"><a>' + this.msg('ip') + '</a><ul><li><a id="state-ip-data"></a></li></ul></li>\n'
	html += '</ul>\n</ul>\n';
	return html;
};

/**
 * Render the personal top bar
 */
App.prototype.renderGroupsList = function() {
	var html = '<li id="newgroup-link"><a href="/#/NewGroup">' + this.msg('newgroup') + '...</a></li>\n';
	var groups = this.user.groups;
	for( var i in this.user.groups ) {
		var g = groups[i];
		var link = '<a href="/' + i + '">' + g +'</a>';
		html += '<li id="personal-groups-' + this.getId(g) + '">' + link + '</li>\n';
	}
	return html;
};

/**
 * Update the page title
 */
App.prototype.pageTitle = function() {
	$('#page-title a').html(this.group ? this.user.groups[this.group] : this.msg('user-page'));
	var view = this.view.constructor.name;
	var msg = 'title-' + view.toLowerCase();
	$('#sub-title').html(this.msgExists(msg) ? this.msg(msg, this.node) : this.node);
};

/**
 * Render the views menu
 */
App.prototype.renderViewsMenu = function() {
	var html = '';

	// Get the current view class, or the default one if none
	var view = this.view;
	if(view == false) view = this.view = this.views[0];

	// Get the list of view names used by this node + the default view
	var views = [this.views[0].constructor.name];
	if(this.node && this.node in this.data && 'views' in this.data[this.node])
		views = views.concat(this.data[this.node].views[0]);

	// If no group is selected, add the new group node
	if(this.group == '') {
		for( var j = 0; j < this.views.length; j++ ) {
			if(this.views[j].constructor.name == 'NewGroup')
				views.push(this.views[j].constructor.name);
		}
	}

	// Render the views menu
	for( var i = 0; i < views.length; i++ ) {
		var name = views[i];

		// Get the view class matching the name if any
		var vi = false;
		for( var j = 0; j < this.views.length; j++ ) if(this.views[j].constructor.name == name) vi = this.views[j];

		// Add a menu item for this view (disabled if no class matched)
		var c = ' class="disabled"';
		var item = name;
		if(vi) {
			item = '<a href="#' + this.node + this.sep + item + '">' + this.msg('view-'+ item.toLowerCase()) + '</a>';
			c = name == view.constructor.name ? ' class="selected"' : '';
		}
		var id = 'view-' + this.getId(name);
		html += '<li' + c + ' id="' + id + '">' + item + '</li>\n';
	}
	return '<ul>' + html + '</ul>';
};

/**
 * When the node changes, rebuild the views menu and update the view
 */
App.prototype.nodeChange = function() {
	$('#views').html(this.renderViewsMenu());
	this.viewChange();
};

/**
 * When the view changes, update the views list classes and call the render method
 */
App.prototype.viewChange = function() {
	if($('#views').length > 0) {
		var view = this.view ? this.view : this.views[0];
		$('#views li.selected').removeClass('selected');
		$('#view-' + this.getId(view)).addClass('selected');

		// Remove any notification that may have been on the page
		$('#notify').html('');

		view.render(this);
		this.pageTitle();
	}
};

/**
 * Send queued data to the Python service and receive any queued items (called on a regular interval if the SWF is not connected)
 */
App.prototype.syncData = function() {

	// If a sync is already in progress, bail
	if(this.syncLock) return console.info('syncLock is set, exiting syncData without doing anything');
	this.syncLock = true;

	// Convert the queue from a hash into a list
	var data = [];
	for( var k in this.queue ) data.push([k, this.queue[k][0], this.queue[k][1]]);
	var lastSync = this.timestamp();

	// Send the sync request
	$.ajax({
		type: 'POST',
		url: (this.group ? '/' + this.group : '' ) + '/_sync.json',
		data: data.length > 0 ? JSON.stringify(data) : '', 
		contentType: "application/json; charset=utf-8",
		headers: { 'X-Bitgroup-ID': this.id },
		dataType: 'json',
		context: this,
		success: function(data) {

			// If the result is an object, then it's the whole data structure
			if(data.length === undefined) {
				this.data = data;
				this.renderPage(); // just rebuild the page instead of raising events for all the changes
			}

			// A list of changed keys was returned, update the local data and trigger change events
			// - note these have no timestamp since we're not merging with another queue
			// - note2 the data is set with queue set to false
			else {

				// The last item is an object contain application information
				var state = data.pop();
				for( var i in state ) this.setState(i, state[i]);
				this.setState('bg', CONNECTED);

				// The rest of the list is the change data
				for( var i = 0; i < data.length; i++ ) {
					var k = data[i][0];
					var v = data[i][1];
					var ts = data[i][2];
					console.info('data received (@' + ts + '): ' + k + ' = "' + v + '"');
					this.setData(k, v, false, ts);
				}
			}

			// Remove all items queued before the sync request was made
			var tmp = {};
			for( var k in this.queue ) if(this.queue[k][1] > lastSync) tmp[k] = this.queue[k];
			this.queue = tmp;

			// Remove the sync lock
			this.syncLock = false;
		},
		error: function(a,b,c) {
			this.setState('bg', DISCONNECTED);
			this.setState('bm', UNKNOWN);
			this.syncLock = false;
		}
	});
};

/**
 * Sends a single change to the Python service (used if the SWF is connected)
 * - sends as a normal sync request, but don't expect anything back as it's going to the SWF instead
 */
App.prototype.sendData = function(key, val, ts) {
	$.ajax({
		type: 'POST',
		url: (this.group ? '/' + this.group : '' ) + '/_sync.json',
		data: JSON.stringify([[key, val, ts]]),
		contentType: "application/json; charset=utf-8",
		headers: { 'X-Bitgroup-ID': this.id },
		dataType: 'html',
		error: function() {
			this.setState('bg', NOTCONNECTED);
			this.setState('bm', CONNECTED);
		}
	});
};

/**
 * Render a container for our 1px SWF which allows asynchronous incoming data
 */
App.prototype.swfRender = function() {
	return '<object id="swfsocket" width="100" height="20" codebase="http://active.macromedia.com/flash2/cabs/swflash.cab#version=4,0,0,0" classid="clsid:D27CDB6E-AE6D-11cf-96B8-444553540000">'
		+ '<param value="socket.swf" name="movie">'
		+ '<param value="high" name="quality">'
		+ '<param value="false" name="play">'
		+ '<param value="#F4F4F4" name="bgcolor">'
		+ '<embed width="100" height="20" pluginspage="http://www.macromedia.com/shockwave/download/index.cgi?P1_Prod_Version=ShockwaveFlash" type="application/x-shockwave-flash" bgcolor="#F4F4F4" quality="high" src="socket.swf" name="swfsocket" swliveconnect="true" play="false">'
		+ '</object>\n';
};

/**
 * Returns the SWF object - by F. Permadi May 2000
 */
App.prototype.swfGetObject = function() {
	var swf = 'swfsocket';
	if(window.document[swf]) return window.document[swf];
	if(navigator.appName.indexOf("Microsoft Internet") == -1) {
		if(document.embeds && document.embeds[swf]) return document.embeds[swf]; 
	}
	return document.getElementById(swf);
}

/**
 * Send our ID and group to the SWF
 */
App.prototype.swfIdentify = function() {
	this.swfGetObject().data(this.id, this.group, window.location.port);
	this.swfIdSent = true;
}

/**
 * Receive data from the SWF
 */
App.prototype.swfData = function(data) {
	this.swfConnected = true;
	this.setState('swf', CONNECTED);
	if(data) {
		console.info("Data received from SWF: " + data);
		data = JSON.parse(data);
		var k = false
		for(k in data) break;

		// Data is application state array
		if(k == 'state') {
			for(k in data['state']) this.setState(k, data['state'][k]);
		}

		// Data is a single change item
		else this.setData(data[0], data[1], false, data[2]);
	}
};

/**
 * Set the dynamic application state data returned from the server side on the last sync if it's changed
 * - this raises a normal change event so that components can connect to state values using a preceding underscore on the key
 */
App.prototype.setState = function(key, val) {
	if(val != this.state[key]) {
		this.state[key] = val;
		$.event.trigger({type: "bgDataChange-_" + key, args: {app:this, val:val}});
	}	
};

/**
 * Return the data for the passed key
 * - return the timestamp to if ts set
 * TODO: don't use eval for this, make a path walking function like node.py
 */
App.prototype.getData = function(key, ts) {
	if(key.substr(0,1) == '_') return this.state[key.substr(1)]; // if the key starts with an underscore, it's an application state value
	var val = eval('this.data.' + key);
	if(val === undefined) console.info( 'undefined value for ' + key );
	return ts === true ? val : val[0];
};

/**
 * Set the data for the passed key to the passed value
 * TODO: don't use eval for this, make a path walking function like node.py
 */
App.prototype.setData = function(key, val, send, ts) {

	// Get the current value and timestamp
	var oldval = this.getData(key, true);
	var oldts = oldval[1];
	oldval = oldval[0]

	// Bail now if the value hasn't changed
	if(JSON.stringify(oldval) == JSON.stringify(val)) return false;

	// Bail if the new data is older than the current data
	if(ts === undefined) ts = this.timestamp();
	else if(oldts > ts) {
		console.info('The local version of ' + key + ' is more recent (@' + oldts + ') than the passed version (@' + ts +')');
		return false;
	}

	// Trigger the data changed event
	$.event.trigger({type: "bgDataChange-" + key.replace('.', '-'), args: {app:this, val:val}});

	// Update the value with the timestamp
	val = [val, ts];
	eval('this.data.' + key + '=val');

	// If the change originated in this page, then 
	if(send === undefined) send = true;
	if(send) {

		// If the SWF is connected send the change directly now, otherwise add it to the outgoing sync queue
		if(app.swfConnected) this.sendData(key, val[0], val[1]);
		else this.queue[key] = val;
	}

	var action = send ? (app.swfConnected ? ' - sent' : ' - queued') : '';
	console.info(key + ' changed from "' + oldval + '" to "' + val[0] + '" (@' + ts + ')' + action);
	return true;
};

/**
 * Load a CSS from the passed URL
 */
App.prototype.loadStyleSheet = function(url) {
	if (document.createStyleSheet) document.createStyleSheet(url);
	else $('<link rel="stylesheet" type="text/css" href="' + url + '" />').appendTo('head'); 
};

/**
 * Convert a name to a valid identifier
 */
App.prototype.getId = function(name) {
	if(typeof name != 'string') name = name.constructor.name;
	return name.replace(' ','').toLowerCase();
};

/**
 * Message dialog and error logging
 */
App.prototype.error = function(msg, type) {
	alert(type + ': ' + msg);
};

/**
 * Return message from key
 */
App.prototype.msg = function(key, s1, s2, s3, s4, s5) {
	var lang = this.user.lang;
	var str;

	// Get the string in the user's language if defined
	if(lang in window.i18n && key in window.i18n[lang]) str = window.i18n[lang][key];

	// Fallback on the en version if not found
	else if(key in window.i18n.en) str = window.i18n.en[key];

	// Otherwise use the message key in angle brackets
	else str = '&lt;' + key + '&gt;';

	// Replace variables in the string
	if(s1) str = str.replace('$1', s1);
	if(s2) str = str.replace('$2', s2);
	if(s3) str = str.replace('$3', s3);
	if(s4) str = str.replace('$4', s4);
	if(s5) str = str.replace('$5', s5);

	return str;
};

/**
 * Return true if a message for the key in the user's lang or in en is found
 */
App.prototype.msgExists = function(key) {
	var lang = this.user.lang;
	if(lang in window.i18n && key in window.i18n[lang]) return true;
	if(key in window.i18n.en) return true;
	return false;
};

/**
 * Allow extensions to add ther own i18n messages
 * TODO: extensions should be in their own dirs and have an i18n.js file for messages
 */
App.prototype.msgSet = function(lang, key, val) {
	window.i18n[lang][key] = val;
};

/**
 * Create a notification div
 */
App.prototype.notify = function(content, type) {
	return '<div class="' + type + '">' + content + '</div>';
};

/**
 * Return a millisecond timestamp - must match app.py's timestamp
 */
App.prototype.timestamp = function() {
	return new Date().getTime() - 1378723000000;
};

/**
 * Detect the general type of an interface component based on its DOM attributes
 */
App.prototype.componentType = function(element) {
	element = $(element)[0];
	var type = false;
	if($(element).attr('type') == 'checkbox') type = 'checkbox';
	else if(element.tagName == 'SELECT') type = 'select';
	else if($(element).hasClass('checklist')) type = 'checklist';
	else if($(element).attr('value') !== undefined || element.tagName == 'textarea') type = 'input';
	else if(element.tagName == 'DIV') type = 'div';
	else if(element.tagName == 'SPAN') type = 'span';
	else if(element.tagName == 'A') type = 'a';
	return type;
};

/**
 * Return whether the passed component type allows user input
 */
App.prototype.componentIsInput = function(element, type) {
	if('getValue' in element) return true;
	if(type === undefined) type = this.componentType(element);
	return type == 'input' || type == 'checkbox' || type == 'select' || type == 'checklist' || type == 'textarea';
};

/**
 * Set the value of an interface component based on its general type
 */
App.prototype.componentSet = function(element, val, type) {
	if('setValue' in element) element.setValue.call(element,val);
	else {
		if(type === undefined) type = this.componentType(element);
		if(type == 'div' || type == 'span' || type == 'a') $(element).html(val);
		else if(type == 'input' || type == 'textarea') $(element).val(val);
		else if(type == 'checkbox') $(element).attr('checked',val ? true : false);
		else if(type == 'select') {
			if(typeof val != 'object') val = [val];
			$('option',element).each(function() { this.selected = val.indexOf($(this).text()) >= 0 });
		}
		else if(type == 'checklist') {
			if(typeof val != 'object') val = [val];
			$('input',element).each(function() { this.checked = val.indexOf($(this).next().text()) >= 0 });
		}
	}
};

/**
 * Get the value of an interface component based on its general type
 */
App.prototype.componentGet = function(element, type) {
	var val = false;
	if('getValue' in element) val = element.getValue.call(element);
	else {
		if(type === undefined) type = this.componentType(element);
		if(type == 'div' || type == 'span' || type == 'a') val = $(element).html();
		else if(type == 'input' || type == 'textarea') val = $(element).val();
		else if(type == 'checkbox') val = $(element).is(':checked');
		else if(type == 'select') {
			if($(element).attr('multiple') === undefined) val = $('option[selected]',element).text();
			else {
				val = [];
				$('option',element).each(function() { if($(this).is(':selected')) val.push($(this).text()) });
			}
		}
		else if(type == 'checklist') {
			val = [];
			$('input',element).each(function() { if($(this).is(':checked')) val.push($(this).next().text()); });
		}
	}
	return val;
};

/**
 * General renderer for interface components
 */
App.prototype.componentRender = function(type, data, atts) {
	if(data === undefined) data = '';
	if(atts === undefined) atts = {};
	if(!('id' in atts)) atts.id = Math.uuid(5);
	html = '';
	attstr = '';
	for(k in atts) attstr += ' ' + k + '="' + atts[k] + '"';

	// HTML
	if(type == 'div' || type == 'span' || type == 'a') html = '<' + type + attstr + '>' + data + '</' + type + '>';

	// Text input
	else if(type == 'input') html = '<input' + attstr + ' type="text" value="' + data + '" />';

	// Checkbox
	else if(type == 'checkbox') html = '<input' + attstr + ' type="text" value="' + data + '" />';

	// Select list
	else if(type == 'select') {
		html = '<select' + attstr + '>';
		for(i = 0; i < data.length; i++) html += '<option>' + data[i] + '</option>';
		html += '</select>';
	}

	// Checklist
	else if(type == 'checklist') {
		html = '<div' + attstr + ' class="checklist">';
		for(i = 0; i < data.length; i++) html += '<input type="checkbox" /><span>' + data[i] + '</span><br />';
		html += '</div>';
	}

	// Textarea
	else if(type == 'textarea') {
		html = '<textarea' + attstr + '>' + data + '</textarea>';
	}

	// Unknown type
	else html = '<div' + attstr + '>' + app.msg( 'err-nosuchcomponent', type) + '</div>';

	return html;
};

/**
 * Connect an interface component to a data source
 */
App.prototype.componentConnect = function(key, element) {
	element = $(element)[0];
	var val = this.getData(key);
	var type = this.componentType(element);

	// Set the source for the element's value
	element.dataSource = key;

	// Set the component's value to the current data value
	this.componentSet(element, val, type);

	// When the value changes from the server, update the element
	console.info('Connecting component "' + element.id + '" to ' + key);
	var handler = function(event) {
		if($(element).parents().filter('body').length > 0) event.args.app.componentSet(element, event.args.val)
		else {
			console.info('Component "' + element.id + '" gone, removing event');
			$(document).off(event, null, handler);
		}
	};
	var event = "bgDataChange-" + key.replace('.','-');
	$(document).on(event, handler);

	// When the element value changes (if an input), update the local data structure and queue the change for the next sync request
	if(this.componentIsInput(element, type)) {
		var i = type == 'checklist' ? $('input',element) : $(element);
		i.change(function() {
			var app = window.app;
			var val = app.componentGet(element);
			var key = element.dataSource;
			app.setData(key, val);
		});
	}
};

/**
 * Add ucfirst method to strings
 */
String.prototype.ucfirst = function() {
    return this.charAt(0).toUpperCase() + this.slice(1);
}

/**
 * Add JSON support for older browsers that don't have it
 */
if(!window.JSON) {
	window.JSON = {
		parse: function (sJSON) { return eval("(" + sJSON + ")"); },
		stringify: function (vContent) {
			if(vContent instanceof Object) {
				var sOutput = "";
				if(vContent.constructor === Array) {
					for(var nId = 0; nId < vContent.length; sOutput += this.stringify(vContent[nId]) + ",", nId++);
					return "[" + sOutput.substr(0, sOutput.length - 1) + "]";
				}
				if(vContent.toString !== Object.prototype.toString) { return "\"" + vContent.toString().replace(/"/g, "\\$&") + "\""; }
				for(var sProp in vContent) { sOutput += "\"" + sProp.replace(/"/g, "\\$&") + "\":" + this.stringify(vContent[sProp]) + ","; }
				return "{" + sOutput.substr(0, sOutput.length - 1) + "}";
			}
			return typeof vContent === "string" ? "\"" + vContent.replace(/"/g, "\\$&") + "\"" : String(vContent);
		}
	};
}

// Create a new instance of the application
window.app = new App();

