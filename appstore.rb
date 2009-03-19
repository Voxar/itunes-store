#!/usr/bin/ruby
=begin

  Author: Patrik Sjöberg <voxxar@gmail.com>
  
  See README.txt
=end
#ARGV.push *%w(-d ~/Desktop/mails2) #for debug

require 'net/imap'
require 'set'

require 'optparse'


#helpers
def req name
  begin
    require name
    true
  rescue LoadError => e
    p e
  end
end
    
def get_password
  req 'rubygems'
  if req('highline')
    h = HighLine.new
    h.ask("Password: ") { |q| q.echo = '*'}
  else
    puts "ruby gem highline not found. Password will be plain text."
    puts " To enable masked password in terminal, run 'sudo gem install highline'"
    puts "Enter password (caution, will be visible!)"
    STDIN.readline.strip
  end
end

class String
  #itunes date (day/month/year) to Time
  def to_date
    Time.mktime(*split("/").reverse)
  end
end
class Array
  #group elements in array
  def unflatten!(n)
    r = Array.new
    while length > 0
      p = slice!(0..n-1)
      r << p
    end
    p << nil while p && p.length < n
    r.each{ |v| self<<v }
  end
  def unflatten(n)
    self.clone.unflatten!(n)
  end
end


options = {
  :username => nil,
  :password => nil,
  :host => 'imap.gmail.com',
  :port => 993,
  :ssl => true,
  :mailbox => '[Gmail]/All Mail',
  :appstats => true,
  :musicstats => true,
  :paid => true,
  :free => false,
  :path => nil,
  :list => {:paid_apps=>true, :free_apps => true, :paid_music=>true, :free_music => true}
}
OptionParser.new do |opts|
  opts.banner = "Usage: appstore.rb [options]\n"
  opts.banner += "Example: appstore.rb -l free_apps,paid_music\n"
  opts.banner += " Lists only free apps and paid music"
  
  opts.separator ""
  opts.separator "User options:"
  
  opts.on("-u", "--username USERNAME", "Username") do |v|
    options[:username] = v
  end
  
  opts.on("-m", "--mailbox MAILBOX", "Mailbox to search (default: Apple Receipt)") do |v|
    options[:mailbox] = v
  end
  
  opts.separator ""
  opts.separator "Output options:"

  opts.on("-l", "--list x", "List outputs (all, paid, free, free_apps, free_music, paid_apps, paid_music)") do |v|
    values = v.split(",")
    valid = %w(all free paid free_apps free_music paid_apps paid_music)
    values.each do |v|
      if !valid.include?(v)
        puts "invalid --list argument: #{v}"
        exit 1
      end
    end
    options[:list] = {
      :free_apps  => values.include?('free_apps')  || values.include?('all') || values.include?('free'),
      :paid_apps  => values.include?('paid_apps')  || values.include?('all') || values.include?('paid'),
      :free_music => values.include?('free_music') || values.include?('all') || values.include?('free'),
      :paid_music => values.include?('paid_music') || values.include?('all') || values.include?('paid'),
    }
  end
  
  opts.separator ""
  opts.separator "Mail server options:"
  
  opts.on("-h", "--host HOST", "Host (default: imap.gmail.com)") do |v|
    options[:host] = v
  end
  
  opts.on("-p", Integer, "--port", "Port (default: 993)") do |v|
    options[:port] = v
  end
  
  opts.on("-s", "--[no-]ssl", "Use ssl (default: true)") do |v|
    options[:ssl] = v
  end
  
  opts.on("-d", "--directory PATH", "Read files in directory as mails (mainly for testing)") do |path|
    options[:path] = path
  end
  
  opts.separator ""
  opts.separator "Common options:"
          
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!



options[:query] = ['FROM', 'do_not_reply@apple.com', 'SUBJECT', 'Your receipt']

