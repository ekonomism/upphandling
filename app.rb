#  ruby app.rb -o $IP -p $PORT 
 
require 'rubygems'
require 'sinatra'
require 'nokogiri'   
require 'open-uri'
require 'sqlite3'
require 'yaml' 
require 'json'
require 'erb' 
require 'csv'
require 'sequel'
require 'securerandom'

enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }
set :environment, :development
configure do
  mime_type :csv, 'text/csv'
end

$ar = [2014, 2015, 2016, 2017]
$nyckeltalsnamn = {'inkopsandel' => 'Inköpsandel (procent av inköparens bruttoomsättning)', 'snittstorlek' => 'Snittomsättning för leverantörer (kronor)', 'snittanstallda' => 'Antal anställda hos leverantörer (snitt)', 
  'lokalandel' => 'Andel köp från lokala leverantörer', 'offandel' => 'Leverantörers försäljning till offentlig sektor (procent)', 'r_res' => 'Leverantörers rörelseresultat (procent)', 'a_res' => 'Leverantörers årsresultat (procent)'}
$kodnyckel = {'A' => 1..3, 'B' => 5..9, 'C' => 10..33, 'D' => 35..35, 'E' => 36..39, 'F' => 41..43, 'G' => 45..47, 'H' => 49..53, 'I' => 55..56, 'J' => 58..63, 'K' => 64..66, 'L' => 68..68, 'M' => 69..75, 'N' => 77..82, 'O' => 84..84, 'P' => 85..85, 'Q' => 86..88, 'R' => 90..93, 'S' => 94..96, 'T' => 97..98, 'U' => 99..99 }
$branscher = {'A' => 'Jordbruk, skogsbruk och fiske', 'B' => 'Utvinning av mineral', 'C' => 'Tillverkning', 'D' => 'Försörjning av el, gas, värme och kyla', 'E' => 'Vattenförsörjning; avloppsrening, avfallshantering och sanering', 
  'F' => 'Byggverksamhet', 'G' => 'Handel; reparation av motorfordon och motorcyklar', 'H' => 'Transport och magasinering', 'I' => 'Hotell- och restaurangverksamhet', 'J' => 'Informations- och kommunikationsverksamhet', 
  'K' => 'Finans- och försäkringsverksamhet', 'L' => 'Fastighetsverksamhet', 'M' => 'Verksamhet inom juridik, ekonomi, vetenskap och teknik', 'N' => 'Uthyrning, fastighetsservice, resetjänster och andra stödtjänster', 
  'O' => 'Offentlig förvaltning och försvar; obligatorisk socialförsäkring', 'P' => 'Utbildning', 'Q' => 'Vård och omsorg; sociala tjänster', 'R' => 'Kultur, nöje och fritid', 'S' => 'Annan serviceverksamhet', 
  'T' => 'Förvärvsarbete i hushåll; hushållens produktion av diverse varor och tjänster för eget bruk', 'U' => 'Verksamhet vid internationella organisationer, utländska ambassader o.d.' }

DB = Sequel.connect('sqlite://foretag.db', :pool_timeout => 10)
def initiera_databas
  # Skapar table och skriver över om den existerar
  DB.drop_table?(:relationer)
  DB.create_table! :relationer do
    primary_key :id
    Integer :ar
    String :lev, null: false
    String :levnamn
    String :kop
    String :kopnamn
    String :typ
    Integer :summa
    Integer :afakt
    Integer :sni
    String :snia
    String :sninamn
    Integer :lan # leverantörens länsnr
    Integer :kommun # leverantörens kommunnr
    Integer :stlkklass
    Date :regdatum
    Integer :anstallda
    Integer :omsattning # Leverantörers omsättning
    Integer :rres
    Integer :ares
    Integer :koms
    Integer :kkommun # köparens läns/kommunnummer
    Bignum :summaomsattning # Summa gånger omsättning
    Bignum :summaanstallda # Summa gånger anställda
    Integer :summaoffkvot # Summa gånger kvot mellan lev off forsäljning och omsättning
    Bignum :rressumma # Årets resultat gånger Summa
    Bignum :aressumma # Rörelseresultat gånger Summa
    Boolean :lokalflagga # Flagga som är true om lokal
  end
