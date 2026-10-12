set -eu
# A source file its author has not formatted yet: the formatter rewrites it in place.
rm -rf /s/cr && mkdir -p /s/cr/src
cat > /s/cr/src/inventory.cr <<'EOF'
# Inventory of a small shop, kept in memory and dumped as CSV.
class Item
  getter name : String
  getter price : Float64
  property count : Int32
  def initialize(@name,@price,@count)
  end
  def total
  price*count
  end
end

class Inventory
  def initialize
    @items=[] of Item
  end
  def add(name : String,price : Float64,count : Int32=1)
    @items<<Item.new(name,price,count)
  end
  def restock(name,amount)
  item=@items.find{|i|i.name==name}
  raise "no such item: #{name}" unless item
  item.count+=amount
  end
  def value
    @items.sum(&.total)
  end
  def to_csv(io)
  io<<"name,price,count\n"
  @items.each{|i| io<<"#{i.name},#{i.price},#{i.count}\n"}
  end
end

inv=Inventory.new
inv.add("pencil",0.5,100)
inv.add( "notebook" , 2.25 , 40 )
inv.restock("pencil",20)
inv.to_csv(STDOUT)
puts "value: #{inv.value}"
EOF
