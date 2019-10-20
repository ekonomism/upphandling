string = "006776"
puts string[0..3].sub!(/^0+/, "")
# ==> 'empty string'