end

def initiera_tabell
  DB.drop_table?(:tabell)
  DB.create_table! :tabell do
    primary_key :id
    Integer :ar
    String :kop
    String :kopnamn
    String :typ
    String :snia
    Float :inkopsandel
    Float :snittstorlek
    Float :snittanstallda
    Float :lokalandel
    Float :offandel
    Float :rres
    Float :ares
  end
end

def indexera_databas
  DB.alter_table :relationer do
    add_index([:lev, :ar])
  end
end

# Inför index efter att data finns på plats
def indexera_tabell
  DB.alter_table :tabell do
    add_index([:snia, :typ])
  end
  puts "Klar skapa tabell"
end 

register do
  def auth(user)
    condition do
      redirect "/auth" unless session[:inloggad] == true
    end
  end
end

# Helper
class String
  def is_integer?
    self.to_i.to_s == self
  end
end

# Inköpare är en myndighet som köper av privata leverantörer, exempelvis en kommun, en region eller en statlig myndighet
class Inkopare
  attr_reader :kop, :kommun, :lan
  
  def initialize(kop)
    begin
      poster = DB[:relationer]
      @kop = kop
    rescue StandardError => e
      puts e
    end  
  end
  # Ta fram köparens namn
  def kopnamn(ar, sni)
    poster = DB[:relationer]
    if sni == "alla" then
      kopnamn = poster.select(:kopnamn).where(ar: ar, kop: @kop).first
      kopnamn = kopnamn.values[0] if !kopnamn.nil?
    else
      kopnamn = poster.select(:kopnamn).where(ar: ar, snia: sni, kop: @kop).first
      kopnamn = kopnamn.values[0] if !kopnamn.nil?
    end
    return kopnamn
  end
  # Ta fram typ
  def typ(ar, sni)
    poster = DB[:relationer]
    if sni == "alla" then
      typ = poster.select(:typ).where(ar: ar, kop: @kop).first
      typ = typ.values[0] if !typ.nil?
    else
      typ = poster.select(:typ).where(ar: ar, snia: sni, kop: @kop).first
      typ = typ.values[0] if !typ.nil?
    end
    return typ
  end
  # Andel inköp av kommunens totala omsättning
  def inkopsandel(ar, sni) 
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_inkop = poster.where(ar: ar, kop: @kop).exclude(koms: nil).sum(:summa)
        omsattning = poster.where(ar: ar, kop: @kop).exclude(koms: nil).avg(:koms)
      else
        summa_inkop = poster.where(ar: ar, snia: sni, kop: @kop).exclude(koms: nil).sum(:summa)
        omsattning = poster.where(ar: ar, kop: @kop).exclude(koms: nil).avg(:koms)
      end
      inkopsandel = 100*summa_inkop.to_f/omsattning
      inkopsandel = nil if inkopsandel.nan? || inkopsandel.infinite?
    rescue StandardError => e
      inkopsandel = nil  
    end   
    return inkopsandel
  end  
  # Snittstorlek på leverantörer vägt efter kontraktsstorlek 
  def snittstorlek(ar, sni) 
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_omsattning = poster.where(ar: ar, kop: @kop).exclude(summaomsattning: nil).sum(:summaomsattning)
        summa = poster.where(ar: ar, kop: @kop).exclude(summaomsattning: nil).sum(:summa)
      else
        summa_omsattning = poster.where(ar: ar, snia: sni, kop: @kop).exclude(summaomsattning: nil).sum(:summaomsattning)
        summa = poster.where(ar: ar, snia: sni, kop: @kop).exclude(summaomsattning: nil).sum(:summa)
      end
      snittstorlek = summa_omsattning.to_f/summa
      snittstorlek = nil if snittstorlek.nan?  || snittstorlek.infinite?
    rescue StandardError => e
      snittstorlek = nil
    end
    return snittstorlek
  end
  # Snitt antal anställda för leverantörer vägt efter kontraktsstorlek
  def snittanstallda(ar, sni)
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_anstallda = poster.where(ar: ar, kop: @kop).exclude(summaanstallda: nil).sum(:summaanstallda)
        summa = poster.where(ar: ar, kop: @kop).exclude(summaanstallda: nil).sum(:summa)
      else
        summa_anstallda = poster.where(ar: ar, snia: sni, kop: @kop).exclude(summaanstallda: nil).sum(:summaanstallda)
        summa = poster.where(ar: ar, snia: sni, kop: @kop).exclude(summaanstallda: nil).sum(:summa)
      end
      snittanstallda = summa_anstallda.to_f/summa
      snittanstallda = nil if snittanstallda.nan? || snittanstallda.infinite?
    rescue StandardError => e
      snittanstallda  = nil
    end
    return snittanstallda
  end
  # Andel som kommuner köper av lokala leverantörer
  def lokalandel(ar, sni)
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_inkop_lokal = poster.where(ar: ar, kop: @kop, lokalflagga: true).exclude(lokalflagga: nil).sum(:summa)
        summa_inkop_ejlokal = poster.where(ar: ar, kop: @kop, lokalflagga: false).exclude(lokalflagga: nil).sum(:summa)
      else
        summa_inkop_lokal = poster.where(ar: ar, snia: sni, kop: @kop, lokalflagga: true).exclude(lokalflagga: nil).sum(:summa)
        summa_inkop_ejlokal = poster.where(ar: ar, snia: sni, kop: @kop, lokalflagga: false).exclude(lokalflagga: nil).sum(:summa)
      end
      lokalandel = 100*summa_inkop_lokal.to_f/(summa_inkop_lokal + summa_inkop_ejlokal)
      lokalandel = nil if lokalandel.nan? || lokalandel.infinite?
    rescue StandardError => e
      lokalandel = nil
    end 
    return lokalandel
  end  
  # Andel av total omsättning som rör offentliga köpare
  def offandel(ar, sni)
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        off_kvot_summa = poster.where(ar: ar, kop: @kop).exclude(summaoffkvot: nil).sum(:summaoffkvot)
        summa_inkop = poster.where(ar: ar, kop: @kop).exclude(summaoffkvot: nil).sum(:summa)
      else
        off_kvot_summa = poster.where(ar: ar, kop: @kop, snia: sni).exclude(summaoffkvot: nil).sum(:summaoffkvot)
        summa_inkop = poster.where(ar: ar, kop: @kop, snia: sni).exclude(summaoffkvot: nil).sum(:summa)
      end
      offandel = 100*off_kvot_summa.to_f/summa_inkop
      offandel = nil if offandel.nan? || offandel.infinite?
    rescue StandardError => e
      offandel = nil
    end
    return offandel
  end
  # Årets resultat i genomsnitt för företag som säljer till köparen
  def rres(ar, sni)
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        rres_summa = poster.where(ar: ar, kop: @kop).exclude(rressumma: nil).sum(:rressumma)
        summa_oms_lev = poster.where(ar: ar, kop: @kop).exclude(rressumma: nil).sum(:summaomsattning)
      else
        rres_summa = poster.where(ar: ar, kop: @kop, snia: sni).exclude(rressumma: nil).sum(:rressumma)
        summa_oms_lev = poster.where(ar: ar, kop: @kop, snia: sni).exclude(rressumma: nil).sum(:summaomsattning)
      end
      r_res = 100*rres_summa.to_f/summa_oms_lev
      r_res = nil if r_res.nan? || r_res.infinite?
    rescue StandardError => e
      r_res = nil
    end
    return r_res
  end
  # Rörelseresultat i genomsnitt för företag som säljer till köparen 
  def ares(ar, sni)
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        ares_summa = poster.where(ar: ar, kop: @kop).exclude(aressumma: nil).sum(:aressumma)
        summa_oms_lev = poster.where(ar: ar, kop: @kop).exclude(aressumma: nil).sum(:summaomsattning)
      else
        ares_summa = poster.where(ar: ar, kop: @kop, snia: sni).exclude(aressumma: nil).sum(:aressumma)
        summa_oms_lev = poster.where(ar: ar, kop: @kop, snia: sni).exclude(aressumma: nil).sum(:summaomsattning)
      end
      a_res = 100*ares_summa.to_f/summa_oms_lev
      a_res = nil if a_res.nan? || a_res.infinite?
    rescue StandardError => e
      a_res = nil
    end
    return a_res
  end
    
