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
$ar = [2014, 2015, 2016, 2017]

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
    Integer :Ar
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
    Bignum :SummaOmsattning # Summa gånger omsättning
    Bignum :SummaAnstallda # Summa gånger anställda
    Bignum :SummaOmsLev # Summan av omsättningen för leverantörerna till köparen
    Bignum :RresOmsSumma # Årets resultat dividerat med omsättning gånger Summa
    Bignum :AresOmsSumma # Rörelseresultat dividerat med omsättningen gånger Summa
    Boolean :LokalFlagga # Flagga som är true om lokal
  end
  DB.create_table! :tabell do
    primary_key :Id
    Integer :Ar
    String :Kop
    String :Kop_namn
    String :Typ
    String :SNI_A
    Float :Inkopsandel
    Float :Snittstorlek
    Float :Snittanstallda
    Float :Lokalandel
    Float :Offandel
    Float :RRes
    Float :ARes
  end
  DB.alter_table :tabell do
    add_index [:SNI_A, :Typ]
  end
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
      @typ = poster.select(:Typ).where(Kop: kop).first[:Typ]
      @kommun = poster.select(:Kommun).where(Kop: kop).exclude(Kommun: nil).first[:Kommun]
      @lan = poster.select(:Lan).where(Kop: kop).exclude(Lan: nil).first[:Lan]
    rescue StandardError => e
      puts e
      @kop = nil
      @typ = nil
      @kommun = nil
      @lan = nil
    end  
  end
  # Andel inköp av kommunens totala omsättning
  def inkopsandel(ar, sni) 
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        summa_inkop = poster.where(Ar: ar, Kop: @kop).exclude(Summa: nil).sum(:Summa)
        omsattning = poster.where(Ar: ar, Kop: @kop).exclude(KOms: nil).avg(:KOms)
      else
        summa_inkop = poster.where(Ar: ar, SNI_A: sni, Kop: @kop).exclude(Summa: nil).sum(:Summa)
        omsattning = poster.where(Ar: ar, Kop: @kop).exclude(KOms: nil).avg(:KOms)
      end
      inkopsandel = 100*summa_inkop.to_f/omsattning
      inkopsandel = nil if inkopsandel.nan?
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
        summa_omsattning = poster.where(Ar: ar, Kop: @kop).exclude(SummaOmsattning: nil).sum(:SummaOmsattning)
        summa = poster.where(Ar: ar, Kop: @kop).exclude(SummaOmsattning: nil).sum(:Summa)
      else
        summa_omsattning = poster.where(Ar: ar, SNI_A: sni, Kop: @kop).exclude(SummaOmsattning: nil).sum(:SummaOmsattning)
        summa = poster.where(Ar: ar, SNI_A: sni, Kop: @kop).exclude(SummaOmsattning: nil).sum(:Summa)
      end
      snittstorlek = summa_omsattning.to_f/summa
      snittstorlek = nil if snittstorlek.nan?
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
        summa_anstallda = poster.where(Ar: ar, Kop: @kop).exclude(SummaAnstallda: nil).sum(:SummaAnstallda)
        summa = poster.where(Ar: ar, Kop: @kop).exclude(SummaAnstallda: nil).sum(:Summa)
      else
        summa_anstallda = poster.where(Ar: ar, SNI_A: sni, Kop: @kop).exclude(SummaAnstallda: nil).sum(:SummaAnstallda)
        summa = poster.where(Ar: ar, SNI_A: sni, Kop: @kop).exclude(SummaAnstallda: nil).sum(:Summa)
      end
      snittanstallda = summa_anstallda.to_f/summa
      snittanstallda = nil if snittanstallda.nan?
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
        summa_inkop_lokal = poster.where(Ar: ar, Kop: @kop, LokalFlagga: true).exclude(LokalFlagga: nil).sum(:Summa)
        summa_inkop_ejlokal = poster.where(Ar: ar, Kop: @kop, LokalFlagga: false).exclude(LokalFlagga: nil).sum(:Summa)
      else
        summa_inkop_lokal = poster.where(Ar: ar, SNI_A: sni, Kop: @kop, LokalFlagga: true).exclude(LokalFlagga: nil).sum(:Summa)
        summa_inkop_ejlokal = poster.where(Ar: ar, SNI_A: sni, Kop: @kop, LokalFlagga: false).exclude(LokalFlagga: nil).sum(:Summa)
      end
      lokalandel = 100*summa_inkop_lokal.to_f/(summa_inkop_lokal + summa_inkop_ejlokal)
      lokalandel = nil if lokalandel.nan?
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
        summa_inkop = poster.where(Ar: ar, Kop: @kop).exclude(Omsattning: nil).sum(:Summa)
        summa_oms_lev = poster.where(Ar: ar, Kop: @kop).exclude(Omsattning: nil).avg(:Summa)
      else
        summa_inkop = poster.where(Ar: ar, Kop: @kop, SNI_A: sni).exclude(Omsattning: nil).sum(:Summa)
        summa_oms_lev = poster.where(Ar: ar, Kop: @kop, SNI_A: sni).exclude(Omsattning: nil).avg(:Summa)
      end
      offandel = 100*summa_inkop.to_f/summa_oms_lev
      offandel = nil if offandel.nan?
    rescue StandardError => e
      offandel = nil
    end
    return offandel
  end
  # Årets resultat i genomsnitt för företag som säljer till köparen
  def r_res(ar, sni)
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        rres_oms_summa = poster.where(Ar: ar, Kop: @kop).exclude(Omsattning: nil).sum(:RresOmsSumma)
        summa_oms_lev = poster.where(Ar: ar, Kop: @kop).exclude(Omsattning: nil).sum(:Summa)
      else
        rres_oms_summa = poster.where(Ar: ar, Kop: @kop, SNI_A: sni).exclude(Omsattning: nil).sum(:RresOmsSumma)
        summa_oms_lev = poster.where(Ar: ar, Kop: @kop, SNI_A: sni).exclude(Omsattning: nil).sum(:Summa)
      end
      r_res = 100*rres_oms_summa.to_f/summa_oms_lev
      r_res = nil if r_res.nan?
    rescue StandardError => e
      r_res = nil
    end
    return r_res
  end
  # Rörelseresultat i genomsnitt för företag som säljer till köparen 
  def a_res(ar, sni)
    poster = DB[:relationer]
    begin
      if sni == "alla" then
        ares_oms_summa = poster.where(Ar: ar, Kop: @kop).exclude(Omsattning: nil).sum(:AresOmsSumma)
        summa_oms_lev = poster.where(Ar: ar, Kop: @kop).exclude(Omsattning: nil).sum(:Summa)
      else
        ares_oms_summa = poster.where(Ar: ar, Kop: @kop, SNI_A: sni).exclude(Omsattning: nil).sum(:AresOmsSumma)
        summa_oms_lev = poster.where(Ar: ar, Kop: @kop, SNI_A: sni).exclude(Omsattning: nil).sum(:Summa)
      end
      a_res = 100*ares_oms_summa.to_f/summa_oms_lev
      a_res = nil if a_res.nan?
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
  (1..100).each do |sni|
    puts sni
    filnamn = "sni/SNI" + sni.to_s + ".csv"
    if File.file?(filnamn) then
      CSV.foreach(filnamn, :encoding => 'iso-8859-1', :col_sep => ";") do |relation|
        relation = rensa(relation)
        $ar.each do |ar|
          if relation[21].is_integer? && ar == 2014 then
            poster.insert(Ar: ar, Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[21].split(",")[0].to_i, AFakt: relation[22], SNI: relation[23], SNI_namn: relation[24])
          end
          if relation[17].is_integer? && ar == 2015 then
            poster.insert(Ar: ar, Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[17].split(",")[0].to_i, AFakt: relation[18], SNI: relation[19], SNI_namn: relation[20])
          end
          if relation[13].is_integer? && ar == 2016 then
            poster.insert(Ar: ar, Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[13].split(",")[0].to_i, AFakt: relation[14], SNI: relation[15], SNI_namn: relation[16])
          end
          if relation[9].is_integer? && ar == 2017 then
            poster.insert(Ar: ar, Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[9].split(",")[0].to_i, AFakt: relation[10], SNI: relation[11], SNI_namn: relation[12])
          end
          if relation[5].is_integer? && ar == 2018 then
            poster.insert(Ar: ar, Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[5].split(",")[0].to_i, AFakt: relation[6], SNI: relation[7], SNI_namn: relation[8])
          end
        end
      end
    else
      puts "Ingen fil för SNI:", sni
    end
  end
  udda_sni = [461, 462, 463, 464, 465, 466, 467, 468, 469, 4641, 4642, 4643, 4644, 4645, 4646, 4647, 4648, 4649, 471, 472, 473, 474, 475, 476, 477, 478, 479]  
  udda_sni.each do |sni|
    puts sni
    filnamn = "sni/SNI" + sni.to_s + ".csv"
    if File.file?(filnamn) then
      CSV.foreach(filnamn, :encoding => 'iso-8859-1', :col_sep => ";") do |relation|
        relation = rensa(relation)
        $ar.each do |ar|
          if relation[9].is_integer? && ar == 2014 then
            poster.insert(Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[21].split(",")[0].to_i, AFakt: relation[22], SNI: relation[23], SNI_namn: relation[24])
          elsif relation[9].is_integer? && ar == 2015 then
            poster.insert(Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[17].split(",")[0].to_i, AFakt: relation[18], SNI: relation[19], SNI_namn: relation[20])
          elsif relation[9].is_integer? && ar == 2016 then
            poster.insert(Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[13].split(",")[0].to_i, AFakt: relation[14], SNI: relation[15], SNI_namn: relation[16])
          elsif relation[9].is_integer? && ar == 2017 then
            poster.insert(Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[9].split(",")[0].to_i, AFakt: relation[10], SNI: relation[11], SNI_namn: relation[12])
          elsif relation[9].is_integer? && ar == 2018 then
            poster.insert(Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[5].split(",")[0].to_i, AFakt: relation[6], SNI: relation[7], SNI_namn: relation[8])
          end
        end
      end
    else
      puts "Ingen fil för SNI:", sni
    end
  end
  DB.alter_table :relationer do
    add_index [:Lev, :Ar]
  end
  puts "Klar relationer"
