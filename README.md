# Parley

## Introduction

An expect-like module for Ruby modled after Perl's Expect.pm

Parley is an implementation of an expect-like API.  It is designed to
help port away from Perl Expect based applications.

The name "expect"
is already well established in ruby and varients of that name are in use by several gems.
"parley" was chosen as alternative to yet another expect-varient.

From http://www.thefreedictionary.com/parley "A discussion or conference, especially one between enemies over terms of truce or other matters."

See http://www.nist.gov/el/msid/expect.cfm for references to the original Expect language based on Tcl.

See http://search.cpan.org/~rgiersig/Expect-1.21/Expect.pod for information on Expect.pm

## Duck Type Compatibility

Parley is a module that can be used with any class, like `PTY`, `IO` or
`StringIO` that responds to `eof()`, and either `read_nonblock(maxread)`
or `getc()`.

If the instance is valid for use with `Kernel.select()`, then Parley will be able to wait
for additional input to arrive.

## Parley method arguments

The `parley()` method is called with two arguments:

* an optional timeout in seconds, which may be 0 to indicate immediate timeout or `nil` to indicate no timeout
* additional arguments are arrays, each array containing a pattern and an action.

A call to parley with no arguments should read data until `eof?` and return `:eof`.


### Each pattern is either:

* a `RegExp` to match input data
* the symbol `:timeout` to match the timeout condition from select()
* the symbol `:eof` to match the eof?() condition

If an action `responds_to?(:call)`, such as a `lambda{|m| code}`
then the action is called with `MatchData` as an argument.
In the case of `:timeout` or `:eof`, `MatchData` is from `matching:`

    input_buffer =~ /.*/

## Examples of Usage

### Standard ruby expect vs. equivalent parley usage

In their simplest forms, the two are very similar:

* Expect takes a Regexp and an optional timeout
parameter. The method is either given a block that receives MatchData or it returns `MatchData`.

* Parley takes an optional `Numeric` timeout as the first argument and a variable
number of arrays, each containing a pattern and an action.

Standard Ruby expect:

    require 'expect'
    ...
    input.expect(/pattern/, 10) {|matchdata| code}  # wait up to 10 seconds
    input.expect(/pattern/, 0) {|matchdata| code}   # no waiting
    input.expect(/pattern/) {|matchdata| code}      # wait for a very long time

Parley:

    require 'parley'

    ...
    input.extend Parley # needed if input is not a subclass of IO
    ...
    input.parley(10, [/pattern/, lambda{|matchdata| code}])   # wait up to 10 seconds
    input.parley(0, [/pattern/, lambda{|matchdata| code}])    # no waiting
    input.parley(nil, [/pattern/, lambda{|matchdata| code}])  # wait forever
    input.parley([/pattern/, lambda{|matchdata| code}])       # wait forever

## Telnet login using /usr/bin/telnet
See the examples directory for a use of Net::Telnet instead of PTY.spawn(...

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

### Run your telnet script against canned input

    require 'parley'
    class StringIO
      include Parley  # or use "input.extend Parley"
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

### Handle a timeout condition

    require 'parley'
    read, write, pid = PTY.spawn("ruby -e 'sleep 20'")
    result = read.parley(5, ["timeout, :timeout])
    if result == :timeout
      puts "Program timed-out as expected"
    else
      puts "Error, timeout did not happen!"
    end

## Known Issues

* *FIXED!* `:reset_timeout` from IO::parley() doesn't have the desired effect, it isn't re-establishing the timeout.
* *FIXED!* need to generatate adequte documentation. See `test/test_parley.rb` for now
* line oriented reading option
* Finer grain greediness control beyond `read_nonblock(maxlen)`

## Contributing to parley
--

* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

## Copyright

Copyright &copy; 2013 Ben Stoltz.
See LICENSE.txt for further details.
