# Common functions for dealing with extensions

# Add extensions to the passed instance
def add(obj):
	for e in obj.config.extensions:
		# Check if this extension dir exists, warn if not
		# Import the module
		# If the module has a Group (module.__dict__['Group']) class, add it to passed instances __bases__ list
