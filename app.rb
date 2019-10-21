#  ruby app.rb -o $IP -p $PORT 
 
require 'rubygems'
require 'nokogiri'   
require 'open-uri'
require 'sqlite3'
require 'yaml' 
require 'json'
require 'erb' 
require 'csv'
require 'sequel'

$kodnyckel = {'A' => 1..3, 'B' => 5..9, 'C' => 10..33, 'D' => 35..35, 'E' => 36..39, 'F' => 41..43, 'G' => 45..47, 'H' => 49..53, 'I' => 55..56, 'J' => 58..63, 'K' => 64..66, 'L' => 68..68, 'M' => 69..75, 'N' => 77..82, 'O' => 84..84, 'P' => 85..85, 'Q' => 86..88, 'R' => 90..93, 'S' => 94..96, 'T' => 97..98, 'U' => 99..99 }

DB = Sequel.connect('sqlite://foretag.db')
def initiera_databas
  # Skapar table och skriver över om den existerar
  DB.create_table! :relationer do
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
    Integer :Omsattning
    Integer :RRes
    Integer :ARes
    Integer :KOms
    Integer :KKommun # köparens läns/kommunnummer
  end
end

# Helper
class String
  def is_integer?
    self.to_i.to_s == self
  end
end

class Inkopare
  attr_reader :inkopsandel, :snittstorlek, :lokalandel, :privatandel
  
  def initialize(orgnr)
    @orgnr = orgnr
  end
  
  def inkopsandel(sni) # Andel inköp av kommunens totala omsättning
    poster = DB[:relationer]
    if sni == "alla" then
      summa_inkop = poster.where(Kop: @orgnr).sum(:Summa)
      omsattning = poster.where(Kop: @orgnr).avg(:KOms)*1000000
    else
      summa_inkop = poster.where(SNI_A: sni, Kop: @orgnr).sum(:Summa)
      omsattning = poster.where(Kop: @orgnr).avg(:KOms)*1000000
    end
    puts summa_inkop, omsattning
    return 100*summa_inkop/omsattning
  end  
  
  def snittstorlek(sni) # Snittstorlek på leverantörer vägt efter kontraktsstorlek
    
  end
  
  def lokalandel(sni) # Andel som kommuner köper av lokala leverantörer
    
  end  
  
  def privatandel(sni) # Andel privat försäljning bland leverantörer
    
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
    filnamn = "SNI" + sni.to_s + ".csv"
    if File.file?(filnamn) then
      CSV.foreach(filnamn, :encoding => 'iso-8859-1', :col_sep => ";") do |relation|
        relation = rensa(relation)
        if relation[9].is_integer? then
          poster.insert(Lev: relation[0], Lev_namn: relation[1], Kop: relation[2], Kop_namn: relation[3], Typ: relation[4], Summa: relation[9], AFakt: relation[10], SNI: relation[11], SNI_namn: relation[12])
        end
      end
    end
  end
  puts "Klar relationer"
  nummer = 0
  CSV.foreach("foretag_ar_2017.csv", :encoding => 'iso-8859-1') do |foretag|
    foretag = rensa(foretag)
    nummer += 1
    puts nummer if nummer % 10000 == 0
    poster.where(Lev: foretag[0]).update(Lan: foretag[6], Kommun: foretag[7], Stlk_klass: foretag[10], Reg_datum: foretag[16], Anstallda: foretag[35], Omsattning: foretag[43], RRes: foretag[55], ARes: foretag[76])
  end    
  puts "Klar företag"
  $kodnyckel.each do |key, value|
    nedre = value.first * 1000 - 1
    ovre = (value.last + 1) * 1000
    puts $kodnyckel[key]
    poster.where(SNI: nedre..ovre).update(SNI_A: key)
  end  
  puts "Klar avdelning"
  CSV.foreach("kommuner.csv") do |kommun|
    kommun = rensa(kommun)
    poster.where(Kommun: kommun[0][0..3].sub(/^0+/, ""), Typ: "Kommun").update(KOms: -kommun[2].to_i)
  end  
  CSV.foreach("landsting.csv") do |landsting|
    landsting = rensa(landsting)
    poster.where(Lan: landsting[0][0..1].sub(/^0+/, ""), Typ: "Landsting").update(KOms: -landsting[2].to_i)
  end  
  puts "Klar kommuner"
  CSV.foreach("kommunkodorgnr.csv", :encoding => 'iso-8859-1', :col_sep => ";") do |rad|
    rad = rensa(rad)
    puts rad.inspect
    poster.where(Kop: rad[2]).update(KKommun: rad[0].sub(/^0+/, ""))
  end
  puts "Klar kommunkoder => orgnr"
end



#skapa_databas
kommunen = Inkopare.new("2321000016")
kommunen.inkopsandel("alla")