end
          
def addera_foretag     
  poster = DB[:relationer]
  nummer = 0
  $ar.each do |ar|
    filnamn = "foretag_ar_" + ar.to_s + ".csv"
    CSV.foreach(filnamn, :encoding => 'iso-8859-1') do |foretag|
      foretag = rensa(foretag)
      nummer += 1
      puts nummer if nummer % 10000 == 0
      poster.where(Ar: ar, Lev: foretag[0]).update(Lan: foretag[6], Kommun: foretag[7], Stlk_klass: foretag[10], Reg_datum: foretag[16], Anstallda: foretag[35], Omsattning: foretag[43].to_i*1000, RRes: foretag[55].to_i*1000, ARes: foretag[76].to_i*1000)
    end   
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
    poster.where(Kop: rad[2]).update(Kop_namn: rad[1])
  end
  puts "Klar kommunkoder => orgnr"
   
  CSV.foreach("kommuner.csv", :col_sep => ";") do |kommun|
    kommun = rensa(kommun)
    $ar.each do |ar|
      poster.where(KKommun: kommun[0][0..3].sub(/^0+/, ""), Typ: "Kommun").update(KOms: kommun[ar-2010].to_i*1000)
    end
  end  
  CSV.foreach("landsting.csv", :col_sep => ";") do |landsting|
    landsting = rensa(landsting)
    $ar.each do |ar|
      poster.where(KKommun: landsting[0][0..1].sub(/^0+/, ""), Typ: "Landsting").update(KOms: landsting[ar-2010].to_i*1000000)
    end
  end  
  puts "Klar kommuner"
  
  # Skapa variabel med summan av omsättningen för leverantörer till köpare
  poster.each do |post|
    saljare = poster.select(:Lev).where(Id: post[:Id]).all.map{|x| x.values }.flatten.uniq
    # Summera omsättning över säljare
    summa_omsattning = 0
    saljare.each do |saljaren|
      omsattning = poster.where(Ar: post[:Ar], Lev: saljaren).exclude(Omsattning: nil).avg(:Omsattning)
      summa_omsattning += omsattning if !omsattning.nil?
    end
    poster.where(Id: post[:Id]).update(SummaOmsLev: summa_omsattning)
  end
  puts "Klar SummaOmsLev"
  
  # Skapa variabel summa gånger omsättning, anställda och flagga lokal
  poster.each do |post|
    if !post[:Summa].nil? && !post[:Omsattning].nil? then
      summa_omsattning = post[:Summa]*post[:Omsattning] 
      poster.where(Id: post[:Id]).update(SummaOmsattning: summa_omsattning)
    end
  end  
  puts "Klar Summa gånger Omsättning"
  poster.each do |post|
    if !post[:Summa].nil? && !post[:Anstallda].nil? then
      summa_anstallda = post[:Summa]*post[:Anstallda] 
      poster.where(Id: post[:Id]).update(SummaAnstallda: summa_anstallda)
    end
  end  
  puts "Klar Summa gånger Anställda"
  poster.each do |post|
    if !post[:Lan].nil? && !post[:Kommun].nil? then
      if ((post[:Kommun] == post[:KKommun]) && (post[:Typ] == "Kommun")) || ((post[:Lan] == post[:KKommun]) && (post[:Typ] == "Landsting")) then
        poster.where(Id: post[:Id]).update(LokalFlagga: true)
      else
        poster.where(Id: post[:Id]).update(LokalFlagga: false)
      end  
    end  
  end  
  puts "Klar flagga Lokal"
  
  # Skapa variabler r_res dividerat med omsättning gånger Summa och a_res dividerat med omsättning gånger Summa
  poster.each do |post|
    if !post[:Summa].nil? && !post[:Omsattning].nil? && !post[:RRes].nil? && !post[:Omsattning] == 0 then
      rres_oms_summa = post[:Summa]*post[:RRes]/post[:Omsattning] 
      poster.where(Id: post[:Id]).update(RresOmsSumma: rres_oms_summa)
    end
  end  
  poster.each do |post|
    if !post[:Summa].nil? && !post[:Omsattning].nil? && !post[:ARes].nil? && !post[:Omsattning] == 0 then
      ares_oms_summa = post[:Summa]*post[:ARes]/post[:Omsattning] 
      poster.where(Id: post[:Id]).update(AresOmsSumma: ares_oms_summa)
    end
  end  
  puts "Klar rres_oms_summa och ares_oms_summa"
