require 'helper'
require "test/unit"
require 'parley'
require 'stringio'

#class TestParley < Test::Unit::TestCase
#  should "probably rename this file and start testing for real" do
#    flunk "hey buddy, you should probably rename this file and start testing for real"
#  end
#end

class StringIO
  include Parley
end

class TestIO < Test::Unit::TestCase

  def setup
    @text = "red apple\nbright white\nthree dogs\nblue sky\nafter glow\n"
    @test_verbose = false # Set to true if you want to see conversations
  end

  def teardown
    # no teardown required
  end

  def test_timeout
    read, write, pid = PTY.spawn('/bin/sleep 20')
    result = read.parley(5, [:timeout, :timeout])
    assert(result == :timeout, "** ERROR result = #{result}")
  end

  def test_eof_constant
    io = File.new("/dev/null", "r")
    result = io.parley(20, [:eof, :eof])
    assert(result == :eof, "** ERROR result = #{result}")
  end

  def test_eof_call
    io = File.new("/dev/null", "r")
    found_eof = false
    result = io.parley(20, [:eof, lambda {|m| found_eof = true; nil}])
    assert(result.nil?, "** ERROR result = <<#{result}>>")
    assert(found_eof == true, "** ERROR found_eof = #{found_eof}")
  end

  def test_strings
    count = 0
    io = StringIO.open(@text, "r")
    result = io.parley(0,
                       ['red apple', lambda{|m| count += 1; :continue }],
                       ['three dogs', lambda{|m| count += 1; :continue }],
                       [:eof, lambda{|m| count}] # XXX need to verify unused portion of buffer
                      )
    assert(count == 2, "** ERROR count = #{count}")
    assert(result == 2, "** ERROR result = #{result.inspect}")
  end

  def test_strings_maxread
    count = 0
    io = StringIO.open(@text, "r")
    io.parley_maxread = 10
    result = io.parley(0,
                       ['red apple', lambda{|m| count += 1; :continue }],
                       ['three dogs', lambda{|m| count += 1; :continue }],
                       [:eof, lambda{|m| count}] # XXX need to verify unused portion of buffer
                      )
    assert(count == 2, "** ERROR count = #{count}")
    assert(result == 2, "** ERROR result = #{result.inspect}")
  end

  def test_patterns
    colors = ['red\s*?(.*)$', 'orange', 'yellow', 'green', 'blue', 'indigo', 'violet']
    count = 0
    io = StringIO.open(@text, "r")
    result = io.parley(0,
                       [Regexp.new(colors.join('|')), lambda{|m| count += 1; :continue}],
                       [:eof, lambda{|m| count}] # XXX need to verify unused portion of buffer
                      )
    assert(count == 2, "** ERROR count = #{count}")
    assert(result == 2, "** ERROR result = #{result.inspect}")
  end

  #
  # Test the effect of reading more characters in at a time.
  # This means you'll have to be more careful of your patterns so that you
  # don't match more than you really want to
  #
  def test_patterns_maxread
    colors = ['red\s*?(.*)$', 'orange', 'yellow', 'green', 'blue', 'indigo', 'violet']
    count = 0
    io = StringIO.open(@text, "r")
    io.parley_maxread = 64  # Note: Up to 64 characters read at a time, so only 1 match
    result = io.parley(0,
                       [Regexp.new(colors.join('|')), lambda{|m| count += 1; :continue}],
                       [:eof, lambda{|m| count}] # XXX need to verify unused portion of buffer
                      )
    assert(count == 1, "** ERROR count = #{count}")
    assert(result == 1, "** ERROR result = #{result.inspect}")
  end

  #
  # Test the effect of reading more characters in at a time.
  # This means you'll have to be more careful of your patterns so that you
  # don't match more than you really want to
  # XXX doesn't work as expected: "\Z matches end of string or just before a \n"
  # ? indicates lazy match as opposed to greedy
  #
  def test_patterns_careful_maxread
    re = /
    red.*\n |    # "red" on a single line
    orange.*\n |
    yellow.*\n |
    green.*\n |
    blue.*\n |
    indigo.*\n |
    violet.*\n
    /x
    count = 0
    io = StringIO.open(@text + @text + @text, "r")
    io.parley_maxread = 64  # Note: Up to 64 characters read at a time, so only 1 match
    buf_end = nil
    io.parley_verbose = true if @test_verbose
    result = io.parley(0,
                       [re, lambda{|m|
      count = count + 1;
      # puts "COUNT=#{count} MATCH=\"#{m.pre_match}/#{m[0]}/#{m.post_match}\""
      :continue}
    ],
      [:eof, lambda{|m|
      buf_end = m[0];
      count
    }
    ] # XXX need to verify unused portion of buffer
                      )
    assert(count == 3, "** ERROR count = #{count}")
    assert(result == 3, "** ERROR result = #{result.inspect}")
    # assert(buf_end.length > 0, "** Error buf_end.length=#{buf_end.length}, buf=#{buf_end}")
  end

  def test_empty_string
    colors = ['red', 'orange', 'yellow', 'green', 'blue', 'indigo', 'violet']
    count = 0
    io = StringIO.open("", "r")
    result = io.parley(0,
                       [Regexp.new(colors.join('|')), lambda{|m| count += 1; :continue}],
                       [:eof, lambda{|m| count}])
    assert(count == 0, "** ERROR count = #{result.inspect}")
    assert(result == 0, "** ERROR result = #{result.inspect}")
  end

  def test_ruby_current_version
    fnames = []
    ftp_to = 20
    PTY.spawn("ftp ftp.ruby-lang.org") do |r_f, w_f, pid|
      r_f.parley_verbose = true if @test_verbose
      hostname = ENV['HOSTNAME']
      hostname ||= ""
      if !ENV['USER'].nil?
        username = ENV['USER']
      elsif !ENV['LOGNAME'].nil?
        username = ENV['LOGNAME']
      else
        username = 'guest'
      end

      # Name (ftp.ruby-lang.org:yourNameHere): ftp
      #   ftp\n
      # Password:
      #   #{username}\n
      # ftp>
      #   cd pub/ruby\n
      r_f.parley(ftp_to,
                 [/^Name.*:/, lambda {|m| w_f.puts("ftp"); :continue }],
                 [/ssword:/,  lambda {|m| w_f.puts("#{username}@#{hostname}"); :continue }],
                 [/> /, lambda {|m| w_f.puts("cd pub/ruby"); nil }]
                )

      # >
      #  dir\n
      r_f.parley(ftp_to, ["> ", lambda {|m| w_f.print "dir\r"}])

      # lrwxrwxrwx 1 1014 100 27 Feb 18 12:52 ruby-1.8.7-p334.tar.bz2 -> 1.8/ruby-1.8.7-p334.tar.bz2
      r_f.parley(ftp_to,
                 [/^ftp> /, lambda {|m|
        for x in m.pre_match.split("\n")
          if x =~ /(ruby.*?\.tar\.gz)/ then
            fnames.push $1
          end
        end
        begin
          w_f.print "quit\n"
        rescue
        end
        :nil
      }],
      [:eof, nil])
    end
    puts "The latest ruby interpreter is #{fnames.sort.pop}"
  end

  def test_reset_timeout
    read, write, pid = PTY.spawn(
      # XXX fire off a ruby program, not bash, to get the test behavoir we want
      '/bin/bash -x -c "for x in wait done too_late; do sleep 3; echo $x; done"')
    read.parley_verbose = true if @test_verbose
    result = read.parley(5,
                         [/wait/, :reset_timeout],
                         [/done/, :pass ],
                         [:timeout, :timeout])
    assert(result == :pass, "** ERROR result = #{result}")
  end
end
