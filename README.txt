Searches your imap enabled mail account for iTunes receipts and displays statistics abount 
your purchases.

Using: 
  
  If you have a gmail account:
    0. Enable imap on www.gmail.com
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
  * Don't know how how receipts for tv-shows look so there is a possibility they will be mistaken for music
  * Probably only works if currency is behind the price (default in sweden)
  * All receipts are assumed to be in the same mailbox.
    "[Gmail]/All Mail" is default. use --mailbox to change
  * Password is plain text in terminal if you don't have the highline gem
  * 'NoMethodError: undefined method ‘dump’ for nil:NilClass'
    - Seems to happen on slow WiFi. Connection too slow for threaded download? No problem on 802.11n-network though
  * Plain text version of receipts have fixed width descriptions so the 
    seller field is missing or incomplete if app name is too long

Changelog:
  12 March 2009 - 0.2:
    * Counts and lists music!
    * Total spent on apps and music
    * 20 threads to download mail
    * Option to list paid or free, music or apps, or all
    * Masked password if you have installed the highline gem
    
  19 Feb 2009 - 0.1.1:
    * Changed default mailbox to '[Gmail]/All Mail'
    * Searches all mail in gmail
    * Max 10 threads to download mail
    
  19 Feb 2009 - 0.1.0: 
    * initial
    
    
TODO:
  * Webapp
  * Include tv-shows. (need help by someone who can buy tv-shows...)
  * More stats and graphs!
  * HTML output (maybe xml?)
  * JSON output