end

def skapa_tabell
  poster = DB[:relationer]
  kopare = Hash.new
  poster.each do |post|
    kopare[post[:Kop]] = [post[:Kop_namn], post[:Typ]]
  end
  tabell = DB[:tabell]
  # Data för samtliga branscher
  kopare.each do |key, value|
    item = Inkopare.new(key)
    $ar.each do |ar|
      tabell.insert(Ar: ar, Kop: key, Kop_namn: value[0], SNI_A: "alla", Typ: value[1], Inkopsandel: item.inkopsandel(ar, "alla"), Snittstorlek: item.snittstorlek(ar, "alla"), Snittanstallda: item.snittanstallda(ar, "alla"), Lokalandel: item.lokalandel(ar, "alla"), Offandel: item.offandel(ar, "alla"), RRes: item.r_res(ar, "alla"), ARes: item.a_res(ar, "alla"))
    end  
  end   
  ("A".."U").each do |sni|
    puts "Avdelning: ", sni
    kopare.each do |key, value|
      item = Inkopare.new(key)
      $ar.each do |ar|
        tabell.insert(Ar: ar, Kop: key, Kop_namn: value[0], SNI_A: sni, Typ: value[1], Inkopsandel: item.inkopsandel(ar, sni), Snittstorlek: item.snittstorlek(ar, sni), Snittanstallda: item.snittanstallda(ar, sni), Lokalandel: item.lokalandel(ar, sni), Offandel: item.offandel(ar, sni), RRes: item.r_res(ar, sni), ARes: item.a_res(ar, sni))
      end 
    end   
  end
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

