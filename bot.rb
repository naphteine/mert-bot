require 'date'
require 'telegram/bot'
require 'lingua/stemmer'
require 'rufus-scheduler'
require 'json'

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
$scheduler = Rufus::Scheduler.new

$states = Hash.new

$dialog = JSON.load_file "assets/dialog.json"
$answers = JSON.load_file "assets/answers.json"

$caricatures = Dir.glob('assets/img/caricatures/*')

begin
	$images = JSON.load_file('assets/image_hashes.json')
	logger("DEBUG: #{$images.length} fotoğraf kimliği dosyadan yüklendi.")
rescue
	$images = {
	}
	logger("DEBUG: Fotoğraf kimlikleri yüklenemedi! Yenisi yaratıldı.")
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

# Main code
logger("Buruki uyanıyor!")

# Telegram loop
begin
	Telegram::Bot::Client.run($token) do |bot|
		# Scheduler
		$scheduler.every '8011s' do
			reply = ["Yine çok neşelisiniz amk yazın hadi", "Amına koyem yazın gençlik", "Yine çok neşelisiniz. Yazsanıza aq", "Anlatın amk", "Saat #{DateTime.now.strftime("%H:%M")} olmuş, napıyorsunuz gençler"].sample
			logger ">>> chat##{$master_chat_id}: #{reply}"
			bot.api.send_message(chat_id:  $master_chat_id, text: reply)
		end

		# Replies
		bot.listen do |message|
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
				
				case message.text
				# Priority 1: Commands
				when /^\/start$/i then reply = "Türkçe konuş"
				when /^\/kafayı göm$/i
					if message.from.id == $master_id
						reply = "Gömemem be kardeş"
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
					image = $caricatures.sample
				when /([asdfghjklşi]){6}\w+/i then reply = ["dkajflaskdjf", "kjdsalfjaldksfjalk", "sdkjlsdfjl", "dsaşfkjsaldf", "sakjdkasjd", "dsşafjasdkfs"].sample

				# Priority 3: Dialog system
				else
					reply = diyalog_kur(message.from.id, message.text)
				end

				# Priority 4: Words
				if reply.to_s.strip.empty?
					case message.text
					when /\bMert\b/i then reply = ["Adım geçti sanki lan", "Şşt arkamdan konuşmayın"].sample
					when /\bAm\b/i then reply = "Lam kim dedi onu nerede"
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
rescue Exception => e
	logger("EXCEPTION: #{e}")
end

logger("Buruki uyumaya gidiyor..")

begin
	File.open('assets/image_hashes.json', "w+") do |f|
		f << $images.to_json
	end
	logger("DEBUG: #{$images.length} fotoğraf kimliği kaydedildi.")
rescue Exception => e
	logger("EXCEPTION: Fotoğraf kimliği kaydederken hata: #{e}")
end

logger("İyi geceler. -Buruki")