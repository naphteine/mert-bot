require 'date'
require 'telegram/bot'
require 'lingua/stemmer'
require 'rufus-scheduler'
require 'json'
require 'benchmark'

# Pure
def logger(text)
  puts "#{DateTime.now} #{text}"
  open('logs/buruki.log', 'a') { |f|
    f.puts "#{DateTime.now} #{text}"
  }
end

# Globals
load('secrets.rb')

$waking_up = Process.clock_gettime(Process::CLOCK_MONOTONIC)
$trStemmer = Lingua::Stemmer.new(:language => "tr")
$scheduler = Rufus::Scheduler.new(:lockfile => ".rufus-scheduler.lock")
$autojob = Rufus::Scheduler::Job
$states = Hash.new
$love = Hash.new
$dialog = JSON.load_file "assets/dialog.json"
$answers = JSON.load_file "assets/answers.json"
$caricatures = Dir.glob('assets/img/caricatures/*')
$morale = 50
$last = Hash.new

begin
  $images = JSON.load_file('assets/image_hashes.json')
  logger("DEBUG: #{$images.length} fotoğraf kimliği dosyadan yüklendi.")
rescue
  $images = Hash.new
  logger("DEBUG: Fotoğraf kimlikleri yüklenemedi! Yenisi yaratıldı.")
end

begin
  $learned = JSON.load_file('assets/learned.json')
  logger("DEBUG: #{$learned.length} öğrenilen yanıt dosyadan yüklendi.")
rescue
  $learned = Hash.new
  logger("DEBUG: Öğrenilen yanıtlar yüklenemedi! Yenisi yaratıldı.")
end

begin
  $insertable = JSON.load_file('assets/insertable.json')
  logger("DEBUG: #{$insertable.length} tane sokulabilir nesne dosyadan yüklendi.")
rescue
  $insertable = ["kamyon", "kamyonet", "boru", "başı", "apartman", "kule"]
  logger("DEBUG: Sokulabilir nesneler yüklenemedi! Yenisi yaratıldı.")
end

# Functions
def geri_sok(mesaj)
  sonsuz_mesaj = mesaj[/(.*)\s/,1][/(.*)\s/,1]
  eksiz_kelime = $trStemmer.stem(sonsuz_mesaj.split.last)
  return sonsuz_mesaj.chomp(sonsuz_mesaj.split.last) + eksiz_kelime
end

def diyalog_kur(user_id, message)
  answer = ""

  # Check hash and get user state
  if $states.has_key?(user_id) == false
    $states[user_id] = "BASA_DON"
  end

  if message.to_s.strip.empty?
    return ""
  end

  state = $states[user_id]

  # Check dialogs and find ID == state
  begin
    gelenler = $dialog.find { |h1| h1['id'] == state }['gelenler']
  rescue Exception => e
    logger("EXCEPTION: Diyalog ID #{state} yok! #{e}")
    return ""
  end

  unless gelenler.to_s.strip.empty?
    # Check every possible messages for a match
    begin
      find_matches = gelenler.find { |h1| h1['gelen'].find { |h2| h2.downcase==message.downcase } }
    rescue Exception => e
      logger("EXCEPTION: Mesaj #{message} yok! #{e}")
      return ""
    end


    unless find_matches.to_s.strip.empty?
      # Update state
      $states[user_id] = find_matches['kontrolcu']

      # Get a random response
      answer = find_matches['cevap'].sample.strip

      # Post-process response, if starts with "___"
      if answer[0, 3] == "___"
        begin
          answers_to_process = $answers.find {|h1| h1['id']==answer}['cevaplar'].sample
        rescue Exception => e
          logger("EXCEPTION: Cevap #{answer} yok! #{e}")
          return ""
        end

        $states[user_id] = answers_to_process['kontrolcu']
        processed_answer = answers_to_process['cevap'].sample.strip

        unless processed_answer.to_s.strip.empty?
          answer = processed_answer
        end
      end

      return answer
    end
  end

  return ""
end

