require 'json'
require 'logger'
require 'set'

STDOUT.sync = true

class Object
  def progn
    fail 'no block' unless block_given?
    yield(self)
  end
end

def dungeon_dimensions(data)
  xmax, ymax = (data["walls"] + data["blocks"]).reduce([0,0]) { |(xmax, ymax), (x, y)|
    [ [xmax,x].max, [ymax,y].max ]
  }
  return [xmax+1, ymax+1]
end

def floor_cells data
  fail 'not map data' unless data.has_key? "map"
  non_floor = Set.new(data["walls"] + data["blocks"])

  width, height = dungeon_dimensions(data)
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

VEC_TO_CMD = {
  [0,-1] => 'UP',
  [1,0] => 'RIGHT',
  [0,1] => 'DOWN',
  [-1,0] => 'LEFT'
}

def vec_minus(v, u)
  vec = v.progn do |x1, y1|
    u.progn do |x0, y0|
      [x1 - x0, y1 - y0]
    end
  end
end

def path_distance(floor, player_pos, goal_pos)
  solve_maze(floor, player_pos, goal_pos).size - 1
end

def colinear?(v, u)
  return v[0] == u[0] || v[1] == v[1]
end

def midpoint(v, u)
  return [(v[0] + u[0])/2, (v[1] + u[1])/2]
end

def mdistance(v, u)
  return (v[0] - u[0]).abs + (v[1] - u[1]).abs
end

def enough_hammers?(data)
  map_level = data["player"]["map-level"]
  hammers = data["player"]["hammer"]

  if data["player"]["heal"] <= 2
    return hammers > 0
  end

  if map_level >= 90
    hammers > 0
  elsif map_level >= 80
    hammers > 8
  elsif map_level >= 50
    hammers > 15
  elsif map_level >= 25
    hammers > 10
  # elsif map_level >= 10
  #   hammers > 3
  else
    hammers > 3
  end
end


def player_pos(data)
  return [data["player"]["pos"]["x"],
          data["player"]["pos"]["y"]]
end

def shortcut_path(data, goal_pos)
  return data["blocks"].map { |block|
    data1 = Marshal.restore Marshal.dump data
    data1["blocks"] = data["blocks"] - [block]
    solve_maze(floor_cells(data1), player_pos(data1), goal_pos)
  }.min_by(&:size)
end

def map_mode data
  floor = floor_cells(data)
  player_pos = [data["player"]["pos"]["x"], data["player"]["pos"]["y"]]

  if data["player"]["hp"] < data["player"]["maxhp"]*0.40 && data["player"]["heal"] > 0
    puts "HEAL"
    return
  else
    # 階段へ向かう
    item = (data["items"] + (data["player"]["map-level"] < 25 ? [] : data["kaidan"])).find { |pos|
      colinear?(player_pos, pos) &&
        mdistance(player_pos, pos) == 2 &&
        data["blocks"].include?(midpoint(player_pos, pos))
    }
    if data["player"]["map-level"] == 100
      # もげぞうへ向かう。
      if mdistance(player_pos, data["boss"][0]) == 1 &&              # 隣接していて
         data["player"]["hp"].fdiv(data["player"]["maxhp"]) < 0.8 && # HP が8割未満で
         data["player"]["heal"] >= 2                                 # 回復薬を複数持っていれば
        $logger.debug("ボス戦前に回復！")
        puts "HEAL"                                                  # 回復する。
      else
        path = solve_maze(floor, player_pos, data["boss"][0])
        fail "path length (#{path.size}) < 2" if path.size < 2

        vec = vec_minus(path[1], path[0])
        puts VEC_TO_CMD[vec]
      end
    elsif enough_hammers?(data) && item
      vec = vec_minus(midpoint(player_pos, item), player_pos)
      $logger.debug("壁を壊すぜ")
      puts VEC_TO_CMD[vec]
    else
      items = data["items"].sort_by { |item_pos| path_distance(floor, player_pos, item_pos) }
      if data["player"]["map-level"] <= 10
        near_threshold = Float::INFINITY
      elsif data["player"]["map-level"] <= 50 &&
            data["player"]["buki"].drop(1).inject(:+) <= 18
        near_threshold = Float::INFINITY
      else
        near_threshold = 5
      end
      near_item =  items.find { |item_pos| path_distance(floor, player_pos, item_pos) <= near_threshold }
      if near_item
        goal_pos = near_item
        $logger.debug("アイテムに向かうぜ")
      else
        if false && data['ha2'].any?
          goal_pos = data['ha2'][0]
          $logger.debug("ハツネツに向かうぜ")
        else
          goal_pos = data['kaidan'][0]
          $logger.debug("階段に向かうぜ")
        end
      end
      path = solve_maze(floor, player_pos, goal_pos)
      if goal_pos == data['kaidan'][0] &&
         enough_hammers?(data) && # data['player']['hammer'] > 0 
         (path.size-1) >= mdistance(player_pos, goal_pos) + 7
        # 階段遠いな…
        $logger.debug("近道するか。")
        shortcut = shortcut_path(data, goal_pos)
        if (shortcut.size-1) < (path.size-1)
          path = shortcut
        end
      end
      fail "path length (#{path.size}) < 2" if path.size < 2

      # 移動ベクトルを計算。
      vec = vec_minus(path[1], path[0])

      puts VEC_TO_CMD[vec]
    end
  end