end  

def rensa(lista)
  lista.each_with_index do |post, index|
    post = "" if post.nil?
    lista[index] = post.encode(Encoding::UTF_8).strip
  end
  return lista
end

def skapa_databas
  initiera_databas
  poster = DB[:relationer]
  threads = []
  snier = (1..3).to_a
  #snier = snier.concat([461, 462, 463, 464, 465, 466, 467, 468, 469, 4641, 4642, 4643, 4644, 4645, 4646, 4647, 4648, 4649, 471, 472, 473, 474, 475, 476, 477, 478, 479])
  snier = snier.each_slice(30).to_a
  snier.each do |snigrupp|
    threads << Thread.new do
      snigrupp.each do |sni|
        puts "SNI", sni, Time.now
        filnamn = "sni/SNI" + sni.to_s + ".csv"
        if File.file?(filnamn) then
          CSV.foreach(filnamn, :encoding => 'iso-8859-1', :col_sep => ";") do |relation|
            relation = rensa(relation)
            $ar.each do |ar|
              if relation[21].is_integer? && ar == 2014 then
                poster.insert(ar: ar, lev: relation[0], levnamn: relation[1], kop: relation[2], kopnamn: relation[3], typ: relation[4], summa: relation[21].split(",")[0].to_i, afakt: relation[22], sni: relation[23], sninamn: relation[24])
              end
              if relation[17].is_integer? && ar == 2015 then
                poster.insert(ar: ar, lev: relation[0], levnamn: relation[1], kop: relation[2], kopnamn: relation[3], typ: relation[4], summa: relation[17].split(",")[0].to_i, afakt: relation[18], sni: relation[19], sninamn: relation[20])
              end
              if relation[13].is_integer? && ar == 2016 then
                poster.insert(ar: ar, lev: relation[0], levnamn: relation[1], kop: relation[2], kopnamn: relation[3], typ: relation[4], summa: relation[13].split(",")[0].to_i, afakt: relation[14], sni: relation[15], sninamn: relation[16])
              end
              if relation[9].is_integer? && ar == 2017 then
                poster.insert(ar: ar, lev: relation[0], levnamn: relation[1], kop: relation[2], kopnamn: relation[3], typ: relation[4], summa: relation[9].split(",")[0].to_i, afakt: relation[10], sni: relation[11], sninamn: relation[12])
              end
              if relation[5].is_integer? && ar == 2018 then
                poster.insert(ar: ar, lev: relation[0], levnamn: relation[1], kop: relation[2], kopnamn: relation[3], typ: relation[4], summa: relation[5].split(",")[0].to_i, afakt: relation[6], sni: relation[7], sninamn: relation[8])
              end
            end
          end
        else
          puts "Ingen fil för SNI:", sni
        end
      end
    end
  end
  threads.each { |thr| thr.join }
  indexera_databas
  puts "Klar relationer"
