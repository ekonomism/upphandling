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
require 'set'

enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) }

$kodnyckel = {'A' => 1..3, 'B' => 5..9, 'C' => 10..33, 'D' => 35..35, 'E' => 36..39, 'F' => 41..43, 'G' => 45..47, 'H' => 49..53, 'I' => 55..56, 'J' => 58..63, 'K' => 64..66, 'L' => 68..68, 'M' => 69..75, 'N' => 77..82, 'O' => 84..84, 'P' => 85..85, 'Q' => 86..88, 'R' => 90..93, 'S' => 94..96, 'T' => 97..98, 'U' => 99..99 }
$branscher = {'A' => 'Jordbruk, skogsbruk och fiske', 'B' => 'Utvinning av mineral', 'C' => 'Tillverkning', 'D' => 'Försörjning av el, gas, värme och kyla', 'E' => 'Vattenförsörjning; avloppsrening, avfallshantering och sanering', 
  'F' => 'Byggverksamhet', 'G' => 'Handel; reparation av motorfordon och motorcyklar', 'H' => 'Transport och magasinering', 'I' => 'Hotell- och restaurangverksamhet', 'J' => 'Informations- och kommunikationsverksamhet', 
  'K' => 'Finans- och försäkringsverksamhet', 'L' => 'Fastighetsverksamhet', 'M' => 'Verksamhet inom juridik, ekonomi, vetenskap och teknik', 'N' => 'Uthyrning, fastighetsservice, resetjänster och andra stödtjänster', 
  'O' => 'Offentlig förvaltning och försvar; obligatorisk socialförsäkring', 'P' => 'Utbildning', 'Q' => 'Vård och omsorg; sociala tjänster', 'R' => 'Kultur, nöje och fritid', 'S' => 'Annan serviceverksamhet', 
  'T' => 'Förvärvsarbete i hushåll; hushållens produktion av diverse varor och tjänster för eget bruk', 'U' => 'Verksamhet vid internationella organisationer, utländska ambassader o.d.' }

DB = Sequel.connect('sqlite://foretag.db')
def initiera_databas
  # Skapar table och skriver över om den existerar
  DB.create_table! :relationer do
    primary_key :Id
    String :Lev, null: false
    String :Lev_namn
    String :Kop
    String :Kop_namn
    String :Typ
    Integer :Summa
    Integer :AFakt
    Integer :SNI
    String :SNI_A
    String :SNI_namn
    Integer :Lan # leverantörens länsnr
    Integer :Kommun # leverantörens kommunnr
    Integer :Stlk_klass
    Date :Reg_datum
    Integer :Anstallda
    Integer :Omsattning # Leverantörers omsättning
    Integer :RRes
    Integer :ARes
    Integer :KOms
    Integer :KKommun # köparens läns/kommunnummer
    Integer :SummaOmsattning # Summa gånger omsättning
    Integer :SummaAnstallda # Summa gånger anställda
    Boolean :LokalFlagga # Flagga som är true om lokal
  end
  DB.create_table! :tabell do
    primary_key :Id
    String :Kop
    String :Kop_namn
    String :Typ
    String :SNI_A
    Float :Inkopsandel
    Float :Snittstorlek
    Float :Snittanstallda
    Float :Lokalandel
    Float :Offandel
  end
end

# Helper
class String
  def is_integer?
    self.to_i.to_s == self
  end
end