def parse body
  #Get the plain text version
  part = body.match(/------=_Part_.+?\r\n\r\n(.+?)---=_Part_/m)
  body = part.captures.first if part
  body = body.gsub("=\r\n", '')

  #Translate some HEX encoded chars to ascii or utf8 or whatever
  body = body.gsub!(/=([A-F0-9][A-F0-9])/) do |c|
    c[1..2].to_a.pack('H*')
  end || body
  
  itemnames = [:item_number, :name, :version, :seller, :price]

  #Extract interesting data
  info = {
    :billed_to => body.match(/Billed to:\r\n([^\r]+)\r\n([^\r]+)\r?\n/).captures.reverse,
    :date  => body.match(/Receipt Date: ([^\r]+)\r?\n/).captures.first,
    :total => body.match(/Order Total: (\d+\.\d+)(.+)  \r?\n/).captures.first,
#    :items => body.scan(/(Q\d+)\s+([^\s].+), (v.+), Seller: (.+)\s+([^\s]*Free|[^\s]*\d+\.\d+[^\s]*)\r?\n/).map{ |s| Hash[*itemnames.zip(s.map{ |s| s.strip }).flatten]}
    :items => body.scan(/(Q?\d+)\s+(\S.+)\s+(\S*Free|\S*\d+\.\d+\S*)\r?\n/).map{ |row| row.map{ |col| col.strip }}
  }
  
  info
end

#TODO: def receipts_from_pop options
#TODO: def receipts_from_itunes options #is it possible?

#For debugging. Use local cache of mails
def receipts_from_dir options
  path = File.expand_path(options[:path])
  puts txt = "Reading recepits in directory '#{path}'"
  data = []
  Dir.glob("#{path}/**") do |filename|
    open(filename) do |f|
      data << parse(f.read)
    end
  end
  puts "-"*txt.length
  data.compact
end

def receipts_from_imap options
  #Ask for credentials
  if not options[:username]
    puts "Enter username (e.g example@gmail.com)"
    options[:username] = STDIN.readline.strip
  end
  options[:password] = get_password
  
  #check the mail
  puts "Connecting to #{options[:host]}:#{options[:port]} #{"using ssl" if options[:ssl]}"
  imap = Net::IMAP.new(options[:host], options[:port], options[:ssl])
  begin
    imap.login(options[:username], options[:password])
  rescue Net::IMAP::NoResponseError => e
    puts "Wrong username and/or password"
    exit
  end

  #look for receipts
  mail = nil
  while !mail
    found_mailbox = false
    begin
      #select mailbox
      imap.examine(options[:mailbox]) #throws
      found_mailbox = true
    rescue Net::IMAP::NoResponseError => e
      puts "Mailbox #{options[:mailbox]} does not exist"
      mail = nil
    end
  
    if found_mailbox
      puts "Looking for iTunes receipts"
      mail = imap.search(options[:query])
      if mail.length == 0
        puts "No recipts found in mailbox #{options[:mailbox]}"
        mail = nil
      end
    end
    
    puts "\nEnter mailbox name" if !mail
    options[:mailbox] = STDIN.readline.strip if !mail

  end
  puts txt_dl = "Downloading #{mail.length} receipts..."
  #download and parse some data
  data = []
  
  #do threaded fetch
  nthreads = 20
  size = mail.length / nthreads
  parts = mail.unflatten(size)
  threads = parts.map do |part|
    Thread.new(part.compact) do |part|
      part.each do |message_id|
        body = imap.fetch(message_id, "BODY[TEXT]")[0].attr['BODY[TEXT]']
        data << parse(body)
      end
    end
  end
  threads.each do |thread|
    thread.join
  end

  imap.logout()
  puts "-"*txt_dl.length
  
  data.compact
end

#get soma data
data = receipts_from_dir(options)  if options[:path]
data = receipts_from_imap(options) if !data

if !data or data.length == 0
  puts "No data could be found"
  exit 1
end

#get all items from all mail and map them to their types
apps = []
music = []
other = []
data = data.each do |mail|
  mail[:items].each do |item|
    item_number, description, price = *item
    
    #is app?
    if match = description.match(/^(.+), (v.+?), (?:Seller:)? ?(.*)$/)
      next nil if !match
      name, version, seller = *match.captures
      apps << {
        :item_number => item_number.strip,
        :name => name,
        :version => version,
        :seller => seller,
        :price => price,
        :date => mail[:date]
      }
    else
      #is it music? Yeah probably
      music << {
        :name => description,
        :price => price,
        :date => mail[:date]
      }
    end
  end.compact
end.flatten