end

def addera_foretag     
  poster = DB[:relationer]
  nummer = 0
  threads = []
  $ar.each do |ar|
    threads << Thread.new do
      filnamn = "foretag_ar_" + ar.to_s + ".csv"
      CSV.foreach(filnamn, :encoding => 'iso-8859-1') do |foretag|
        foretag = rensa(foretag)
        nummer += 1
        puts nummer if nummer % 10000 == 0
        if foretag[43].is_integer? && foretag[55].is_integer? && foretag[76].is_integer? then
          poster.where(ar: ar, lev: foretag[0]).update(lan: foretag[6], kommun: foretag[7], stlkklass: foretag[10], regdatum: foretag[16], anstallda: foretag[35], omsattning: foretag[43].to_i*1000, rres: foretag[55].to_i*1000, ares: foretag[76].to_i*1000)
        end
      end
    end
  end
  threads.each { |thr| thr.join }
  puts "Klar företag"      
  $kodnyckel.each do |key, value|
    nedre = value.first * 1000 - 1
    ovre = (value.last + 1) * 1000
    puts $kodnyckel[key]
    poster.where(sni: nedre..ovre).update(snia: key)
  end  
  puts "Klar avdelning"
      
  CSV.foreach("kommunkodorgnr.csv", :encoding => 'iso-8859-1', :col_sep => ";") do |rad|
    rad = rensa(rad)
    puts rad.inspect
    poster.where(kop: rad[2]).update(kkommun: rad[0].sub(/^0+/, ""))
    poster.where(kop: rad[2]).update(kopnamn: rad[1])
  end
  puts "Klar kommunkoder => orgnr"
   
  CSV.foreach("kommuner.csv", :col_sep => ";") do |kommun|
    kommun = rensa(kommun)
    $ar.each do |ar|
      poster.where(kkommun: kommun[0][0..3].sub(/^0+/, ""), typ: "Kommun").update(koms: kommun[ar-2010].to_i*1000)
    end
  end  
  CSV.foreach("landsting.csv", :col_sep => ";") do |landsting|
    landsting = rensa(landsting)
    $ar.each do |ar|
      poster.where(kkommun: landsting[0][0..1].sub(/^0+/, ""), typ: "Landsting").update(koms: landsting[ar-2010].to_i*1000000)
    end
  end  
  puts "Klar kommuner"
  
  # Skapa variabel med summa gånger offentlig andel för leverantör
  poster.each do |post|
    if !post[:summa].nil? && !post[:omsattning].nil? then
      begin
        off_lev_summa = poster.where(ar: post[:ar], lev: post[:lev]).exclude(summa: nil).sum(:summa)
        lev_oms_summa = poster.where(ar: post[:ar], lev: post[:lev]).exclude(omsattning: nil).avg(:omsattning)
        off_lev_summa =  lev_oms_summa if off_lev_summa > lev_oms_summa # Kvoten får aldrig vara > 1
        summa_off_kvot = post[:summa]*off_lev_summa/lev_oms_summa
        summa_off_kvot = nil if summa_off_kvot.nan? || summa_off_kvot.infinite?
      rescue ZeroDivisionError
        summa_off_kvot = nil
      end
      poster.where(id: post[:id]).update(summaoffkvot: summa_off_kvot)
    end
  end
  puts "Klar Summa gånger leveranser"
  
  # Skapa variabel summa gånger omsättning, anställda och flagga lokal
  poster.each do |post|
    if !post[:summa].nil? && !post[:omsattning].nil? then
      summa_omsattning = post[:summa]*post[:omsattning] 
      poster.where(id: post[:id]).update(summaomsattning: summa_omsattning)
    end
  end  
  puts "Klar Summa gånger Omsättning"
  poster.each do |post|
    if !post[:summa].nil? && !post[:anstallda].nil? then
      summa_anstallda = post[:summa]*post[:anstallda] 
      poster.where(id: post[:id]).update(summaanstallda: summa_anstallda)
    end
  end  
  puts "Klar Summa gånger Anställda"
  poster.each do |post|
    if !post[:lan].nil? && !post[:kommun].nil? then
      if ((post[:kommun] == post[:kkommun]) && (post[:typ] == "Kommun")) || ((post[:lan] == post[:kkommun]) && (post[:typ] == "Landsting")) then
        poster.where(id: post[:id]).update(lokalflagga: true)
      else
        poster.where(id: post[:id]).update(lokalflagga: false)
      end  
    end  
  end  
  puts "Klar flagga Lokal"
  
  # Skapa variabler r_res dividerat med omsättning gånger Summa och a_res dividerat med omsättning gånger Summa
  poster.each do |post|
    if !post[:summa].nil? && !post[:omsattning].nil? && !post[:rres].nil? then
      begin
        rres_summa = post[:summa]*post[:rres] 
      rescue ZeroDivisionError
        rres_summa == nil
      end
      poster.where(id: post[:id]).update(rressumma: rres_summa)
    end
  end  
  poster.each do |post|
    if !post[:summa].nil? && !post[:omsattning].nil? && !post[:ares].nil? then
      begin
        ares_summa = post[:summa]*post[:ares]
      rescue ZeroDivisionError
        ares_summa == nil
      end
      poster.where(id: post[:id]).update(aressumma: ares_summa)
    end
  end  
  puts "Klar rres_oms_summa och ares_oms_summa"