def diyalog_bul(diyalog, anahtar)
  return diyalog.find { |h1| h1['id'] == anahtar }
end

def diyalog_listele(diyalog, anahtar)
  bul = diyalog_bul(diyalog, anahtar)["gelenler"]

  if bul.empty?
    return ""
  end

  cevap = String.new
  bul.map { |h1| cevap << "Gelenler: " << h1["gelen"].to_s << " Cevaplar: " << h1["cevap"].to_s << " Beklenen: " << h1["kontrolcu"] << "\n" }
  return cevap
end

def diyalog_tum_listele(diyalog)
  if diyalog.empty?
    return ""
  end

  cevap = String.new
  diyalog.map { |h1| cevap << h1['id'].to_s << " " }
  return cevap
end

def diyalog_istendi(msg)
  if msg.to_s.strip.empty?
    return "Boş atma amk"
  end

  begin
    istenen = command_arguments(msg)

    if istenen == "tamliste"
      return diyalog_tum_listele($dialog)
    end
    return diyalog_listele($dialog, istenen)
  rescue Exception => e
    logger "DEBUG: diyalog_istendi: #{e.to_s}"
    return "Olmadı niyeyse amk"
  end
end

def diyalog_ekle(message)
  if message.to_s.strip.empty?
    return "Boş atma mk"
  end

  begin
    return "Dur daha yok bundan"
  rescue
    return "Olmuyo amk nedense"
  end
end

def command_arguments(command)
  return command.split(/(.+?)\s(.+)/)[-1]
end

def cmd_args(input)
  return input.split(/\s(.+)/)
end

def awake
  raw_seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - $waking_up).round()
  raw_minutes = raw_seconds / 60
  hours = raw_minutes / 60
  seconds = raw_seconds - raw_minutes * 60
  minutes = raw_minutes - hours * 60

  if raw_seconds > 3659
    output = "#{hours} saat #{minutes} dakika"
  elsif raw_seconds > 3599
    output = "#{hours} saat"
  elsif raw_seconds > 59
    output = "#{minutes} dakika #{seconds} saniye"
  else
    output = "#{seconds} saniye oldu daha dur aq"
  end

  return output
end

def ogren(msg, splitter: ",")
  begin
    splitted = msg.split(splitter)

    if splitted.length != 2
      return "Böyle olmaz kardeş şöyle yapacaksın: /ogren Merhaba#{splitter} Al sana araba (o)))"
    end

    if ($learned.has_key?(splitted.first.downcase))
      return "Bundan var kardeş, değiştireceksek /lanogren kullan"
    end

    $learned[splitted.first.downcase] = splitted.last
    return ["Ekledim kardeş", "Tamamdır kardeş", "Bu da oldu kardeş", "Bunu da ekledim kardeş"].sample
  rescue
    return "Bu nasıl iş amk, olmuyor"
  end
end

def sokekle(msg)
  begin
    if msg.length < 1
      return "Bu çok kısa, olmaz kardeş şöyle yapacaksın: /sokekle boru"
    end

    if ($insertable.include?(msg.to_s.downcase))
      return "Bundan var kardeş"
    end

    $insertable.append(msg.to_s.downcase)
    return ["Ekledim kardeş", "Tamamdır kardeş", "Bu da oldu kardeş", "Bunu da ekledim kardeş"].sample
  rescue
    return "Bu nasıl iş amk, olmuyor"
  end
end

def lanogren(msg, splitter: ",")
  begin
    splitted = msg.split(splitter)

    if splitted.length != 2
      return "Böyle olmaz kardeş şöyle yapacaksın: /lanogren Merhaba#{splitter} Al sana araba (o)))"
    end

    $learned[splitted.first.downcase] = splitted.last
    return "Ekledim kardeş"
  rescue
    return "Bu nasıl iş amk, olmuyor"
  end
end

