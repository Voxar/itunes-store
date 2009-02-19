#!/usr/bin/ruby
=begin

  Author: Patrik Sjöberg <voxxar@gmail.com>
    Date: 19 Feb 2009
 Version: 0.1.1
    
  Searches your imap enabled mail account for iTunes receipts and displays statistics abount 
  your purchases.
  
  Using: 
    
    If you have a gmail account:
     1. run 'ruby appstore.rb'
     2. enter username
     3. enter password
     
    If you have an account other than gmail:
      1. run 'ruby appstore.rb --host <server address> --port <server port> \
              --mailbox <mailbox where receipts are stored>'
         add '--ssl' if server uses ssl
      2. enter username
      3. enter password
  
  see --help for options
  
  Known problems: 
    * Probably only works if currency is behind the price
    * All receipts are assumed to be in the same mailbox.
      "[Gmail]/All Mail" is default. use --mailbox to change
    * Password is plain text in terminal
    * 'NoMethodError: undefined method ‘dump’ for nil:NilClass'
      - Seems to happen on WiFi. Connection too slow for threaded download?
  
  Changelog:
    19 Feb 2009 - 0.1.1:
      * Changed default mailbox to '[Gmail]/All Mail'
      * Searches all mail in gmail
      
    19 Feb 2009 - 0.1.0: 
      * initial
      
      
  TODO:
    * More stats and graphs!
    * HTML output (maybe eaven xml?)
    * JSON output
    * Confirm counts (off by one for some reason)
    * Dont spam too many threads when downloading

=end


require 'net/imap'
require 'set'

require 'optparse'

options = {
  :username => nil,
  :password => nil,
  :host => 'imap.gmail.com',
  :port => 993,
  :ssl => true,
  :mailbox => '[Gmail]/All Mail',
  :stats => true,
  :paid => true,
  :free => false
}
OptionParser.new do |opts|
  opts.banner = "Usage: appstore.rb [options]"
  
  opts.separator ""
  opts.separator "User options:"
  
  opts.on("-u", "--username USERNAME", "Username") do |v|
    options[:username] = v
  end
  
  opts.on("-m", "--mailbox MAILBOX", "Mailbox to search (default: Apple Receipt)") do |v|
    options[:mailbox] = v
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
  
  
  opts.separator ""
  opts.separator "Common options:"
          
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!


#Ask for credentials
if not options[:username]
  puts "Enter username (e.g example@gmail.com)"
  options[:username] = STDIN.readline.strip
end
puts "Enter password (caution, will be visible!)"
options[:password] = STDIN.readline.strip



options[:query] = ['FROM', 'do_not_reply@apple.com', 'SUBJECT', 'Your receipt']

def parse body
  #Get the plain text version
  body = body.match(/------=_Part_.+?\r\n\r\n(.+?)---=_Part_/m).captures.first
  body = body.gsub("=\r\n", '')

  #Translate some HEX encoded chars to ascii or utf8 or whatever
  body = body.gsub!(/=([A-F0-9][A-F0-9])/) do |c|
    c[1..2].to_a.pack('H*')
  end

  itemnames = [:item_number, :name, :version, :seller, :price]

  #Extract interesting data
  info = {
    :billed_to => body.match(/Billed to:\r\n([^\r]+)\r\n([^\r]+)\r\n/).captures.reverse,
    :date  => body.match(/Receipt Date: ([^\r]+)\r\n/).captures.first,
    :total => body.match(/Order Total: (\d+\.\d+)(.+)  \r\n/).captures.first,
    :items => body.scan(/(Q\d+)\s+([^ ].+), (v.+), Seller: (.+)\s+([^\s]*Free|[^\s]*\d+\.\d+[^\s]*)\r/).map{ |s| Hash[*itemnames.zip(s.map{ |s| s.strip }).flatten]}
  }

  info
end

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
mail.each do |message_id|
  Thread.new do #TODO: one thread per receipt might be overkill if hundreds of receipts..
    body = imap.fetch(message_id, "BODY[TEXT]")[0].attr['BODY[TEXT]']
    data << parse(body)
  end
end
imap.logout()
puts "-"*txt_dl.length

#Get data for all apps
apps = data.map do |mail|
  app = mail[:items]
  app.each do |a|
    a[:date] = mail[:date]
  end
  app
end.flatten

#generate some statistics
apps_names = apps.map{ |a| a[:name] }
apps_names_set = Set.new(apps_names)

apps_free = apps.select{|a|a[:price]=="Free"}
apps_free_names = apps_free.map{ |a| a[:name] }
apps_free_names_set = Set.new(apps_free_names)
apps_free_updates = apps_free_names.length - apps_free_names_set.length

apps_paid = apps.reject{|a|a[:price]=="Free"}
apps_paid_names = apps_paid.map{ |a| a[:name] }
apps_paid_names_set = Set.new(apps_paid_names)
apps_paid_updates = apps_paid_names.length - apps_paid_names_set.length

#TODO: map paid apps by currency (if needed. probably not)
money_spent_apps = apps_paid.map{ |a| a[:price].to_f }.inject(0){ |r,v| r+v }
money_spent_apps = money_spent_apps.to_i if money_spent_apps - money_spent_apps.to_i == 0.0

#show paid apps?
if options[:paid]
  width_name = 14
  width_price = 8
  width_seller = 14
  width_date = 0

  def max a,b; return a if a > b; b; end
  #find minimum widths
  apps_paid.each do |app|
    width_name = max(width_name, app[:name].length+1)
    width_price = max(width_price, app[:price].length+1)
    width_seller = max(width_seller, app[:seller].length+1)
    width_date = max(width_date, app[:date].length+1)
  end

  puts ""
  puts "paid apps"
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
  #print all paid apps
  apps_paid.sort(&method(:sortfun)).each do |app|
    args = [ app[:name], width_name,
             app[:price], width_price,
             app[:seller],  width_seller,
             app[:date], width_date ]
    puts dataformatstr%args
  end
  puts ""
end


#Show statistics?
if options[:stats]
  #Print totals
  puts txt_stat = "Statistics:"
  puts "-"*txt_stat.length
  puts " Total applications: #{apps_names_set.length}"
  puts "    Total free apps: #{apps_free_names_set.length}" #dont count updates
  puts " Total free updates: #{apps_free_updates}"
  puts "    Total paid apps: #{apps_paid_names_set.length}"
  puts " Total paid updates: #{apps_paid_updates}"
  #take an amount and replace the value to get the right currency
  spent_str = apps_paid.first[:price].sub(/\d+.\d+/, money_spent_apps.to_s)
  puts "  Total money spent: #{spent_str}"
end