def skriv_tabell_till_csv
  poster = DB[:tabell]
  CSV.open("public/tabell.csv", "wb") do |csv|
    poster.each_with_index do |row, index|
      csv << row.keys if index == 0
      csv << row.values
    end
  end
end
    
skapa_databas
addera_foretag
skriv_till_csv
skapa_tabell
inkop = Inkopare.new("2321000016")
puts inkop.offandel(2014, "A")
  
# Kolla om inloggad    
before do
  @user = session[:inloggad]
end

get "/auth" do
  erb :signin
end
      
post "/login" do
  if params[:password] == "password" then
    session[:inloggad] = true
    redirect "/"
  else
    @fel = true
    redirect "/auth"
  end  
end
       
get "/logout" do
  session[:inloggad] = false
end
    
get '/diagram?', :auth => :true do
  session[:diagram] = params['diagram'] if !params['diagram'].nil?
  session[:diagram] = params['rad'] if !params['rad'].nil?
  if session[:sni] == "alla" then
    tabell = DB[:tabell]
  else
    tabell = DB[:tabell].where(SNI_A: session[:sni])
  end
  @diagram = Hash.new
  $ar.each do |ar|
    if session[:diagram] == 'inkopsandel' then
      varde[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Kop: session[:rad]).avg(:Inkopsandel)
      snitt[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Typ: session[:kopare]).avg(:Inkopsandel)
    elsif session[:diagram] == 'snittstorlek' then
      varde[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Kop: session[:rad]).avg(:Snittstorlek)
      snitt[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Typ: session[:kopare]).avg(:Snittstorlek)
    elsif session[:diagram] == 'snittanstallda' then
      varde[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Kop: session[:rad]).avg(:Snittanstallda)
      snitt[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Typ: session[:kopare]).avg(:Snittanstallda)
    elsif session[:diagram] == 'lokalandel' then
      varde[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Kop: session[:rad]).avg(:Lokalandel)
      snitt[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Typ: session[:kopare]).avg(:Lokalandel)
    elsif session[:diagram] == 'offandel' then
      varde[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Kop: session[:rad]).avg(:Offandel)
      snitt[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Typ: session[:kopare]).avg(:Offandel)
    elsif session[:diagram] == 'r_res' then
      varde[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Kop: session[:rad]).avg(:RRes)
      snitt[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Typ: session[:kopare]).avg(:RRes)
    elsif session[:diagram] == 'a_res' then
      varde[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Kop: session[:rad]).avg(:ARes)
      snitt[ar] = tabell.where(Ar: ar, SNI_A: session[:sni], Typ: session[:kopare]).avg(:ARes)
    elsif
      varde[ar] = ''
      snitt[ar] = ''
    end
  end