end

MONSTER_PRIORITY = [
  "もげぞう",
  "ハツネツエリア",
  "メタルヨテイチ",
  "ヒドラ",
  "ブリガンド",
  "スライム",
  "オーク",
]

def monster_weight(m)
  pri = MONSTER_PRIORITY.index(m["name"])
  if m["name"] == "もげぞう" || m["name"] == "ハツネツエリア"
    level = 1
  else
    level = m["level"]
  end
  return pri * 5 + level
end

MOGEZOU_ATK = 10
HA2NE2_ATK = 8

def monster_expected_attack(player, monster)
  case monster["name"]
  when "もげぞう"
    if player["agi"] == 0
      ((player["level"] + MOGEZOU_ATK) * 0.5 + 1 + 5) * 0.8
    else
      ((player["level"] + MOGEZOU_ATK) * 0.5 + 1 + 5) * 0.4
    end
  when "ハツネツエリア"
    ((player["level"] + HA2NE2_ATK) * 0.5 + 1 + 3) / 3.0
  when "メタルヨテイチ"
    monster["level"] * 0.5 * 0.5
  when "オーク"
    monster["level"] * 0.5
  when "ヒドラ"
    monster["level"] * 0.5 * 0.5
  when "スライム"
    if player["agi"] > 0
      0.0
    else
      monster["level"] * 0.5
    end
  when "ブリガンド"
    m = [player["hp"], player["agi"], player["str"]].max
    if m == player["hp"]
      monster["level"]
    else
      0.0
    end
  else
    fail "unknown monster #{monster['name'].inspect}"
  end
end

def expected_damage(player, monsters)
  monsters.map { |monster| monster_expected_attack(player, monster) }.inject(0, :+)
end

