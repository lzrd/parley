#!/usr/bin/ruby
#
# = parley.rb - An expect library for Ruby modled after Perl's Expect.pm
#
require 'pty'

# TODO: line oriented reading option
# Greediness control
module Parley
  # VERSION = '0.1.0'

  # Initialize() is usually not called or doesn't call super(), so
  # do implicit instance variable initialization
  def unused_buf= (v)
    @unused_buf = v
  end

  def unused_buf
    @unused_buf = nil unless defined? @unused_buf
    @unused_buf
  end

  def parley_verbose= (v)
    @parley_verbose = (v ? true : false)
  end

  def parley_verbose
    @parley_verbose = false unless defined? @parley_verbose
    @parley_verbose
  end

  def parley_maxread= (v)
    @parley_maxread = (v > 0) ? v : 1
  end

  def parley_maxread
    @parley_maxread = 1 unless defined? @parley_maxread
    @parley_maxread
  end

  def parley (t_out, *actions)
    # t_out = nil; # wait forever for next data
    # t_out = 0; # timeout immediately if no data available
    # t_out > 0; # timeout after t_out seconds
    # t_out < 0; # deadline is in the past, same as t_out = 0
    STDOUT.print "\n------\nparley t_out=#{t_out}\n" if parley_verbose
    if (t_out == nil)
      deadline = nil
    else
      deadline = Time.now + t_out
    end
    buf = ''
    unused_buf = '' if not unused_buf

    loop_count = 0

    # STDOUT.puts "class=#{self.class}"

    # Compatible hack. There are changes coming w.r.t. respond_to? for
    # protected methods. Just do a simple poll, and see if it works.
    begin
      result = IO.select([self], [], [], 0)
      has_select = true;
    rescue Exception
      has_select = false;
      # STDOUT.puts "Exception: #{Exception}"
    end
    # STDOUT.puts "has_select=#{has_select}"

    begin
      loop_count = loop_count + 1
      # If it is possible to wait for data, then wait for data
      t = (deadline ? (deadline - Time.now) : nil)
      t = (t.nil? || t >= 0) ? t : 0
      if unused_buf.length == 0 && has_select && !IO.select([self], nil, nil, t)
        # Timeout condition returns nil
        STDOUT.print "TIMEOUT=\"#{buf}\"\n" if parley_verbose
        timeout_handled = nil
        result = nil
        result = actions.each do|act|
          case act[0]
          when :timeout
            timeout_handled = true
            if act[1].respond_to?(:call)
              /.*/.match(buf) # get the buffer contents into a Regexp.last_match
              result = act[1].call(Regexp.last_match)
            else
              result = act[1]
            end
            break result
          end
        end
        if (!timeout_handled)
          # XXX need to prepend buf to @unusedbuf
          unused_buf = buf  # save data for next time
          raise "timeout" # XXX use TimeoutException
        end
        STDOUT.print "TIMEOUT RESULT=\"#{result}\"\n" if parley_verbose
        return result unless result == :reset_timeout
      else

        # We've waited, if that was possible, check for data present
        if unused_buf.length == 0 && eof?
          STDOUT.print "EOF Buffer=\"#{buf}\"\n" if parley_verbose
          result = nil
          eof_handled = false
          actions.each do |act|
            case act[0]
            when :eof
              eof_handled = true
              if act[1].respond_to?(:call)
                /.*/m.match(buf)  # Game end, match everything remaining
                result = act[1].call(Regexp.last_match)
              else
                result = act[1]
              end
              break result
            end
          end
          if not eof_handled
            # XXX need to prepend buf to @unusedbuf
            unused_buf = buf  # save data for next time
            raise :eof if not eof_handled
          end
          return result
        end

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
          # STDOUT.print "buf=\"#{buf}\"\tact=#{act[0]}\n" if parley_verbose
          m = case act[0]
              when Regexp
                act[0].match(buf) and Regexp.last_match
              when String
                act[0] = Regexp.new(act[0]) # caching the regexp conversion, XXX any problem?
                act[0].match(buf) and Regexp.last_match
              else
                nil
              end
          if m
            STDOUT.print "match[#{i}]=\"#{buf}\"\n" if parley_verbose
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
            STDOUT.puts "result=#{result}" if parley_verbose
            break result
          end
          result
        end
      end

      if matched == true
        result = case result
                 when :continue
                   :continue
                 when nil  # explicit end
                   break nil
                 when :reset_timeout
                   deadline = Time.now + t_out # XXX vs deadline in lambda closure?
                   STDOUT.puts "deadline=#{deadline.to_s}, continue" if parley_verbose
                   :continue
                 else  # return with result
                   break result
                 end
      else
        result = :continue
      end
    end while result == :continue
  end
end

class IO
  include Parley
end
