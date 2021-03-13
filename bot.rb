require 'date'
require 'telegram/bot'
require 'lingua/stemmer'
require 'rufus-scheduler'

# Globals
load('secrets.rb')

$waking_up = Process.clock_gettime(Process::CLOCK_MONOTONIC)
$trStemmer = Lingua::Stemmer.new(:language => "tr")
$scheduler = Rufus::Scheduler.new

# Functions
def logger(text)
	puts "#{DateTime.now} #{text}"
	open('logs/buruki.log', 'a') { |f|
		f.puts "#{DateTime.now} #{text}"
	}
end

def geri_sok(mesaj)
	sonsuz_mesaj = mesaj[/(.*)\s/,1][/(.*)\s/,1]
	eksiz_kelime = $trStemmer.stem(sonsuz_mesaj.split.last)
	return sonsuz_mesaj.chomp(sonsuz_mesaj.split.last) + eksiz_kelime
end

# Main code
logger("Buruki uyanıyor!")

# Telegram loop
Telegram::Bot::Client.run($token) do |bot|
	# Scheduler
	$scheduler.every '30m' do
		reply = ["Yaa kendi başıma da yazabiliyorum aq", "Anlatın amk", "Melih napıyorsun?", "Saat #{DateTime.now.strftime("%H:%M")} olmuş hala uyanık mısınız lan"].sample
		chatid = -483338367
		logger ">>> chat##{chatid}: #{reply}"
		bot.api.send_message(chat_id: chatid, text: reply)
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
			# Commands
			when /^\/start$/i then reply = "Türkçe konuş"
			when /^\/uyu$/i
				if message.from.id == $master_id
					reply = "İyi geceler kral"
				end

			# Full-match
			when /^(Mert ibnesi)$|^(Amcık Mert)$|^(İbne Mert)$/i then reply = "Doğru konuş lan"
			when /^Mert$/i then reply = ["Söyle kardeş", "Buyur kardeşim", "Söyle", "Evet gardaş"].sample
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
			when /^(Naber Mert)$|^(Mert nasılsın)$|^(Naptın Mert)$|^(Mert naber ya)$|^(Nasıl oldun Mert)$|^(Nasılsın Mert)$/i then reply = "İyiyim kardeş seni sormalı"
			when /^(İyiyim)$|^(Ben de iyiyim)$|^(İyiyim Mert)$/i then reply = "İyi kal gardaşş"
			when /^(Bak)$|^(\(o\)\)\))$/i then reply = "(o)))"
			when /^(Görüşürüz Mert)$|^(Mert görüşürüz)$|^(Görüşürüz beyler)$/i then reply = "Görüşürüz kardeşim"
			when /\b(Maya'yı sik)$|\b(Mayayı sik)$/i then reply = "Ne diyon lan aq Maya benim bacım sayılır. Seni sikerim doğru konuş"
			when /^Mert, Melih'i sik$/i then reply = "Meliiih gel attaya gidecez"
			when /^Sinirim çok bozuk$/i then reply = "Sinirlerini topla kardeş"
			when /^Yarın buluşalım mı$/i then reply = "Buluşalım ben de geliyorum"
			when /^Yarın erken kalkacağım$/i then reply = "Git yat uyu o zaman"
			when /^(Mert amk)$|^(Mert senin amk)$|^(Mert senin ben amk)$|^(Senin ben amk Mert)$/i then reply = "Ben de senin amk"
			when /^Yazılım$/i then reply = "Yazılmayalım"
			when /^Seni seviyorum kral$/i then reply = "Eyvallah tosun ben de seni seviyim"
			when /^En iyi dostumsun$/i then reply = "Sen benim kardeşimsin kardeşim. Ölümüne"
			when /^Hastayım$/i then reply = "Geçmiş olsun kardeşim"
			when /^Mert'e vurdururuz$/i then reply = "Kim bana vurduruyor şimdi ona göre şeyetcem"
			when /^Mert neyin var$/i then reply = "23cm kalin sert büyük yarragimi görmek istermisin suan dimdik ve oldukça sert"
			when /^Görmek isterim$/i then reply = "Ezan bitsin hemen gösterecem"
			when /^Adamsın lan Mert$/i then reply = "Eyvallah kardeşim"
			when /^👊$/i then reply = "👊🏽"
			when /(Canım sıkılıyor)$|(canım sıkıldı)$/i
				bot.api.send_photo(chat_id: message.chat.id, photo: Faraday::UploadIO.new('assets/images/Kurtuluş.jpg', 'image/jpeg'))
			when /([asdfghjklşi]){4}\w+/i then reply = ["dkajflaskdjf", "kjdsalfjaldksfjalk", "sdkjlsdfjl", "dsaşfkjsaldf", "sakjdkasjd", "dsşafjasdkfs"].sample
			
			# Words
			when /\bAm\b/i then reply = "Lam kim dedi onu nerede"
			when /\bMert\b/i then reply = ["Adım geçti sanki lan", "Şşt arkamdan konuşmayın"].sample
			end

			unless reply.to_s.strip.empty?
				logger ">>> chat##{message.chat.id} #{message.from.id}@#{message.from.username}: #{reply}"
				bot.api.send_message(chat_id: message.chat.id, text: reply)
			end
		end
	end
end

logger("Buruki uyumaya gidiyor..")