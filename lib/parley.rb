
require 'pty'

# The Parley module is generally used to wrestle with the informal, interactive, text-mode,
# APIs of the world.
#
# Parley is an implementation of an expect-like API.  It is designed to
# help port away from Perl Expect based applications.
# Parley was chosen as a name as an alternative to the various "expect" like
# names already in use by other implementations.
#
# The {definition of "parley"}[http://www.thefreedictionary.com/parley] used
# here is: "A discussion or conference, especially one between enemies over
# terms of truce or other matters."
#
# See {the original Expect site at NIST}[http://www.nist.gov/el/msid/expect.cfm] for
# references to the original Expect language based on Tcl.
#
# See the {Perl Expect.pm module}[http://search.cpan.org/~rgiersig/Expect-1.21/Expect.pod].
#
# === Compatibility
# Parley can be used with any class, like PTY, IO or
# StringIO that responds_to?() :eof?, and either :read_nonblock(maxread) or :getc.
#
# If the class also responds to :select, ala IO##select, then Parley will be able to wait
# for additional input to arrive.
#
# === Monkey Patching
# require 'parley' will automatcially add parley() and support methods to the IO class
#
# Author::     Ben Stoltz (mailto:gem-parley@lzrd.com)
# Copyright::  Copyright (c) 2013 Benjamin Stoltz
# License::    See LICENSE.txt distributed with this file
#
# == Examples
# === Standard ruby expect vs. equivalent parley usage
# Standard Ruby expect:
#   require 'expect'
#
#   ...
#   input.expect(/pattern/, 10) {|matchdata| code}
#
# Parley:
#   require 'parley'
#
#   ...
#   input.parley(10, [/pattern/, lambda{|matchdata| code}])
#
# === Telnet login using /usr/bin/telnet
#  require 'parley'
#  input, output, process_id = PTY.spawn("/usr/bin/telnet localhost")
#  output.puts '' # hit return to make sure we get some output
#  result = input.parley(30,    # allow 30 seconds to login
#    [ /ogin:/, lambda{|m| output.puts 'username'; :continue} ],
#    [ /ssword:/, lambda{|m| output.puts 'my-secret-password'; :continue} ],
#    [ /refused/i, "connection refused" ],
#    [ :timeout, "timed out" ],
#    [ :eof, "command output closed" ],
#    [ /\$/, true ] # some string that only appears in the shell prompt
#    ])
#  if result == true
#    puts "Successful login"
#    output.puts "date" # This is the important command we had to run
#  else
#    puts "Login failed because: #{result}"
#  end
#  # We can keep running commands.
#  input.close
#  output.close
#  id, exit_status = Process.wait2(process_id)
#