def json_to_file(var, file, description)
  begin
    File.open(file, "w+") do |f|
      f << JSON.pretty_generate(var)
    end
    logger("DEBUG: #{var.length} adet #{description.to_s.downcase} kaydedildi.")
    return "Tamamdır kardeş #{var.length} adet #{description.to_s.downcase} kaydettim"
  rescue Exception => e
    logger("EXCEPTION: #{description.to_s.capitalize} kaydı sırasında hata: #{e}")
    return "Durumum yoktu #{description.to_s.downcase} kaydedemedim be kardeş"
  end
end

def imghashes
  json_to_file($images, "assets/image_hashes.json", "fotoğraf kimliği")
end

def tamogren
  json_to_file($learned, "assets/learned.json", "öğrenilen yanıt")
end

def tamsokekle
  json_to_file($insertable, "assets/insertable.json", "sokulabilir nesne")
end

def kafayigom
  json_to_file($dialog, "assets/dialog.json", "diyalog")
end

def kafayicek
  begin
    $dialog = JSON.load_file "assets/dialog.json"
    $responses = JSON.load_file "assets/answers.json"
    $caricatures = Dir.glob('assets/caricatures/*')
    return "Çektim çektim"
  rescue Exception => e
    return "Çekemedim"
  end
end

def son_getir(chat_id)
  begin
    if $last.has_key?(chat_id)
      return $last[chat_id]
    else
      return "Bilmiyorum valla kardeş"
    end
  rescue
    return "Durumum yoktu öğrenemedim kardeş"
  end
end

def son_guncelle(chat_id, msg)
  $last[chat_id] = msg;
end

def cevir(chat_id, msg)
  if msg =~ /\/son$/
    cevirilecek = son_getir(chat_id)
  else
    cevirilecek = msg
  end

  if cevirilecek.empty?
    return "Böyle bir şey yok ki kardeş"
  end

  return cevirilecek.split.reverse.join(" ")
end

def tam_cevir(chat_id, msg)
  if msg =~ /\/son$/
    cevirilecek = son_getir(chat_id)
  else
    cevirilecek = msg
  end

  if cevirilecek.empty?
    return "Böyle bir şey yok ki kardeş"
  end

  return cevirilecek.to_s.reverse
end

def karisik(chat_id, msg)
  if msg =~ /\/son$/
    cevirilecek = son_getir(chat_id)
  else
    cevirilecek = msg
  end

  if cevirilecek.empty?
    return "Böyle bir şey yok ki kardeş"
  end

  return cevirilecek.split.shuffle.join(" ")
end

def handle_cmd(chat_id, input)
  begin
    # Check if it's really a command (i.e. starts with a slash)
    unless input.chars[0] == "/"
      logger "DEBUG handle_cmd: Input is not a command"
      return ""
    end

    # Prepare variables
    seperated = cmd_args(input)
    args = seperated[-1]
    cmd = seperated[0]
    logger "DEBUG handle_cmd: Seperated: #{cmd} :: #{args}"

    # Check if it's for us
    splitted = cmd.split('@')
    unless splitted[1].nil?
      unless splitted[1] == "buruki_bot"
        logger "DEBUG handle_cmd: Command is not for the bot"
        return ""
      end
    end

    # Handle the command
    pure_cmd = splitted[0]
    logger "DEBUG handle_cmd: Handling command: #{cmd} => #{pure_cmd}"

    case pure_cmd
    when "/cevir"
      return cevir(chat_id, args)
    when "/diyalog"
      return diyalog_istendi(args)
    when "/eklediyalog"
      return diyalog_ekle(args)
    when "/kafacek"
      return kafayicek
    when "/karisik"
      return karisik(chat_id, args)
    when "/kaydet"
      return "Her şeyi kaydediyorum\n" << json_to_file($dialog, "assets/dialog.json", "diyalog") << "\n" << json_to_file($learned, "assets/learned.json", "öğrendiğim yanıtı") << "\n" << json_to_file($insertable, "assets/insertable.json", "sokulabilir nesneyi") << "\nBunların hepsini çıkarken zaten kaydedecektim"
    when "/lanogren"
      return lanogren(args)
    when "/lanogren~>"
      return lanogren(args, splitter: "~>")
    when "/ogren"
      return ogren(args)
    when "/ogren~>"
      return ogren(args, splitter: "~>")
    when "/start"
      return "Türkçe konuş"
    when "/sokekle"
      return sokekle(args)
    when "/son"
      return son_getir(chat_id)
    when "/tamcevir"
      return tam_cevir(chat_id, args)
    when "/uyanik"
      return "#{awake()} uykum geldi aq kaç saat olmuş böyle"
    end
  rescue Exception => e
    logger "EXCEPTION handle_cmd: #{e}"
  end