end

# Tar fram uppgifter om köpare
def hamta_tabellhash(kop, ar, sni)
  item = Inkopare.new(kop)
  tabell_hash = Hash.new
  tabell_hash['kop'] = kop
  tabell_hash['ar'] = ar
  tabell_hash['snia'] = sni
  tabell_hash['kopnamn'] = item.kopnamn(ar, sni)
  tabell_hash['typ'] = item.typ(ar, sni)
  tabell_hash['inkopsandel'] = item.inkopsandel(ar, sni)
  tabell_hash['snittstorlek'] = item.snittstorlek(ar, sni)
  tabell_hash['snittanstallda'] = item.snittanstallda(ar, sni)
  tabell_hash['lokalandel'] = item.lokalandel(ar, sni)
  tabell_hash['offandel'] = item.offandel(ar, sni)
  tabell_hash['rres'] = item.rres(ar, sni)
  tabell_hash['ares'] = item.ares(ar, sni)
  return tabell_hash
end  

def skapa_tabell
  initiera_tabell
  threads = []
  col = Hash.new
  tabell = DB[:tabell]
  poster = DB[:relationer]
  kopare = poster.select(:kop).distinct.all.map {|x| x[:kop]}
  # Data för samtliga branscher
  snier = ("A".."U").to_a.concat(["alla"])
  snier.each do |sni|
    puts "Avdelning: ", sni, Time.now
    kopare.each do |koparen|
      $ar.each do |ar|
        threads << Thread.new do
          col[ar] = hamta_tabellhash(koparen, ar, sni)
        end
      end
      threads.each { |thr| thr.join }
      $ar.each do |ar|
        tabell.insert(ar: col[ar]['ar'], kop: col[ar]['kop'], kopnamn: col[ar]['kopnamn'], snia: col[ar]['snia'], typ: col[ar]['typ'], inkopsandel: col[ar]['inkopsandel'], snittstorlek: col[ar]['snittstorlek'], snittanstallda: col[ar]['snittanstallda'], lokalandel: col[ar]['lokalandel'], offandel: col[ar]['offandel'], rres: col[ar]['rres'], ares: col[ar]['ares']) 
      end
    end
  end
  indexera_tabell
