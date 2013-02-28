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

= Parley 
An expect-like module for Ruby modled after Perl's Expect.pm

Parley is a module that can be used with any class, like PTY, IO or
StringIO that responds_to?() :eof?, and either :read_nonblock(maxread)
or :getc.

If the class also responds to :select, then Parley will be able to wait
for additional input to arrive.

== parley method arguments

The parley() method is called with two arguments:

* a timeout in seconds, which may be zero to indicate no timeout
* an array of arrays, each array contains a pattern and an action.

Each pattern is either:

* a RegExp to match input data
* the symbol :timeout to match the timeout condition from select()
* the symbol :eof to match the eof?() condition

If an action responds_to?(:call), such as a lambda{|m| code}
then the action is called with MatchData as an argument.
In the case of :timeout or :eof, MatchData is from matching:
 input_buffer =~ /.*/

== Examples of Usage

=== Standard ruby expect vs. equivalent parley usage
Standard Ruby expect:
  require 'expect'

  ...
  input.expect(/pattern/, 10) {|matchdata| code}

Parley:
  require 'parley'

  ...
  input.parley(10, [[/pattern/, lambda{|matchdata| code}]])

=== Telnet login using /usr/bin/telnet
 require 'parley'
 input, output, process_id = PTY.spawn("/usr/bin/telnet localhost")
 output.puts '' # hit return to make sure we get some output
 result = input.parley(30, [  # allow 30 seconds to login
   [ /ogin:/, lambda{|m| output.puts 'username'; :continue} ],
   [ /ssword:/, lambda{|m| output.puts 'my-secret-password'; :continue} ],
   [ /refused/i, "connection refused" ],
   [ :timeout, "timed out" ],
   [ :eof, "command output closed" ],
   [ /\$/, true ] # some string that only appears in the shell prompt
   ])
 if result == true
   puts "Successful login"
   output.puts "date" # This is the important command we had to run
 else
   puts "Login failed because: #{result}"
 end
 # We can keep running commands.
 input.close
 output.close
 id, exit_status = Process.wait2(process_id)

=== Run your telnet script against canned input
 require 'parley'
 class StringIO
   include Parley
 end
 input = StringIO.new("login: password: prompt$\n", "r")
 output = StringIO.new("", "w")
 output.puts '' # Note: no effect in this example
 result = input.parley(30, [  # Note: timeout has no effect for StringIO
   # XXX check these example patterns against need for anchoring with ^ and/or $
   [ /ogin:/, lambda{|m| output.puts 'username'; :continue} ],
   [ /ssword:/, lambda{|m| output.puts 'my-secret-password'; :continue} ],
   [ :timeout, "timed out" ],
   [ :eof, "command output closed" ],
   [ /\$/, true ] # some string that only appears in the shell prompt
   ])
 if result == true
   puts "Successful login"
   output.puts "exit"
 else
   puts "Login failed because: #{result}"
 end
 input.close
 output.close
 id, exit_status = Process.wait2(process_id)

=== Handle a timeout condition
 require 'parley'
 read, write, pid = PTY.spawn("ruby -e 'sleep 20'")
 result = read.parley(5, ["timeout, :timeout])
 if result == :timeout
  puts "Program timed-out as expected"
 else
  puts "Error, timeout did not happen!"
 end

== Known Issues

* :reset_timeout from IO::parley() doesn't have the desired effect, it isn't re-establishing the timeout.
* need to generatate adequte documentation. See test/test_parley.rb for now
* line oriented reading option
* Finer grain greediness control beyond read_nonblock(maxlen)

== Contributing to parley
* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

== Copyright

Copyright (c) 2013 Ben Stoltz.
See LICENSE.txt for further details.
