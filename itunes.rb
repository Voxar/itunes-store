
=begin

  Author: Patrik Sjöberg <voxxar@gmail.com>
  
  Loads itunes reciepts from imap mail accounts
  
  Usage:
    i = Itunes.new
    i.load_dir File.expand_path('~/Desktop/mails2')
    puts i.items
    puts i.items.free.apps
    puts i.items.music.paid
    puts i.mails.inject(0){ |t,m| t+m.total.to_f }
=end


#TODO: receipts_from_pop
#TODO: receipts_from_itunes if possible

  
require 'net/imap'
require 'set'
require 'ostruct'
require 'logger'

MAILBOX_QUERY = ['FROM', 'do_not_reply@apple.com', 'SUBJECT', 'Your receipt']

## Represents  an itunes recipe
class Mail < Struct.new(:billed_to, :date, :total, :items)
end

## Represents an itunes item
class Item
  attr_reader :mail, :item_number, :description, :price
  attr_reader :name, :version, :seller #if is_app
  def initialize mail, item_number, description, price
    @mail = mail
    @item_number = item_number.strip
    @description = description.strip
    @price = price.strip
    
    if match = description.match(/^(.+), (v.+?), (?:Seller:)? ?(.*)$/)
      @name     = match[1].strip
      @version  = match[2].strip
      @seller   = match[3].strip
      @is_app   = true
    else
      @name = description.strip
      @version = nil
      @seller = nil
      @is_app = false
    end
  end
  
  def date
    mail.date
  end
  
  def is_app?
    @is_app
  end
  
  def is_music?
    !is_app?
  end
  
  def is_show?
    false
  end
  
  def type
    return :app   if is_app?
    return :music if is_music?
    return :show  if is_show?
    :other
  end
  
  def inspect
    "#<#{self.class} \"#{self}\", #{type.to_s}>"
  end
  
  def to_s
    "#{item_number}\t#{description}\t#{price}"
  end

  def <=> r
    name.downcase <=> r.name.downcase
  end
end

## Represents a list of itunes items with filter functions
class ItemList
  def initialize items
    @items = items
  end
  
  def free
    ItemList.new @items.select { |i| i.price == "Free" }
  end
  
  def paid
    ItemList.new @items.reject { |i| i.price == "Free" }
  end
  
  def apps
    ItemList.new @items.select { |i| i.is_app? }
  end
  
  def music
    ItemList.new @items.select { |i| i.is_music? }
  end
  
  def shows
    ItemList.new @items.select { |i| i.is_show? }
  end
  
  def do_sort_by by
    case by
    when :price: i = @items.sort{ |a,b| b.send(by).to_f <=> a.send(by).to_f }
    when :name : i = @items.sort
    else         i = @items.sort{ |a,b| a.send(by) <=> b.send(by) }
    end
    ItemList.new i
  end
  
  def do_cmp(by,a,b)
    case by
    when :price: d = b.send(by).to_f <=> a.send(by).to_f 
    when :name : d = a <=> b
    else         d = a.send(by) <=> b.send(by)
    end
    d
  end
  
  def cmp args, a, b
    args.each do |arg|
      d = do_cmp(arg, a, b)
      return d if d != 0.0
    end
    return 0.0
  end
  
  def sort_by *args
    i = @items.sort do |a,b|
      cmp(args,a,b)
    end
    ItemList.new i
  end
  
  def distinct(by = :name)
    visited = Set.new
    main = []
    other = []
    @items.each do |i|
      v = i.send(by)
      if visited.add v
        main << i
      else
        other << i
      end
    end
    main
  end
  
  def to_a
    @items
  end
  
  def method_missing name, *arg, &block
    to_a.send(name, *arg, &block)
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

class ItunesException < Exception; end