end
    
get '/tabell?', :auth => :true do
  session[:ar] = params['ar'] if !params['ar'].nil?
  session[:kopare] = params['kopare'] if !params['kopare'].nil?
  session[:sni] = params['sni'] if !params['sni'].nil?
  session[:sortera] = params['sortera'] if !params['sortera'].nil?
  if session[:sni] == "alla" then
    tabell = DB[:tabell]
  else
    tabell = DB[:tabell].where(SNI_A: session[:sni])
  end
  if session[:sortera] == 'kop_namn' then
    tabell = tabell.order(:Kop_namn)
  elsif session[:sortera] == 'inkopsandel'
    tabell = tabell.reverse(:Inkopsandel)
  elsif session[:sortera] == 'snittstorlek'
    tabell = tabell.reverse(:Snittstorlek)
  elsif session[:sortera] == 'snittanstallda'
    tabell = tabell.reverse(:Snittanstallda)
  elsif session[:sortera] == 'lokalandel'
    tabell = tabell.reverse(:Lokalandel)
  elsif session[:sortera] == 'offandel'
    tabell = tabell.reverse(:Offandel)
  elsif session[:sortera] == 'r_res'
    tabell = tabell.reverse(:RRes)
  elsif session[:sortera] == 'a_res'
    tabell = tabell.reverse(:ARes)
  end
  typ = "Kommun" if session[:kopare] == 'kommun'
  typ = "Landsting" if session[:kopare] == 'lan'
  typ = "Statlig enhet" if session[:kopare] == 'myndighet'
  @tabell_h = tabell.where(Ar: session[:ar], Typ: typ, SNI_A: session[:sni]).all
  erb :tabell
end
  
get '/', :auth => :true do
  erb :index
end



