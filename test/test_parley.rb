
$LOAD_PATH.unshift("#{File.dirname(__FILE__)}/../lib") if __FILE__ == $0
$LOAD_PATH.unshift("#{File.dirname(__FILE__)}") if __FILE__ == $0

require 'helper'
require "test/unit"
require 'parley'
require 'stringio'
require 'open3'

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

  def test_timeout_positive
    read, write, pid = PTY.spawn('/bin/sleep 20')
    result = read.parley(5, [:timeout, :timeout])
    assert(result == :timeout, "** ERROR result = #{result}")
  end

  # Negative timeout behaves like zero since that time is already passed.
  def test_negative_timeout
    sleep_seconds = 5
    read, write, pid = PTY.spawn("/bin/sleep #{sleep_seconds}")
    start_time = Time.now
    result = read.parley(-1, [:timeout, :timeout])
    delta_t = Time.now - start_time
    assert(result == :timeout, "** ERROR result = #{result}")
    assert(delta_t < sleep_seconds/2,
           "Immediate timeout did not happen: delta_t = #{delta_t}")
  end

  # Zero timeout results in immediate :timeout if no data available
  def test_zero_timeout
    sleep_seconds = 10
    read, write, pid = PTY.spawn("/bin/sleep #{sleep_seconds}")
    start_time = Time.now
    result = read.parley(0, [:timeout, :timeout], [:eof, :eof])
    end_time = Time.now
    delta_t = (end_time - start_time)
    assert(result == :timeout, "** ERROR result = #{result}")
    assert(delta_t < (sleep_seconds/2.0),
           "Test ended too late: delta_t(#{delta_t}) >= #{sleep_seconds/2.0}")
  end

=begin
  # This syntax is not final or implemented yet
  def test_multiple_spawned_commands
    total = 0
    count = 0

    commands1 = []
    (1..5).each do |i|
      # push [read, write, pid] onto commands
      commands1 << PTY.spawn("sleep 3; echo N=#{i}; sleep 2")
    end
    pattern_action_1 = [
      /N=(\d+)/,          # find this pattern in output of all commands
      lambda do |m, r, w|
      total += m[1].to_i
      count += 1
      :continue;       # we don't want to terminate the expect call
      end
    ]

    commands2 = []
    (6..10).each do |i|
      # push [read, write, pid] onto commands
      commands2 << PTY.spawn("sleep 3; echo X=#{i}; sleep 2")
    end
    pattern_action_2 = [
      /X=(\d+)/,          # find this pattern in output of all commands
      lambda do |m, r, w|
      total += m[1].to_i
      count += 1
      :continue;       # we don't want to terminate the expect call
      end
    ]

    result = total / (count * 1.0)

    sum = 0
    (1..10).each do |i|
      sum += i
    end
    avg = sum/10.0

    parley_multiple(15,
                    [commands1, pattern_action_1],
                    [commands2, pattern_action_2])

    assert(avg == result, "Error avg(#{avg}) != result(#{result}))")
  end
=end

  def test_nil_timeout
    sleep_seconds = 10
    read, write, pid = PTY.spawn("/bin/sleep #{sleep_seconds}")
    start_time = Time.now
    result = read.parley(nil, [:timeout, :timeout], [:eof, :eof])
    delta_t = Time.now - start_time
    assert(result == :eof, "** ERROR result = #{result}")
    assert(delta_t >= sleep_seconds - 1,
           "Test ended too quickly: delta_t = #{delta_t}")
  end

=begin
  # Alternate API, no timeout: parley([pattern, action], ...)
  # timeout_seconds defaults to nil which means "no timeout"
  def test_missing_timeout
    sleep_seconds = 10
    read, write, pid = PTY.spawn("/bin/sleep #{sleep_seconds}")
    start_time = Time.now
    result = read.parley([:timeout, :timeout], [:eof, :eof])
    delta_t = Time.now - start_time
    assert(result == :eof, "** ERROR result = #{result}")
    assert(delta_t >= sleep_seconds - 1,
           "Test ended too quickly: delta_t = #{delta_t}")
  end
=end

  def test_single_match
    sin = StringIO.new(@text)
    result = sin.parley(0,
                        [/apple/, "just apple"],
                        [/white/, "1 too many matches"],
                        [/dogs/, "2 too many matches"],
                        [:eof, "very bad"])
    assert(result == "just apple", "Invalid result(#{result})")
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
    assert(count == 0, "** ERROR count = #{count.inspect}")
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

  def test_guessing_game
    @NGAMES = 2
    @UPPER_LIMIT = 100
    @UPPER_LIMIT_LOG2 = 8

    game = <<-GUESSING_GAME_EOT
      BEGIN {puts "0>"; @n = 0}
      END { puts "Goodbye!"; }
      @secret ||= rand 100
      g = $F[0] ? $F[0].strip : ""
      z = "?"
      if g =~ /\\d+$/m
        z = (g.to_i <=> @secret)
        case g.to_i <=> @secret
        when -1
          puts "too low"
        when 1
          puts "too high"
        when 0
          puts "correct!"
          @secret = rand 100
          puts "Ready";
        end
      else
        exit 0 if $F[0] == "exit"
      end
      @n += 1
      puts "\#{@n}>"
    GUESSING_GAME_EOT

    # DRY: common code for sending a guess
    def sendguess resend = false
      @myguess = ((@min + @max) / 2).to_i
      puts "Resending guess" if resend
      puts "Guessing #{@myguess}"
      @sin.puts @myguess
      @guesses += 1 unless resend
      if @guesses > @UPPER_LIMIT_LOG2
        "I Lost"  # Bug in program if we haven't guessed it already
      else
        :continue
      end
    end

    def newgame
      @min = 0
      @max = @UPPER_LIMIT
      @guesses = 0
    end

    def winner
      puts "I win!"
      @wins += 1
      newgame
      (@games -= 1) > 0 ? sendguess : "finished" # :continue or "finished"
    end

    @games = @NGAMES
    @wins = 0
    # puts "Running: ruby -n -a -e #{game}"
    result = nil
    pty_return = PTY.spawn('ruby', '-n', '-a', '-e', game) do |sout, sin, pid|
      @sin = sin
      puts "Sending <CR>"
      sin.puts '' # Elicit a prompt from the game
      r = select([sout], [], [], 2)  # Wait up to 15 seconds for output from guessing game
      puts "Wokeup from select with <<#{r.inspect}>>"

      newgame
      @n_to_reset = 0
      sout.parley_maxread = 100
      # sout.parley_verbose = true
      result = sout.parley(
        2,
        [/too low/, lambda{|m| @min = @myguess + 1; sendguess}],
        [/too high/, lambda{|m| @max = @myguess - 1; sendguess}],
        [/correct/, lambda{|m| winner}],
        [/>/, lambda{|m| sendguess true}],
        [
          :timeout,
          lambda do |m|
        sin.puts ""
        @n_to_reset += 1
        puts "Resetting timeout #{@n_to_reset}"
        if @n_to_reset > 2 
          sin.puts "exit"
          "Timeout"
        else
          :reset_timeout
        end
          end
      ])
    end
    puts "Script finished, pty_return=#{pty_return}"
    assert(result == "finished", "didn't win last game")
    # assert(ec == 0, "Bad exit from guessing game")
    assert(@wins == @NGAMES, "Didn't win exactly #{@NGAMES} games")
  end
end