def gen_stats list
  #count free, paid, updates etc
  names = list.map{ |a| a[:name] }
  names_set = Set.new(names)

  free = list.select{|a|a[:price]=="Free"}
  free_names = free.map{ |a| a[:name] }
  free_names_set = Set.new(free_names)
  free_updates = free_names.length - free_names_set.length

  paid = list.reject{|a|a[:price]=="Free"}
  paid_names = paid.map{ |a| a[:name] }
  paid_names_set = Set.new(paid_names)
  paid_updates = paid_names.length - paid_names_set.length

  #TODO: map paid apps by currency (if needed. probably not)
  money_spent = paid.map{ |a| a[:price].to_f }.inject(0){ |r,v| r+v }
  money_spent = money_spent.to_i if money_spent - money_spent.to_i == 0.0
  
  {
    :names => names,
    :names_set => names_set,
    
    :free => free,
    :free_names => free_names,
    :free_names_set => free_names_set,
    :free_updates => free_updates,
    
    :paid => paid,
    :paid_names => paid_names,
    :paid_names_set => paid_names_set,
    :paid_updates => paid_updates,
    
    :money_spent => money_spent,
  }
end

#show paid apps?
def list_apps options, app_stats
  #what to include
  list = []
  list += app_stats[:paid] if options[:list][:paid_apps]
  if options[:list][:free_apps]
    set = Set.new
    list += app_stats[:free].reject { |i| !set.add?(i[:name]) } #filter free updates
  end
  
  width_name = 14
  width_price = 8
  width_seller = 14
  width_date = 0

  def max a,b; return a if a > b; b; end
  #find minimum widths
  list.each do |app|
    width_name = max(width_name, app[:name].length+1)
    width_price = max(width_price, app[:price].length+1)
    width_seller = max(width_seller, app[:seller].length+1)
    width_date = max(width_date, app[:date].length+1)
  end

  puts ""
  puts "Applications - iPhone and iPod Touch"
  
  if list.length == 0
    puts "Could not find any data about applications\n"
    puts ""
    return
  end
  
  puts ""
    
  #make some cols left justified
  width_name   *= -1
  width_price  *=  1
  width_seller *= -1
  width_date   *= -1

  dataformatstr = "%1$*2$s  %3$*4$s  %5$*6$s  %7$*8$s"

  # a nice header
  args = [ 'Name', width_name, 'Price', width_price, 'Seller',  width_seller, 'Date', width_date ]
  puts txt_header =dataformatstr%args
  args = [ '----', width_name, '-----', width_price, '------',  width_seller, '----', width_date ]
  puts dataformatstr%args

  def sortfun(a,b)
    d = b[:price].to_f - a[:price].to_f
    return d if d != 0.0
    a[:name] <=> b[:name]
  end
  #print apps
  list.sort(&method(:sortfun)).each do |app|
    args = [ app[:name], width_name,
             app[:price], width_price,
             app[:seller],  width_seller,
             app[:date], width_date ]
    puts dataformatstr%args
  end
  puts ""
end

#print report on music
def list_music options, music_stats
  #What to include
  list = []
  list += music_stats[:paid] if options[:list][:paid_music]
  if options[:list][:free_music]
    set = Set.new
    list += music_stats[:free].reject { |i| !set.add?(i[:name]) }#filter updates. Whait.. This is music!?!?
  end
  
  #list paid music
  width_name = 14
  width_price = 8
  width_date = 0

  def max a,b; return a if a > b; b; end
  #find minimum widths
  list.each do |music|
    width_name = max(width_name, music[:name].length+1)
    width_price = max(width_price, music[:price].length+1)
    width_date = max(width_date, music[:date].length+1)
  end

  puts ""
  puts "Music - Songs, singles and records"
  
  if list.length == 0
    puts "Could not find any data about music\n"
    puts ""
    return
  end
  
  puts ""

  #make some cols left justified
  width_name   *= -1
  width_price  *=  1
  width_date   *= -1

  dataformatstr = "%1$*2$s  %3$*4$s  %5$*6$s"

  # a nice header
  args = [ 'Name', width_name, 'Price', width_price, 'Date', width_date ]
  puts txt_header =dataformatstr%args
  args = [ '----', width_name, '-----', width_price, '----', width_date ]
  puts dataformatstr%args

  def sortfun(a,b)
    d = b[:price].to_f - a[:price].to_f
    return d if d != 0.0
    a[:name] <=> b[:name]
  end
  #print music
  list.sort(&method(:sortfun)).each do |music|
    args = [ music[:name], width_name,
             music[:price], width_price,
             music[:date], width_date ]
    puts dataformatstr%args
  end
  puts ""
