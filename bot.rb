require 'date'
require 'telegram/bot'
require 'lingua/stemmer'

# Globals
load('secrets.rb')

$waking_up = Process.clock_gettime(Process::CLOCK_MONOTONIC)
$trStemmer = Lingua::Stemmer.new(:language => "tr")

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

Telegram::Bot::Client.run($token) do |bot|
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