end 

def skriv_till_csv
  poster = DB[:relationer]
  CSV.open("upphandlingsdata.csv", "wb") do |csv|
    poster.each_with_index do |row, index|
      csv << row.keys if index == 0
      csv << row.values
    end
  end
  puts "Klar skriv Relationer till CSV"
end

def skriv_tabell_till_csv
  poster = DB[:tabell]
  CSV.open("tabell.csv", "wb") do |csv|
    poster.each_with_index do |row, index|
      csv << row.keys if index == 0
      csv << row.values
    end
  end
  puts "Klar skriv Tabell till CSV"
end

skapa_databas
addera_foretag
skriv_till_csv
inkop = Inkopare.new("2120001579")
ar = 2017
puts "Köpnamn", inkop.kopnamn(ar, "A")
puts "Typ", inkop.typ(ar, "A")
puts "Inköpsandel", inkop.inkopsandel(ar, "A")
puts "Offandel", inkop.offandel(ar, "A")
puts "Snittstorlek", inkop.snittstorlek(ar, "A")
puts "Snittanstallda", inkop.snittanstallda(ar, "A")
puts "Lokalandel", inkop.lokalandel(ar, "A")
puts "Rörelseresultat", inkop.rres(ar, "A")
puts "Årets resultat", inkop.ares(ar, "A")
skapa_tabell
skriv_tabell_till_csv