def battle_mode data
  player = data["player"]
  monsters = data["monsters"]
  monsters_alive = monsters.select { |m| m["hp"] > 0 }

  two_or_more_monsters = proc {
    (monsters_alive.size > 1).tap do |test|
      unless test
        $logger.debug("HP低いけどもうすぐ勝てるから回復しない(キリッ")
      end
    end
  }

  # low_hp_threshold = proc { expected_damage(player, monsters_alive) * 2.0 }
  $logger.debug("期待値 = #{expected_damage(player, monsters)}")
  if false
  elsif player["map-level"] == 100 && # 100階。ボス戦かもなので残り1体での回復省略はしない。
        player["heal"] > 0 &&
        player["hp"] < [player["maxhp"], 37].min
    puts "HEAL"
  elsif player["map-level"] >= 50 && # 50階〜99階
        player["heal"] > 8 &&
        player["hp"] < [player["maxhp"], 37].min
        two_or_more_monsters.()
    puts "HEAL"
  elsif player["heal"] > 0 &&
        ((player["hp"] < player["maxhp"] * 0.40) ||
         (player["agi"] == 0 && player["hp"] < player["maxhp"])) && # 素早さがない
        two_or_more_monsters.()
    puts "HEAL"
  else
    if monsters_alive.all? { |m| m["hp"] <= 2 }
      $logger.debug("HPの低い敵ばかりなのでなぎはらい")
      puts "SWING"
    elsif monsters_alive.size == 1 && monsters_alive[0]["name"] == "メタルヨテイチ"
      $logger.debug("メタルヨテイチになぎはらい!")
      puts "SWING"
    else
      most_dangerous = monsters_alive.max_by { |m|
        monster_weight(m)
      }
      if most_dangerous["hp"] <= 4 && monsters_alive.size >= 2
        a, b = monsters_alive.sort_by { |m|
          monster_weight(m)
        }.reverse.first(2)
        $logger.debug("ダブルスウィング！")
        puts "DOUBLE #{a['number']} #{b['number']}"
      else
        puts "STAB #{most_dangerous['number']}"
      end
    end
  end
end

def weapon_grade(w)
  w["str"] + w["hp"] + w["agi"]
end

def equip_mode data
  if weapon_grade(data["discover"]) > weapon_grade(data["now"])
    puts "YES"
  else
    puts "NO"
  end
end

def levelup_mode data
  player = data["player"]
  index = [player["maxstr"], player["maxagi"], player["maxhp"]].zip(0..2).min_by(&:first)[1]
  puts ["STR", "AGI", "HP"][index]
  return
end

def adjacents(coords)
  x, y = coords
  return [[x,y-1], [x+1,y], [x,y+1], [x-1,y]]
end

def reconstruct_path(prev, goal)
  path = []
  curr = goal
  while prev[curr]
    path << curr
    curr = prev[curr]
  end
  path << curr
  return path.reverse
end

def solve_maze(floor, start, goal)
  #p [:start, start, :goal, goal]
  maze = Set.new(floor)
  queue = [start]
  visited = Set.new
  prev = {}

  until queue.empty?
    current = queue.shift
    visited << current
    if current == goal
      return reconstruct_path(prev, goal)
    else
      candidates =  adjacents(current).reject { |pt| !maze.include?(pt) || visited.include?(pt) }
      candidates.each do |candidate|
        prev[candidate] = current
      end
      queue.concat candidates
    end
  end

  return nil
end

def render_grid(cells: [], width: nil, height: nil, on_char: '*', off_char: '.')
  fail ArgumentError, "width, height required" unless width || height
  (0...height).map do |y|
    (0...width).map do |x|
      if cells.include?([x,y])
        on_char
      else
        off_char
      end
    end
  end
end

def main
  srand(0)

  log_file = File.open("log", "w")
  input_file = File.open("input", "w")
  log_file.sync = true
  $logger = Logger.new(log_file)
  $logger.info "起動しました。"
  at_exit do
    $logger.info "終了します。"
    log_file.close
    input_file.close
  end

  call_table = {
    "map" => method(:map_mode),
    "battle" => method(:battle_mode),
    "equip" => method(:equip_mode),
    "levelup" => method(:levelup_mode)
  }

  puts "予定地ＡＩ"

  while line = gets
    input_file.write line
    json_data = JSON.parse(line)
    $logger.debug("Got: #{line.chomp}")
    processed = call_table.any? do |key, fn|
      if json_data.has_key?(key)
        fn.call(json_data)
        true
      else
        false
      end
    end
    unless processed
      fail "no fn for #{json_data.inspect}"
    end
  end
  $logger.error("標準入力 EOF")
rescue => e
  $logger.error(e.inspect)
  if e.backtrace
    $logger.error(e.backtrace.join("\n"))
  end
  raise # re-raise
end

if __FILE__ == $0
  main
end
