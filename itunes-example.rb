require 'itunes'

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
    begin
      h = HighLine.new
      h.ask("Password: ") { |q| q.echo = '*'}
    rescue
      puts "Failed to ask for masked password. Trying clear text"
      puts "Enter Password (caution, will be visible!)"
      STDIN.readline.strip
    end
  else
    puts "ruby gem highline not found. Password will be plain text."
    puts " To enable masked password in terminal, run 'sudo gem install highline'"
    puts "Enter password (caution, will be visible!)"
    STDIN.readline.strip
  end
end

itunes = Itunes.new
#itunes.load_dir '~/Desktop/mails2'
puts "Enter username for imap enabled gmail account:"
username = STDIN.readline.strip
itunes.load_gmail username, get_password

class Item
  def date_str
    date.strftime "%y/%m/%d"
  end
end

def print items
  width_name = width_price = width_date = width_seller = 0
  items.each do |item|
    width_name   = width_name > item.name.length ? width_name : item.name.length
    width_price  = width_price > item.price.length ? width_price : item.price.length
    width_date   = width_date > item.date_str.length ? width_date : item.date_str.length
    width_seller = width_seller > item.seller.length ? width_seller : item.seller.length if item.is_app?
  end
  
  width_seller = -width_seller
  width_name = -width_name
  width_date = -width_date
  
  dataformatstr = "%1$*2$s  %3$*4$s  %5$*6$s  %7$*8$s"
  
  args = [ 'Name', width_name, 'Price', width_price, 'Seller',  width_seller, 'Date', width_date ]
  puts txt_header =dataformatstr%args
  args = [ '----', width_name, '-----', width_price, '------',  width_seller, '----', width_date ]
  puts dataformatstr%args
  
  items.sort_by(:price, :name).each do |item|
    args = [item.name, width_name, item.price, width_price, item.seller.to_s, width_seller, item.date_str, -width_date]
    puts dataformatstr%args
  end

end

#p itunes.items.last
print itunes.items