# Kolla om inloggad    
before do
  @user = session[:inloggad]
end

# Ladda ner bearbetade data
get "/data", :auth => :true do
  send_file 'tabell.csv', :disposition => 'attachment', :filename => 'tabell.csv'
end

# Ladda ner källdata
get "/transaktioner", :auth => :true do
   send_file 'upphandlingsdata.csv', :disposition => 'attachment', :filename => 'transaktioner.csv'
end    

# Inloggningssidan
get "/auth" do
  erb :signin
end

# Tar emot inloggningsuppgifter
post "/login" do
  if params[:password] == "password" then
    session[:inloggad] = true
    $fel = false
    redirect "/"
  else
    $fel = true
    redirect "/auth"
  end  
end

# Loggar ut
get "/logout" do
  session[:inloggad] = false
  redirect "/auth"
end

# Ritar upp diagram i iframe
get '/diagram?', :auth => :true do
  session[:diagram] = params['diagram'] if !params['diagram'].nil?
  session[:rad] = params['rad'] if !params['rad'].nil?
  tabell = DB[:tabell]
  typ = "Kommun" if session[:kopare] == 'kommun'
  typ = "Landsting" if session[:kopare] == 'lan'
  typ = "Statlig enhet" if session[:kopare] == 'myndighet'
  @diagram = Hash.new
  $ar.each do |ar|
    @diagram[ar] = [0.0, 0.0, {:kopnamn => 'nada'}]
    if session[:diagram] == 'inkopsandel' then
      @diagram[ar][0] = tabell.where(ar: ar, snia: session[:sni], kop: session[:rad]).avg(:inkopsandel)
      @diagram[ar][1] = tabell.where(ar: ar, snia: session[:sni], typ: typ).avg(:inkopsandel)
      @diagram[ar][2] = tabell.select(:kopnamn).where(ar: ar, kop: session[:rad]).first
    elsif session[:diagram] == 'snittstorlek' then
      @diagram[ar][0] = tabell.where(ar: ar, snia: session[:sni], kop: session[:rad]).avg(:snittstorlek)
      @diagram[ar][1] = tabell.where(ar: ar, snia: session[:sni], typ: typ).avg(:snittstorlek)
      @diagram[ar][2] = tabell.select(:kopnamn).where(ar: ar, kop: session[:rad]).first
    elsif session[:diagram] == 'snittanstallda' then
      @diagram[ar][0] = tabell.where(ar: ar, snia: session[:sni], kop: session[:rad]).avg(:snittanstallda)
      @diagram[ar][1] = tabell.where(ar: ar, snia: session[:sni], typ: typ).avg(:snittanstallda)
      @diagram[ar][2] = tabell.select(:kopnamn).where(ar: ar, kop: session[:rad]).first
    elsif session[:diagram] == 'lokalandel' then
      @diagram[ar][0] = tabell.where(ar: ar, snia: session[:sni], kop: session[:rad]).avg(:lokalandel)
      @diagram[ar][1] = tabell.where(ar: ar, snia: session[:sni], typ: typ).avg(:lokalandel)
      @diagram[ar][2] = tabell.select(:kopnamn).where(ar: ar, kop: session[:rad]).first
    elsif session[:diagram] == 'offandel' then
      @diagram[ar][0] = tabell.where(ar: ar, snia: session[:sni], kop: session[:rad]).avg(:offandel)
      @diagram[ar][1] = tabell.where(ar: ar, snia: session[:sni], typ: typ).avg(:offandel)
      @diagram[ar][2] = tabell.select(:kopnamn).where(ar: ar, kop: session[:rad]).first
    elsif session[:diagram] == 'r_res' then
      @diagram[ar][0] = tabell.where(ar: ar, snia: session[:sni], kop: session[:rad]).avg(:rres)
      @diagram[ar][1] = tabell.where(ar: ar, snia: session[:sni], typ: typ).avg(:rres)
      @diagram[ar][2] = tabell.select(:kopnamn).where(ar: ar, kop: session[:rad]).first
    elsif session[:diagram] == 'a_res' then
      @diagram[ar][0] = tabell.where(ar: ar, snia: session[:sni], kop: session[:rad]).avg(:ares)
      @diagram[ar][1] = tabell.where(ar: ar, snia: session[:sni], typ: typ).avg(:ares)
      @diagram[ar][2] = tabell.select(:kopnamn).where(ar: ar, kop: session[:rad]).first
    end 
  end
  erb :diagram
