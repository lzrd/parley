parley
======

An Expect-like gem for Ruby

Parley is an implementation of an expect-like API.  It is designed to
help port away from Perl Expect based applications.  The name "expect"
is already well established in ruby.  Those of you who have wrestled
with the interactive, text-mode, APIs of the world will appreciate the
meaning of the word:

From http://www.thefreedictionary.com/parley "A discussion or conference, especially one between enemies over terms of truce or other matters."

See http://www.nist.gov/el/msid/expect.cfm for references to the original Expect language based on Tcl.

See http://search.cpan.org/~rgiersig/Expect-1.21/Expect.pod for information on Expect.pm

Known Issues
------------

* need to generatate adequte documentation. See test/test_parley.rb for now
* :restart_timeout from IO::parley() doesn't have the desired effect, it isn't re-establishing the timeout.

Contributing to parley
----------------------
 
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

Copyright
---------

Copyright (c) 2013 Ben Stoltz.
See LICENSE.txt for further details.