class Inkopare
  attr_reader :kop, :kommun, :lan
  
  def initialize(kop)
    begin
      poster = DB[:relationer]
      @kop = kop
      @typ = poster.select(:Typ).where(Kop: kop).first[:Typ]
      @kommun = poster.select(:Kommun).where(Kop: kop).exclude(Kommun: nil).first[:Kommun]
      @lan = poster.select(:Lan).where(Kop: kop).exclude(Lan: nil).first[:Lan]
    rescue StandardError => e
      @kop = nil
      @typ = nil
      @kommun = nil
      @lan = nil
    end  
  end
  
  def inkopsandel(sni) # Andel inköp av kommunens totala omsättning
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_inkop = poster.where(Kop: @kop).exclude(Summa: nil).sum(:Summa)
        omsattning = poster.where(Kop: @kop).exclude(KOms: nil).avg(:KOms)
      else
        summa_inkop = poster.where(SNI_A: sni, Kop: @kop).exclude(Summa: nil).sum(:Summa)
        omsattning = poster.where(Kop: @kop).exclude(KOms: nil).avg(:KOms)
      end
      inkopsandel = summa_inkop/omsattning
      inkopsandel = nil if inkopsandel.nan?
    rescue StandardError => e
      inkopsandel = nil  
    end   
    return inkopsandel
  end  
    
  def snittstorlek(sni) # Snittstorlek på leverantörer vägt efter kontraktsstorlek
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_omsattning = poster.where(Kop: @kop).exclude(SummaOmsattning: nil).sum(:SummaOmsattning)
        summa = poster.where(Kop: @kop).exclude(SummaOmsattning: nil).sum(:Summa)
      else
        summa_omsattning = poster.where(SNI_A: sni, Kop: @kop).exclude(SummaOmsattning: nil).sum(:SummaOmsattning)
        summa = poster.where(SNI_A: sni, Kop: @kop).exclude(SummaOmsattning: nil).sum(:Summa)
      end
      snittstorlek = summa_omsattning/summa
      snittstorlek = nil if snittstorlek.nan?
    rescue StandardError => e
      snittstorlek = nil
    end
    return snittstorlek
  end
    
  def snittanstallda(sni) # Snittstorlek på leverantörer vägt efter kontraktsstorlek
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_anstallda = poster.where(Kop: @kop).exclude(SummaAnstallda: nil).sum(:SummaAnstallda)
        summa = poster.where(Kop: @kop).exclude(SummaAnstallda: nil).sum(:Summa)
      else
        summa_anstallda = poster.where(SNI_A: sni, Kop: @kop).exclude(SummaAnstallda: nil).sum(:SummaAnstallda)
        summa = poster.where(SNI_A: sni, Kop: @kop).exclude(SummaAnstallda: nil).sum(:Summa)
      end
      snittanstallda = summa_anstallda.to_f/summa
      snittanstallda = nil if snittanstallda.nan?
    rescue StandardError => e
      snittanstallda  = nil
    end
    return snittanstallda
  end
  
  def lokalandel(sni) # Andel som kommuner köper av lokala leverantörer
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_inkop_lokal = poster.where(Kop: @kop, LokalFlagga: true).exclude(LokalFlagga: nil).sum(:Summa)
        summa_inkop_ejlokal = poster.where(Kop: @kop, LokalFlagga: false).exclude(LokalFlagga: nil).sum(:Summa)
      else
        summa_inkop_lokal = poster.where(SNI_A: sni, Kop: @kop, LokalFlagga: true).exclude(LokalFlagga: nil).sum(:Summa)
        summa_inkop_ejlokal = poster.where(SNI_A: sni, Kop: @kop, LokalFlagga: false).exclude(LokalFlagga: nil).sum(:Summa)
      end
      lokalandel = summa_inkop_lokal.to_f/(summa_inkop_lokal + summa_inkop_ejlokal)
      lokalandel = nil if lokalandel.nan?
    rescue StandardError => e
      lokalandel = nil
    end 
    return lokalandel
  end  
  
  def offandel(sni) # Andel privat försäljning bland leverantörer
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_inkop = poster.where(Kop: @kop).exclude(Omsattning: nil).sum(:Summa)
        summa_omsattning = poster.where(Kop: @kop).exclude(Omsattning: nil).sum(:Omsattning)
      else
        summa_inkop = poster.where(SNI_A: sni, Kop: @kop).exclude(Omsattning: nil).sum(:Summa)
        summa_omsattning = poster.where(SNI_A: sni, Kop: @kop).exclude(Omsattning: nil).sum(:Omsattning)
      end
      offandel = summa_inkop.to_f/summa_omsattning
      offandel = nil if offandel.nan?
    rescue StandardError => e
      offandel = nil
    end
    return offandel
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
  (1..1).each do |sni|
    puts sni
    filnamn = "sni/SNI" + sni.to_s + ".csv"
    if File.file?(filnamn) then
      CSV.foreach(filnamn, :encoding => 'iso-8859-1', :col_sep => ";") do |relation|
        relation = rensa(relation)
        if relation[9].is_integer? then
          poster.insert(Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[9].to_i, AFakt: relation[10], SNI: relation[11], SNI_namn: relation[12])
        end
      end
    else
      puts "Ingen fil för SNI:", sni
    end
  end
  #udda_sni = [461, 462, 463, 464, 465, 466, 467, 468, 469, 4641, 4642, 4643, 4644, 4645, 4646, 4647, 4648, 4649, 471, 472, 473, 474, 475, 476, 477, 478, 479]  
  udda_sni = []
  udda_sni.each do |sni|
    puts sni
    filnamn = "sni/SNI" + sni.to_s + ".csv"
    if File.file?(filnamn) then
      CSV.foreach(filnamn, :encoding => 'iso-8859-1', :col_sep => ";") do |relation|
        relation = rensa(relation)
        if relation[9].is_integer? then
          poster.insert(Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[9].to_i, AFakt: relation[10], SNI: relation[11], SNI_namn: relation[12])
        end
      end
    else
      puts "Ingen fil för SNI:", sni
    end
  end
  puts "Klar relationer"
  nummer = 0
  CSV.foreach("foretag_ar_2017.csv", :encoding => 'iso-8859-1') do |foretag|
    foretag = rensa(foretag)
    nummer += 1
    puts nummer if nummer % 10000 == 0
    poster.where(Lev: foretag[0]).update(Lan: foretag[6], Kommun: foretag[7], Stlk_klass: foretag[10], Reg_datum: foretag[16], Anstallda: foretag[35], Omsattning: foretag[43].to_i*1000, RRes: foretag[55], ARes: foretag[76])
  end   
  puts "Klar företag"
  $kodnyckel.each do |key, value|
    nedre = value.first * 1000 - 1
    ovre = (value.last + 1) * 1000
    puts $kodnyckel[key]
    poster.where(SNI: nedre..ovre).update(SNI_A: key)
  end  
  puts "Klar avdelning"
  CSV.foreach("kommunkodorgnr.csv", :encoding => 'iso-8859-1', :col_sep => ";") do |rad|
    rad = rensa(rad)
    puts rad.inspect
    poster.where(Kop: rad[2]).update(KKommun: rad[0].sub(/^0+/, ""))
  end
  puts "Klar kommunkoder => orgnr"
  CSV.foreach("kommuner.csv") do |kommun|
    kommun = rensa(kommun)
    poster.where(KKommun: kommun[0][0..3].sub(/^0+/, ""), Typ: "Kommun").update(KOms: -kommun[2].to_i*1000)
  end  
  CSV.foreach("landsting.csv") do |landsting|
    landsting = rensa(landsting)
    poster.where(KKommun: landsting[0][0..1].sub(/^0+/, ""), Typ: "Landsting").update(KOms: -landsting[2].to_i*1000000)
  end  
  puts "Klar kommuner"
  # Skapa variabel summa gånger omsättning
  poster.each do |post|
    if !post[:Summa].nil? && !post[:Omsattning].nil? then
      summa_omsattning = post[:Summa]*post[:Omsattning] 
      poster.where(Id: post[:Id]).update(SummaOmsattning: summa_omsattning)
    end
  end  
  puts "Klar summa gånger omsättning"
  poster.each do |post|
    if !post[:Summa].nil? && !post[:Anstallda].nil? then
      summa_anstallda = post[:Summa]*post[:Anstallda] 
      poster.where(Id: post[:Id]).update(SummaAnstallda: summa_anstallda)
    end
  end  
  puts "Klar summa gånger anställda"
  poster.each do |post|
    if !post[:Lan].nil? && !post[:Kommun].nil? then
      if ((post[:Kommun] == post[:KKommun]) && (post[:Typ] == "Kommun")) || ((post[:Lan] == post[:KKommun]) && (post[:Typ] == "Landsting")) then
        poster.where(Id: post[:Id]).update(LokalFlagga: true)
      else
        poster.where(Id: post[:Id]).update(LokalFlagga: false)
      end  
    end  
  end  
  puts "Klar flagga lokal"
