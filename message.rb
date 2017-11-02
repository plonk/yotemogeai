require 'set'

class Message
  attr_reader :data

  def initialize(data)
    @data = Marshal.restore Marshal.dump(data)
  end

  def type
    return ['map', 'battle', 'equip', 'levelup'].find { |t| @data.has_key? t }.to_sym
  end

  # [x, y]
  def player_pos
    return [@data['player']['pos']['x'], @data['player']['pos']['y']]
  end

  def kaidan
    return @data['kaidan'][0]
  end

  def method_missing(name, *args)
    fail 'what?' unless args.empty?

    if @data.has_key?(name.to_s)
      @data[name.to_s]
    else
      fail "data has no such key (#{name})"
    end
  end

  def dungeon_dimensions
    xmax, ymax = (data["walls"] + data["blocks"]).reduce([0,0]) { |(xmax, ymax), (x, y)|
      [ [xmax,x].max, [ymax,y].max ]
    }
    return [xmax+1, ymax+1]
  end

  def floor_cells
    fail 'not map @data' unless @data.has_key? "map"
    non_floor = Set.new(@data["walls"] + @data["blocks"])

    width, height = dungeon_dimensions()
    floor = []
    (0...width).each do |x|
      (0...height).each do |y|
        pt = [x, y]
        unless non_floor.include? pt
          floor << pt
        end
      end
    end
    return floor
  end
end