module Parley
  # Internal: used to set input data that has been received, but not yet matched
  #--
  # Initialize() is usually not called or doesn't call super(), so
  # do implicit instance variable initialization
  #++
  def unused_buf= (v)
    @unused_buf = v
  end

  # holds the remaining input read from +read_nonblock()+ or +getc()+ but not
  # yet used
  def unused_buf
    @unused_buf = nil unless defined? @unused_buf
    @unused_buf
  end

  # Sets/clears verbose mode to aid debugging.
  #
  # Debug output is sent to +STDOUT+ unless overridden by +pvout+
  def parley_verbose= (truth, pvout = STDOUT)
    @pvout = pvout
    @parley_verbose = (truth ? true : false)
  end

  # returns +true+ if debug output is enabled, else +false+
  def parley_verbose
    @parley_verbose = false unless defined? @parley_verbose
    @parley_verbose
  end

  # sets the maximum number of characters to read from +read_nonblock()+
  def parley_maxread= (max_characters = 1)
    @parley_maxread = (max_characters > 0) ? max_characters : 1
  end

  # return the maximum number of characters to read from +read_nonblock()+
  def parley_maxread
    @parley_maxread = 1 unless defined? @parley_maxread
    @parley_maxread
  end

  # Collect data, from an IO-like object while matching
  # match patterns and conditions (i.e. EOF and Timeout) and take corresponding
  # actions until an action returns a value not equal to +:continue+ or
  # +:reset_timeout+
  #
  # The parley() method is called with two arguments:
  #
  # +timeout_seconds+ specifies the amount of time before the +:timeout+
  # condition is presented to the pattern/action list.
  #
  # a variable number of arrays, each array contains a pattern and an action.
  #
  # * +timeout_seconds+ = nil disables timeout.
  # * +timeout_seconds+ <= 0 times out immediately as soon as no data is present
  # * +timeout_seconds+ > 0 times out seconds after parley was called unless
  #   timer is reset by an action returning :reset_timeout
  #
  # A pattern is either:
  # * a RegExp to match input data
  # * the symbol :timeout to match the timeout condition from select()
  # * the symbol :eof to match the eof?() condition
  #
  # If an action responds_to?(:call), such as a lambda{|m| code}
  # then the action is called with MatchData as an argument.
  # In the case of :timeout or :eof, MatchData is from matching:
  #
  #   input_buffer =~ /.*/
  #
  # A action returning the value +:reset_timeout+ will +:continue+ and reset
  # the timeout deadline to a value of +Time.now+ + +timeout_seconds+
  #
  def parley (timeout_seconds, *actions)
    @pvout.puts "parley: timeout_seconds=#{timeout_seconds}" if parley_verbose
    case timeout_seconds
    when NilClass
      deadline = nil
    when Numeric
      deadline = Time.now + timeout_seconds
    else
      raise "Invalid timeout parameter: #{timeout_seconds.inspect}"
    end
    buf = ''
    unused_buf ||= ''

    # XXX Compatible hack. There are changes coming w.r.t. respond_to? for
    # protected methods. Just do a simple poll, and see if it works.
    begin
      result = IO.select([self], [], [], 0)
      has_select = true;
    rescue Exception  # NoMethodError and ArgumentError are common
      has_select = false;
    end

    begin
      # If it is possible to wait for data, then wait for data
      t = (deadline ? (deadline - Time.now) : nil)
      t = (t.nil? || t >= 0) ? t : 0
      # XXX If maxlen > unused_buf.length, then try to get more input?
      #     Think about above. don't want to use up all of timeout.
      if unused_buf.length == 0 && has_select && !IO.select([self], nil, nil, t)
        # Timeout condition from IO.select() returns nil
        @pvout.print "parley,#{__LINE__}: TIMEOUT buf=\"#{buf}\"\n" if parley_verbose
        timeout_handled = nil
        result = nil
        result = actions.find do|pattern, action|
          if pattern == :timeout
            timeout_handled = true
            if action.respond_to?(:call)
              r = action.call(/.*/.match(buf)) # call with entire buffer as a MatchData
            else
              r = action
            end
            @pvout.print "parley,#{__LINE__}: TIMEOUT Handled=\"#{r}\"\n" if parley_verbose
            break r
          else
            nil
          end
        end
        @pvout.print "parley,#{__LINE__}: TIMEOUT RESULT=\"#{result}\"\n" if parley_verbose
        if (!timeout_handled)
          # XXX need to prepend buf to @unusedbuf
          unused_buf = buf  # save data for next time
          raise "timeout"
        end
        return result unless result == :reset_timeout
        matched = true
      else

        # We've waited, if that was possible, check for data present
        if unused_buf.length == 0 && eof?
          @pvout.print "parley,#{__LINE__}: EOF Buffer=\"#{buf}\"\n" if parley_verbose
          eof_handled = false
          result = actions.find do |pattern, action|
            case pattern
            when :eof
              eof_handled = true
              if action.respond_to?(:call)
                result = action.call(/.*/m.match(buf))
              else
                result = action
              end
              break result
            else
              nil
            end
          end
          unless eof_handled
            # XXX need to prepend buf to @unusedbuf
            unused_buf = buf  # save data for next time
            raise "End of file"
          end
          return result
        end

        # No timeout and no EOF. There is some input data to look at
        # Greedy read:
        # buf << self.read_nonblock(maxlen)
        if (unused_buf.length > 0)
          c = unused_buf.slice!(0..parley_maxread)
        elsif (parley_maxread > 1 && self.respond_to?(:read_nonblock))
          c = read_nonblock(parley_maxread)
        else
          c = getc.chr
        end
        buf << c

        # Look for matches to the current buffer content
        result = :continue
        matched = false
        result = actions.each_with_index do |act,i|
          # @pvout.print "parley,#{__LINE__}: buf=\"#{buf}\"\tact=#{act[0]}\n" if parley_verbose
          m = case act[0]
              when Regexp
                act[0].match(buf)
              when String
                act[0] = Regexp.new(act[0]) # caching the regexp conversion
                act[0].match(buf)
              else
                nil
              end
          if m
            @pvout.print "parley,#{__LINE__}: match[#{i}]=\"#{buf}\"\n" if parley_verbose
            matched = true
            if act[1]
              if act[1].respond_to?(:call)
                result = act[1].call(m)
              else
                result = act[1] # no block, just a result
              end
            else
              result = m # no action supplied, return last match
            end
            buf = ''  # consume the buffer (XXX only the part that matched?)
            # XXX if the regex had post context, don't consume that.
            @pvout.puts "parley,#{__LINE__}: result=#{result}" if parley_verbose
            break result
          end
          result
        end
      end

      if matched == true
        @pvout.puts "parley,#{__LINE__}: MATCH, result=#{result}" if parley_verbose
        result = case result
                 when :continue
                   :continue
                 when nil  # explicit end
                   break nil
                 when :reset_timeout
                   deadline = Time.now + timeout_seconds # XXX vs deadline in lambda closure?
                   @pvout.puts "parley,#{__LINE__}: deadline=#{deadline.to_s}, continue" if parley_verbose
                   :continue
                 else  # return with result
                   break result
                 end
      else
        @pvout.puts "parley,#{__LINE__}: no match, implicit :continue, buf=#{buf}" if parley_verbose
        result = :continue
      end
    end while result == :continue
  end
end

# Including the Parley module will monkey-patch the IO class
class IO
  include Parley
end