end
  
def skriv_till_csv
  poster = DB[:relationer]
  CSV.open("upphandlingsdata.csv", "wb") do |csv|
    poster.each_with_index do |row, index|
      csv << row.keys if index == 0
      csv << row.values
    end
  end
end

def skapa_tabell
  poster = DB[:relationer]
  kopare = Set[]
  poster.each do |post|
    kopare << [post[:Kop], post[:Kop_namn], post[:Typ]]
  end
  puts "Klar set"
  tabell = DB[:tabell]
  # Data för samtliga branscher
  kopare.each do |koparen|
    item = Inkopare.new(koparen[0])
    tabell.insert(Kop: koparen[0], Kop_namn: koparen[1], Typ: koparen[2], SNI_A: "alla", Inkopsandel: item.inkopsandel("alla"), Snittstorlek: item.snittstorlek("alla"), Snittanstallda: item.snittanstallda("alla"), Lokalandel: item.lokalandel("alla"), Offandel: item.offandel("alla"))
  end  
  # Data för varje SNI-avdelning
  ("A".."U").each do |sni|
    kopare.each do |koparen|
      item = Inkopare.new(koparen[0])
      tabell.insert(Kop: koparen[0], Kop_namn: koparen[1], Typ: koparen[2], SNI_A: sni, Inkopsandel: item.inkopsandel(sni), Snittstorlek: item.snittstorlek(sni), Snittanstallda: item.snittanstallda(sni), Lokalandel: item.lokalandel(sni), Offandel: item.offandel(sni))  
    end
  end  
end  

skapa_databas
skriv_till_csv
skapa_tabell
    

get '/tabell?' do
  session[:kopare] = params['kopare'] if !params['kopare'].nil?
  session[:sni] = params['sni'] if !params['sni'].nil?
  session[:sortera] = params['sortera'] if !params['sortera'].nil?
  erb :tabell
end
  
get '/' do
  erb :index
end