end

def stats_by_wday apps
  puts "Shoppy happy day of month"
  
  names = %w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
  wdays = Hash[ *(0..6).zip([0]*7).flatten ]
  apps.each do |app|
    d = app[:date].to_date
    wdays[d.wday] += 1
  end
  wdays = wdays.to_a.sort!{ |a,b| a[0]-b[0] }
  total = apps.length

  size = 0.65
  max_percent = size*100#((wdays.sort{ |a,b| b[1]-a[1] }.first[1]/total.to_f)*100).round;  
  
  wdays.each do |item|
    day, count = *item
    percent = count/total.to_f*100
    puts "%10s: [%*s] %.1f%%"%[names[day], -max_percent, '='*(percent*size).round, percent]
  end
  puts ""
end

def stats_by_months apps
  puts "Shoppy happy month of year"
  
  names = %w(onebased Januari Febuari Mars April May June July August September October November December)
  wdays = Hash[ *(0..12).zip([0]*13).flatten ]
  apps.each do |app|
    d = app[:date].to_date
    wdays[d.month] += 1
  end
  wdays = wdays.to_a.sort!{ |a,b| a[0]-b[0] }
  total = apps.length

  size = 0.65
  max_percent = size*100#((wdays.sort{ |a,b| b[1]-a[1] }.first[1]/total.to_f)*100).round;  
  
  wdays[1..-1].each do |item|
    day, count = *item
    percent = count/total.to_f*100
    puts "%10s: [%*s] %.1f%%"%[names[day], -max_percent, '='*(percent*size).round, percent]
  end
  puts ""
end

def fartapps apps
  count = 0
  apps.each do |app|
    name = app[:name]
    count += 1 if name =~ /fart|whoopie|pull.+finger/i 
  end
  puts "Number of obvious fart apps: #{count}",""
end
app_stats = gen_stats(apps)
music_stats = gen_stats(music)

list_apps options, app_stats
list_music options, music_stats

stats_by_wday apps+music
stats_by_months apps+music
fartapps apps

#Show statistics?
if options[:appstats]
  #Print totals
  puts txt_stat = "Apps statistics:"
  puts "-"*txt_stat.length
  puts " Total applications: #{app_stats[:names_set].length}"
  puts "    Total free apps: #{app_stats[:free_names_set].length}" #dont count updates
  puts " Total free updates: #{app_stats[:free_updates]}"
  puts "    Total paid apps: #{app_stats[:paid_names_set].length}"
  puts " Total paid updates: #{app_stats[:paid_updates]}"
  #take an amount and replace the value to get the right currency
  if app_stats[:paid].first
    spent_str = app_stats[:paid].first[:price].sub(/\d+.\d+/, app_stats[:money_spent].to_s)
  else
    spent_str = "None"
  end
  puts "Total spent on apps: #{spent_str}"
end

puts " "
if options[:musicstats]
  #Print totals
  puts txt_stat = "Music statistics:"
  puts "-"*txt_stat.length
  puts "         Total music: #{music_stats[:names_set].length}"
  puts "    Total free music: #{music_stats[:free_names_set].length}"
  puts "    Total paid music: #{music_stats[:paid_names_set].length}"
  #take an amount and replace the value to get the right currency
  if music_stats[:paid].first
    spent_str = music_stats[:paid].first[:price].sub(/\d+.\d+/, music_stats[:money_spent].to_s)
  else
    spent_str = "None"
  end
  puts "Total spent on music: #{spent_str}"
end

puts ""
#take an amount and replace the value to get the right currency
if item = (app_stats[:paid].first || music_stats[:paid].first)
  spent_str = item[:price].sub(/\d+.\d+/, (app_stats[:money_spent] + music_stats[:money_spent]).to_s)
else
  spent_str = "None"
end
puts "Total spent in the iTunes Store: #{spent_str}"

items = data.map do |mail|
  mail[:items]
end.flatten

