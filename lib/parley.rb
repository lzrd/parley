
require 'pty'

module Parley
  # Internal: used to set input data that has been received, but not yet matched
  #--
  # Initialize() is usually not called or doesn't call super(), so
  # do implicit instance variable initialization
  #++
  def unused_buf= (v)
    @unused_buf = v
  end

  # holds the remaining input read from +read_nonblock()+ or +getc()+ but not yet used
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

  # Match patterns and conditions and take corresponding actions until an action
  # returns a value not equal to +:continue+ or +:reset_timeout+
  #
  # +timeout_seconds+ specifies the amount of time before the +:timeout+ condition
  # is presented to the pattern/action list.
  #
  # If +timeout_seconds+ is less than or equal to zero, then +:timeout+
  # immediately as soon as there is no more data available.
  #
  # XXX bad. output could spew forever and we want to stop by deadline.
  #
  # If +timeout_seconds+ is nil, then no +:timeout+ condition will be generated.
  #
  # A action returning the value +:reset_timeout+ will +:continue+ and reset
  # the timeout deadline to a value of +Time.now+ + +timeout_seconds+
  def parley (timeout_seconds, *actions)
    @pvout.print "parley,#{__LINE__}: timeout_seconds=#{timeout_seconds}\n" if parley_verbose
    if (timeout_seconds == nil)
      deadline = nil
    else
      deadline = Time.now + timeout_seconds
    end
    buf = ''
    unused_buf = '' if not unused_buf

    # XXX Compatible hack. There are changes coming w.r.t. respond_to? for
    # protected methods. Just do a simple poll, and see if it works.
    begin
      result = IO.select([self], [], [], 0)
      has_select = true;
    rescue Exception
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