end

def active_response(msg)
  case msg
  when /^Sana girsin$/i
    return "Sana da " + $insertable.sample.strip.downcase + " girsin"
  when /^Mert Kore'de saat kaç$/i
    return "Kardeş Kore şuan " + DateTime.now.new_offset('+09:00').strftime("%H:%M")
  when /^Mert isim salla$/i
    return File.readlines("assets/isimler").sample.strip.capitalize + " nasıl"
  when /(görüyon mu)$|(görüyor musun)$/i
    return geri_sok(message.text) + " sana girsin"
  when /tamam mı$/i
    return ["Tamam olur", "Olmaz aq", "Olabilir", "Bana ne soruyon aq", "Olurmaz", "Olmazur"].sample
  when /(Canım sıkılıyor)$|(canım sıkıldı)$/i
    return "Sıkma canını kardeeş", $caricatures.sample
  when /([asdfghjklşi]){6}\w+/i
    return ["ksdjfksdjfskd", "jhzdkjfhskjdfhks", "jsdhfjksdhfkjsdh", "ksdkjfsjdlkfjskl", "shdjkfhsdkf", "Jdhkjfhslkjh", "Hsdjfhsdkjf", "Kksdjfkds", "dkajflaskdjf", "kjdsalfjaldksfjalk", "sdkjlsdfjl", "dsaşfkjsaldf", "sakjdkasjd", "dsşafjasdkfs"].sample
  when /^Mert senin moralini sikeyim$/i
    if $morale > 0
      $morale -= 50
    end
    return "Ben de senin moralini sikeyim aq"
  when /^Mert senin moralini seveyim$/i
    if $morale < 100
      $morale += 50
    end
    return "Eyvallah kardeşim"
  when /^Mert moralin nasıl$/i
    case $morale
    when 0
      return "Moralim çok bozuk be"
    when 50
      return "İyi diyelim iyi olsun"
    when 100
      return "Çok güzel bir gün, götüme çiçek sokasım var be"
    end
  when /^Mert senden nefret ediyorum$/i
    if not $love.has_key?(message.from.id)
      $love[message.from.id] = 0
    end

    if $love[message.from.id] > -50
      $love[message.from.id] -= 50
    end
    
    return "Ben de senden amk"
  when /^Mert seviyorum seni$/i
    if not $love.has_key?(message.from.id)
      $love[message.from.id] = 0
    end

    if $love[message.from.id] < 50
      $love[message.from.id] += 50
    end

    return "Ben de seni seviyorum kardeşim"
  when /^Mert beni seviyor musun$/i
    case $love[message.from.id]
    when -50
      return "Hayır :d"
    when 50
      return "Tabii seviyorum oğlum kardeşimsin"
    else
      $love[message.from.id] = 0
      return "İyisin be kardeş"
    end
  end
end

