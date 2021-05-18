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
	$images = {
	}
	logger("DEBUG: Fotoğraf kimlikleri yüklenemedi! Yenisi yaratıldı.")
end

begin
    $learned = JSON.load_file('assets/learned.json')
	logger("DEBUG: #{$learned.length} öğrenilen yanıt dosyadan yüklendi.")
rescue
    $learned = Hash.new
	logger("DEBUG: Öğrenilen yanıtlar yüklenemedi! Yenisi yaratıldı.")
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

def ogren(message)
  begin
    args = command_arguments(message)
    splitted = args.split(",")

    if splitted.length != 2
      return "Böyle olmaz kardeş"
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

def lanogren(message)
  begin
    args = command_arguments(message)
    splitted = args.split(",")

    if splitted.length != 2
      return "Böyle olmaz kardeş"
    end

    $learned[splitted.first.downcase] = splitted.last
    return "Ekledim kardeş"
  rescue
    return "Bu nasıl iş amk, olmuyor"
  end
end

def imghashes
  begin
      File.open('assets/image_hashes.json', "w+") do |f|
          f << JSON.pretty_generate($images)
      end
      logger("DEBUG: #{$images.length} fotoğraf kimliği kaydedildi.")
  rescue Exception => e
      logger("EXCEPTION: Fotoğraf kimliği kaydederken hata: #{e}")
  end
end

def tamogren
  begin
      File.open('assets/learned.json', "w+") do |f|
          f << JSON.pretty_generate($learned)
      end
      logger("DEBUG: #{$learned.length} öğrenilen yanıt kaydedildi.")
  rescue Exception => e
      logger("EXCEPTION: Öğrenilen yanıtları kaydederken hata: #{e}")
  end
end

def kafayigom
  begin
      File.open('assets/dialog.json', "w+") do |f|
          f << JSON.pretty_generate($dialog)
      end
      logger("DEBUG: #{$dialog.length} diyalog kaydedildi.")
  rescue Exception => e
      logger("EXCEPTION: Diyalogları kaydederken hata: #{e}")
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
  if command_arguments(msg) =~ /\/son$/
    cevirilecek = son_getir(chat_id)
  else
    cevirilecek = command_arguments(msg)
  end

  if cevirilecek.empty?
    return "Böyle bir şey yok ki kardeş"
  end

  return cevirilecek.split.reverse.join(" ")
end

def tam_cevir(chat_id, msg)
  if command_arguments(msg) =~ /\/son$/
    cevirilecek = son_getir(chat_id)
  else
    cevirilecek = command_arguments(msg)
  end

  if cevirilecek.empty?
    return "Böyle bir şey yok ki kardeş"
  end

  return cevirilecek.to_s.reverse
end

# Main code
logger("Buruki uyanıyor!")