class Itunes
  attr_reader :data, :stats
  attr_accessor :logger
  
  def initialize
    @logger = Logger.new STDERR
  end
  
  def load_imap user, pass, host, port, ssl, mailbox
    @mails = receipts_from_imap(user, pass, host, port, ssl, mailbox)
  end
  
  def load_dir path
    @mails = receipts_from_dir(path)
  end
  
  def load_gmail user, pass
    load_imap user, pass, 'imap.gmail.com', 993, true, '[Gmail]/All Mail'
  end
  
  def mails
    @mails
  end
  
  def items
    ItemList.new(mails.map do |mail|
      mail.items
    end.flatten)
  end
  
  def test
    items.apps.sort_by(:seller).each{ |i| p i }
#    puts items.paid.apps.to_a.sort{ |b,a| a.price.to_f<=>b.price.to_f }.map{ |i| "#{i.name}  #{i.price}" }
    p items.inject(0){ |r,i| r+i.price.to_f }
    p mails.to_a.inject(0){ |r,m| r+m.total.to_f }
  end
  
  protected
  
  ##Parse a mail
  def parse body
    #Get the plain text version
    part = body.match(/------=_Part_.+?\r\n\r\n(.+?)---=_Part_/m)
    body = part.captures.first if part
    body = body.gsub("=\r\n", '')

    #Translate some HEX encoded chars
    body = body.gsub!(/=([A-F0-9][A-F0-9])/) do |c|
      c[1..2].to_a.pack('H*')
    end || body

    mail = Mail.new
    
    #Extract interesting data
    mail.billed_to = body.match(/Billed to:\r\n([^\r]+)\r\n([^\r]+)\r?\n/).captures.reverse,
    mail.date      = itunes_date_to_date(body.match(/Receipt Date: ([^\r]+)\r?\n/).captures.first),
    mail.total     = body.match(/Order Total: (\d+\.\d+)(.+)  \r?\n/).captures.first,
    mail.items     = body.scan(/(Q?\d+)\s+(\S.+)\s+(\S*Free|\S*\d+\.\d+\S*)\r?\n/).map do |row| 
      Item.new mail, *row 
    end
    
    #    :items => body.scan(/(Q\d+)\s+([^\s].+), (v.+), Seller: (.+)\s+([^\s]*Free|[^\s]*\d+\.\d+[^\s]*)\r?\n/).map{ |s| Hash[*itemnames.zip(s.map{ |s| s.strip }).flatten]}

    mail
  end
  
  ##Read recepies from textfiles in a directory
  def receipts_from_dir path
    path = File.expand_path(path)
    logger.info(txt = "Reading recepits in directory '#{path}'")
    data = []
    Dir.glob("#{path}/**") do |filename|
      open(filename) do |f|
        data << parse(f.read)
      end
    end
    data.compact
  end
  
  ##Fetch recepies from a mail server
  def receipts_from_imap user, pass, host, port, ssl, mailbox
    #check the mail
    logger.info "Connecting to #{host}:#{port} #{"using ssl" if ssl}"
    imap = Net::IMAP.new(host, port, ssl)
    begin
      imap.login(user, pass)
    rescue Net::IMAP::NoResponseError => e
      throw ItunesException.new("Wrong username and/or password")
    end

    #look for receipts
    mail = nil
    #select mailbox
    begin
      imap.examine(mailbox) #throws
    rescue Net::IMAP::NoResponseError => e
      throw ItunesException.new("Mailbox #{mailbox} does not exist")
    end

    logger.info "Looking for iTunes receipts"
    mail = imap.search(MAILBOX_QUERY)
    if mail.length == 0
      throw ItunesException.new("No recipts found in mailbox #{mailbox}")
    end

    logger.info txt_dl = "Downloading #{mail.length} receipts..."
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

    data.compact
  end
  
  #helpers
  def req name
    begin
      require name
      true
    rescue LoadError => e
      p e
    end
  end
  
  def itunes_date_to_date(str)
    Time.mktime(*str.split("/").reverse)
  end
  
end


#i = Itunes.new
#i.load_dir File.expand_path('~/Desktop/mails2')
#i.test