# Telegram loop
def main
  begin
    retries = retries || 0
    Telegram::Bot::Client.run($token) do |bot|

      # Scheduler
      unless $scheduler.down?
        logger "Scheduler başlatılıyor.."

        begin
          if $scheduler.scheduled? $autojob
            logger "Zaten Autojob var, onu kaldırıyorum"
            $scheduler.unschedule $autojob
          else
            logger "Autojob'u kontrol ettim, açık değildi"
          end
        rescue
          logger "Autojob var mı yok mu kontrol edemedim"
        end

        $autojob = $scheduler.every '8110s' do
          tamogren()
          imghashes()

          reply = ["Yine çok neşelisiniz amk yazın hadi", "Amına koyem yazın gençlik", "Yine çok neşelisiniz. Yazsanıza aq", "Anlatın amk", "Saat #{DateTime.now.strftime("%H:%M")} olmuş, napıyorsunuz gençler"].sample
          logger ">>> chat##{$master_chat_id}: #{reply}"
          bot.api.send_message(chat_id:  $master_chat_id, text: reply)
        end
      end

      # Replies
      bot.listen do |message|
        retries = 0

        case message
        when Telegram::Bot::Types::InlineQuery
          results = [
            [1, 'Buruki', "Tek güç Buruki POWER!"],
            [2, 'Mert', "Ne var lan"]
          ].map do |arr|
            Telegram::Bot::Types::InlineQueryResultArticle.new(
              id: arr[0],
              title: arr[1],
              input_message_content: Telegram::Bot::Types::InputTextMessageContent.new(message_text: arr[2])
            )
          end
          bot.api.answer_inline_query(inline_query_id: message.id, results: results, cache_time: 5)
          logger "InlineQuery activity!"
        when Telegram::Bot::Types::Message
          logger "chat##{message.chat.id} #{message.from.id}@#{message.from.username}: #{message.text}"

          # Check if it's really a message
          if message.text.to_s.strip.empty?
            return
          end

          # Update last message hash
          unless message.text =~ /^\//
            son_guncelle(message.chat.id, message.text)
          end

          # Handling input
          ## Priority 1: Commands
          reply = handle_cmd(message.chat.id, message.text)

          ## Priority 2: Active responses
          if reply.to_s.strip.empty?
            rt = active_response(message.text)
            reply = rt[0]
            image = rt[1]
          end

          ## Priority 3: Dialog system
          if reply.to_s.strip.empty?
            time = Benchmark.measure do
              reply = diyalog_kur(message.from.id, message.text)
            end
            logger("BENCHMARK: Diyalog: #{time}")
          end

          ## Priority 4: Learned replies
          if reply.to_s.strip.empty?
            if ($learned.has_key?(message.text.downcase))
              reply = $learned[message.text.downcase]
            end
          end

          ## Priority 5: Words
          if reply.to_s.strip.empty?
            case message.text
            when /\bMert\b/i then reply = ["Adım geçti sanki lan", "Şşt arkamdan konuşmayın", "Mert dedin devamını getir kardeş", "Söyle söyle çekinme", "Nediir", "Vıyy", "Ne diyorsen"].sample
            when /\bam am\b/i then reply = "Hani bize am"
            end
          end

          # Send messages/photos, if it exists
          unless image.zero? or image.to_s.strip.empty?
            logger ">>> chat##{message.chat.id} #{message.from.id}@#{message.from.username}: IMG #{image}"
            if $images.has_key?(image) then bot.api.send_photo(chat_id: message.chat.id, photo: $images[image])
            else
              sent = bot.api.send_photo(chat_id: message.chat.id, photo: Faraday::UploadIO.new(image, 'image/jpg'))
              $images[image] = sent['result']['photo'][sent['result']['photo'].length - 1]['file_id']
            end
          end

          unless reply.to_s.strip.empty?
            logger ">>> chat##{message.chat.id} #{message.from.id}@#{message.from.username}: #{reply}"
            bot.api.send_message(chat_id: message.chat.id, text: reply)
          end
        end
      end
    end
  rescue SystemExit
    logger("EXCEPTION: SystemExit")
  rescue Faraday::ConnectionFailed => e
    logger("EXCEPTION: #{e}")
    retries += 1
    sleep_time = retries * 10
    if sleep_time > 60 then sleep_time 60 end
    logger("EXCEPTION: RETRY: #{retries}; #{sleep_time} saniye bekleniyor...")
    sleep sleep_time
    retry
  rescue Exception => e
    logger "EXCEPTION: #{e}"
  end
end

# Main code
logger("Buruki uyanıyor!")
main()

logger("Buruki uyumaya gidiyor..")
imghashes()
tamogren()
kafayigom()
tamsokekle()

logger("İyi geceler. -Buruki")