end

# Tar emot förfrågan om filtrering av tabell
get "/filter?" do
  session[:filter] = params[:filter]
end

# Tar fram tabell med givna val och ev filtrering
get '/tabell?', :auth => :true do
  # Tabelldel
  session[:ar] = params['ar'] if !params['ar'].nil?
  session[:kopare] = params['kopare'] if !params['kopare'].nil?
  session[:sni] = params['sni'] if !params['sni'].nil?
  session[:sortera] = params['sortera'] if !params['sortera'].nil?
  # Hanterar val av SNI och filtrering
  if session[:sni] == "alla" then
    if session[:filter].nil? then
      tabell = DB[:tabell]
    else
      sok = session[:filter] + '%'
      tabell = DB[:tabell].where(Sequel.ilike(:kopnamn, sok))
    end
  else
    if session[:filter].nil? then
      tabell = DB[:tabell].where(snia: session[:sni])
    else
      sok = session[:filter] + '%'
      tabell = DB[:tabell].where(snia: session[:sni]).where(Sequel.ilike(:kopnamn, sok))
    end  
  end
  # Hanterar val av sorteringskolumn
  if session[:sortera] == 'kop_namn' then
    tabell = tabell.order(:kopnamn)
  elsif session[:sortera] == 'inkopsandel'
    tabell = tabell.reverse(:inkopsandel)
  elsif session[:sortera] == 'snittstorlek'
    tabell = tabell.reverse(:snittstorlek)
  elsif session[:sortera] == 'snittanstallda'
    tabell = tabell.reverse(:snittanstallda)
  elsif session[:sortera] == 'lokalandel'
    tabell = tabell.reverse(:lokalandel)
  elsif session[:sortera] == 'offandel'
    tabell = tabell.reverse(:offandel)
  elsif session[:sortera] == 'r_res'
    tabell = tabell.reverse(:rres)
  elsif session[:sortera] == 'a_res'
    tabell = tabell.reverse(:ares)
  end
  # Hanterar val av inköparetyp
  typ = "Kommun" if session[:kopare] == 'kommun'
  typ = "Landsting" if session[:kopare] == 'lan'
  typ = "Statlig enhet" if session[:kopare] == 'myndighet'
  # Renderar tabell med hjälp av Unpoly
  @tabell_h = tabell.where(ar: session[:ar], typ: typ, snia: session[:sni]).all
  erb :tabell
end
  
get '/', :auth => :true do
  erb :index
end