# Telegram loop
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
                unless message.text =~ /^\//
                  son_guncelle(message.chat.id, message.text)
                end
				
				case message.text
				# Priority 1: Commands
				when /^\/start$/i then reply = "Türkçe konuş"
                when /^\/kafayı göm/i
                  begin
                      File.open('assets/dialog.json', "w+") do |f|
                          f << JSON.pretty_generate($dialog)
                      end
                      logger("DEBUG: #{$dialog.length} diyalog kaydedildi.")
                      reply = "Tamamdır kardeş #{$dialog.length} tane diyalog kaydettim, zaten çıkarken kaydedecektim de unutmam artık"
                  rescue Exception => e
                      logger("EXCEPTION: Öğrenilen yanıtları kaydederken hata: #{e}")
                      reply = "Kaydedemedim be kardeş, durumum yoktu.."
                  end
				when /^\/kafayı çek$/i
					if message.from.id == $master_id
						begin
							$dialog = JSON.load_file "assets/dialog.json"
							$responses = JSON.load_file "assets/answers.json"
							$caricatures = Dir.glob('assets/caricatures/*')
							reply = "Çektim çektim"
						rescue Exception => e
							reply = "Çekemedim"
						end
					end
                when /^\/ogren/i
                  reply = ogren(message.text)
                when /^\/lanogren/i
                  reply = lanogren(message.text)
                when /^\/tamogren/i
                  begin
                      File.open('assets/learned.json', "w+") do |f|
                          f << JSON.pretty_generate($learned)
                      end
                      logger("DEBUG: #{$learned.length} öğrenilen yanıt kaydedildi.")
                      reply = "Tamamdır kardeş #{$learned.length} tane öğrendiğimi kaydettim, zaten çıkarken kaydedecektim de unutmam artık"
                  rescue Exception => e
                      logger("EXCEPTION: Öğrenilen yanıtları kaydederken hata: #{e}")
                      reply = "Kaydedemedim be kardeş, durumum yoktu.."
                  end
                when /^\/diyalog/i
                  reply = diyalog_istendi(message.text)
                when /^\/eklediyalog/i
                  reply = diyalog_ekle(message.text)
                when /^\/uyanik/i then reply = "#{awake()}. Uykum var aq (gerçekten yoruldum)"
                when /^\/son$/i
                  reply = son_getir(message.chat.id)
                when /^\/cevir/i
                  reply = cevir(message.chat.id, message.text)
                when /^\/tamcevir/i
                  reply = tam_cevir(message.chat.id, message.text)


				# Priority 2: Quick responses
				when /^(Mert ibnesi)$|^(Amcık Mert)$|^(İbne Mert)$/i then reply = "Doğru konuş lan"
				when /^(Melih ibnesi)$|^(Amcık Melih)$|^(İbne Melih)$/i then reply = "Şşş ibne olabilir ama o da içimizden"
				when /^Use Signal$/i then reply = "I can't aq"
				when /^Gönüller bir$/i then reply = "Tabbbe ✊✊"
				when /^Ihı ohı ohı Mert$/i then reply = "Hıı şurdaki kızları ellesek"
				when /^31 çek$/i then reply = "Sevisiyorum ben düzenli"
				when /^Sana girsin$/i then reply = "Sana da " + File.readlines("assets/sokulabilir").sample.strip.downcase + " girsin"
				when /^Mert Kore'de saat kaç$/i then reply = "Kardeş Kore şuan " + DateTime.now.new_offset('+09:00').strftime("%H:%M")
				when /^Mert isim salla$/i then reply = File.readlines("assets/isimler").sample.strip.capitalize + " nasıl"
				when /(görüyon mu)$|(görüyor musun)$/i then reply = geri_sok(message.text) + " sana girsin"
                when /tamam mı$/i then reply = ["Tamam", "Olmaz kjsdfj"].sample
				when /^(İyi geceler Mert)$|^(İyi geceler)$|^(İyi geceler beyler)$/i then reply = "İyi geceler kardeşim"
				when /^(Selam Mert)$|^(Selamlar)$|^(Selam beyler)$|^(Merhaba beyler)$|^(Merhaba Mert)$|^(Merhaba)$/i then reply = "Hoş geldin kardeş"
				when /^(Bak)$|^(\(o\)\)\))$/i then reply = "(o)))"
				when /^(Görüşürüz Mert)$|^(Mert görüşürüz)$|^(Görüşürüz beyler)$/i then reply = "Görüşürüz kardeşim"
				when /\b(Maya'yı sik)$|\b(Mayayı sik)$/i then reply = "Ne diyon lan aq Maya benim bacım sayılır. Seni sikerim doğru konuş"
				when /^Mert, Melih'i sik$/i then reply = "Meliiih gel attaya gidecez"
				when /^Sinirim çok bozuk$/i then reply = "Sinirlerini topla kardeş"
				when /^Yarın buluşalım mı$/i then reply = "Buluşalım ben de geliyorum"
				when /^Yarın erken kalkacağım$/i then reply = "Git yat uyu o zaman"
				when /^Yazılım$/i then reply = "Yazılmayalım"
				when /^Seni seviyorum kral$/i then reply = "Eyvallah tosun ben de seni seviyim"
				when /^En iyi dostumsun$/i then reply = "Sen benim kardeşimsin kardeşim. Ölümüne"
				when /^Hastayım$/i then reply = "Geçmiş olsun kardeşim"
				when /^Mert'e vurdururuz$/i then reply = "Kim bana vurduruyor şimdi ona göre şeyetcem"
				when /^Mert neyin var$/i then reply = "Bir şeyim yok Allaha şükür jsadhfas"
				when /^Görmek isterim$/i then reply = "Ezan bitsin hemen gösterecem"
				when /^Adamsın lan Mert$/i then reply = "Eyvallah kardeşim"
				when /^👊$/i then reply = "👊🏽"
				when /(Canım sıkılıyor)$|(canım sıkıldı)$/i
					reply = "Sıkma canını kardeeş"
					image = $caricatures.sample
				when /([asdfghjklşi]){6}\w+/i then reply = ["ksdjfksdjfskd", "jhzdkjfhskjdfhks", "jsdhfjksdhfkjsdh", "ksdkjfsjdlkfjskl", "shdjkfhsdkf", "Jdhkjfhslkjh", "Hsdjfhsdkjf", "Kksdjfkds", "dkajflaskdjf", "kjdsalfjaldksfjalk", "sdkjlsdfjl", "dsaşfkjsaldf", "sakjdkasjd", "dsşafjasdkfs"].sample
				when /^Mert senin moralini sikeyim$/i
					if $morale > 0
						$morale -= 50
					end
					reply = "Ben de senin moralini sikeyim aq"
				when /^Mert senin moralini seveyim$/i
					if $morale < 100
						$morale += 50
					end
					reply = "Eyvallah kardeşim"
				when /^Mert moralin nasıl$/i
					case $morale
					when 0 then reply = "Moralim çok bozuk be"
					when 50 then reply = "İyi diyelim iyi olsun"
					when 100 then reply = "Çok güzel bir gün, götüme çiçek sokasım var be"
					end
				when /^Mert senden nefret ediyorum$/i
                  if not $love.has_key?(message.from.id)
                    $love[message.from.id] = 0
                  end

					if $love[message.from.id] > -50
						$love[message.from.id] -= 50
					end
					reply = "Ben de senden amk"
				when /^Mert seviyorum seni$/i
                  if not $love.has_key?(message.from.id)
                    $love[message.from.id] = 0
                  end

					if $love[message.from.id] < 50
						$love[message.from.id] += 50
					end
					reply = "Ben de seni seviyorum kardeşim"
				when /^Mert beni seviyor musun$/i
					case $love[message.from.id]
					when -50 then reply = "Hayır :d"
					when 50 then reply = "Tabii seviyorum oğlum kardeşimsin"
					else
						reply = "İyisin be kardeş"
						$love[message.from.id] = 0
					end

				# Priority 3: Dialog system
				else
					time = Benchmark.measure do
						reply = diyalog_kur(message.from.id, message.text)
					end
					logger("BENCHMARK: Diyalog: #{time}")
				end

				# Priority 4: Words
				if reply.to_s.strip.empty?
					case message.text
					when /\bMert\b/i then reply = ["Adım geçti sanki lan", "Şşt arkamdan konuşmayın", "Mert dedin devamını getir kardeş", "Söyle söyle çekinme", "Nediir", "Vıyy", "Ne diyorsen"].sample
					when /\bAm\bam\bam\b/i then reply = "Hani bize am"
					end
				end

                # Priority 5: Learned replies
                if reply.to_s.strip.empty?
                  unless message.text.to_s.strip.empty?
                    if ($learned.has_key?(message.text.downcase))
                      reply = $learned[message.text.downcase]
                    end
                  end
                end

				# Send messages/photos, if it exists
				unless image.to_s.strip.empty?
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
rescue Exception => e
	logger("EXCEPTION: #{e}")
    retries += 1
    sleep_time = retries * 10
    if sleep_time > 60 then sleep_time 60 end
    logger("EXCEPTION: RETRY: #{retries}; #{sleep_time} saniye bekleniyor...")
    sleep sleep_time
    retry
end

logger("Buruki uyumaya gidiyor..")

imghashes()
tamogren()
kafayigom()

logger("İyi geceler. -Buruki")
