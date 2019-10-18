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
  # Skapar bara tables om de inte redan existerar
  DB.create_table? :relationer do
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
    Integer :Lan
    Integer :Kommun
    Integer :Stlk_klass
    Date :Reg_datum
    Integer :Anstallda
    Integer :Omsattning
    Integer :RRes
    Integer :ARes
    Integer :HOms
  end
end

class Inkopare
  attr_reader :inkopsandel, :snittstorlek, :lokalandel, :privatandel
  
  def initialize(orgnr)
    @orgnr = orgnr
  end
  
  private
  
  def inkopsandel # Andel inköp av kommunens totala omsättning
    
  end  
  
  def snittstorlek # Snittstorlek på leverantörer vägt efter kontraktsstorlek
    
  end
  
  def lokalandel # Andel som kommuner köper av lokala leverantörer
    
  end  
  
  def privatandel # Andel privat försäljning bland leverantörer
    
  end
  
end  

poster = DB[:relationer]
rad = 0
CSV.foreach("foretag_ar_2017.csv", :encoding => 'iso-8859-1', headers: true) do |foretag|
  rad += 1
  puts rad, foretag[8].encode(Encoding::UTF_8)
  (1..100).each do |sni|
    filnamn = "SNI" + sni.to_s + ".csv"
    if File.file?(filnamn) then
      CSV.foreach(filnamn, :encoding => 'iso-8859-1', :col_sep => ";", headers: true) do |relation|
        if foretag[0] == relation[0] then
          puts "Relation:", foretag, relation
          relationer.insert(Lev: relation[0].encode(Encoding::UTF_8), Lev_namn: relation[1].encode(Encoding::UTF_8), Kop: relation[2].encode(Encoding::UTF_8), Kop_namn: relation[3].encode(Encoding::UTF_8), Typ: relation[4].encode(Encoding::UTF_8), Summa: relation[9].encode(Encoding::UTF_8), AFakt: relation[10].encode(Encoding::UTF_8), SNI: relation[11].encode(Encoding::UTF_8), SNI_namn: relation[13].encode(Encoding::UTF_8), Lan: foretag[6].encode(Encoding::UTF_8), Kommun: foretag[7].encode(Encoding::UTF_8), Stlk_klass: foretag[10].encode(Encoding::UTF_8), Reg_datum: foretag[16].encode(Encoding::UTF_8), Anstallda: foretag[35].encode(Encoding::UTF_8), Omsattning: foretag[43].encode(Encoding::UTF_8), RRes: foretag[55].encode(Encoding::UTF_8), ARes: foretag[76].encode(Encoding::UTF_8)) 
        end
      end
    end
  end
end



