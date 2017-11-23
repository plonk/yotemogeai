              # モンスターの生成と挙動は分離したい。
module OrcBattle
  EXP = { ha2ne2: 99, orc: 2, slime_mold: 3, hydra: 4, brigand: 5, yote1: 100 }

  module_function

  # def update(arr, designator, rhs)
  #   return arr.dup.tap do |copy|
  #     copy[designator] = rhs
  #   end
  # end

  def update(coll, designator, value = nil)
    copy = coll.dup
    if block_given?
      copy[designator] = yield(coll[designator])
    else
      copy[designator] = value
    end
    return copy
  end

  # (モンスター, ダメージ) → モンスター
  def monster_hit(monster, damage)
    case monster[:type]
    when :yote1
      return update(monster, :health, &:pred)
    else
      return update(monster, :health) { |h| h - damage }
    end
  end

  # モンスター|プレーヤー → 真偽値
  def dead?(thing)
    health = thing[:health]
    if health
      return health <= 0
    else
      return thing[:hp] <= 0
    end
  end

  def number_of_monsters(player_level: , monster_num: )
    return randval(monster_num + player_level.div(4))
  end

  # {モンスターの数, モンスターレベル基礎値} → [モンスター]
  def init_monsters(n: , monster_level:)
    return n.times.map {
      case rand(101)
      when  0..25 then make_orc(monster_level)
      when 26..50 then make_hydra(monster_level)
      when 51..75 then make_slime_mold(monster_level)
      when 76..99 then make_brigand(monster_level)
      else make_yote1(monster_level)
      end
    }.map.with_index { |m, i| m.merge(number: i) }
  end

  # n <= 0 の場合は 1 を返す。さもなくば [1, n] の範囲の整数を返す。
  def randval(n)
    return rand([1, n].max) + 1
  end

  def make_monster(type, monster_level)
    { type: type, health: randval(10 + monster_level) }
  end
  def make_orc(monster_level)
    make_monster(:orc, monster_level)
      .merge(club_level: randval(8 + monster_level))
  end
  def make_hydra(monster_level)
    make_monster(:hydra, monster_level)
  end
  def make_slime_mold(monster_level)
    make_monster(:slime_mold, monster_level)
      .merge(sliminess: randval(5 + monster_level))
  end
  def make_brigand(monster_level)
    make_monster(:brigand, monster_level)
      .merge(atk: 2 + rand(monster_level))
  end
  def make_yote1(monster_level)
    make_monster(:yote1, monster_level)
      .merge(atk: randval(10 + monster_level))
  end

  def make_player
    { hp: 30, maxhp: 30,
      agi: 30, maxagi: 30,
      str: 30, maxstr: 30,
      heal: 2,
      level: 1,
      exp: 0 }
  end

  def random_live_monster(monsters)
    return monsters.reject(&method(:dead?)).sample
  end

  # プレーヤー → プレーヤー
  def use_heal(player)
    if player[:heal] > 0
      return player.merge(hp: player[:maxhp],
                          agi: player[:maxagi],
                          str: player[:maxstr],
                          heal: player[:heal] - 1)
    else
      return player
    end
  end

  def player_attack(player, monsters, action)
    case action[:type]
    when :heal
      return use_heal(player), monsters
    when :swing
      randval(player[:str].div(3)).times do
        break if monsters.all?(&method(:dead?))
        monster = random_live_monster(monsters)
        monster1 = monster_hit(monster, 1)
        monsters = update(monsters, monster[:number], monster1)
      end
      return player, monsters
    when :stab
      return player,
             update(monsters, action[:target],
                    monster_hit(monsters[action[:target]], 2 + randval(player[:str].div(2))))
    when :double
      damage = randval(player[:str].div(6))
      monsters = update(monsters, action[:first],
                        monster_hit(monsters[action[:first]], damage))
      unless monsters.all?(&method(:dead?))
        if dead?(monsters[action[:second]])
          target2 = random_live_monster(monsters)
        else
          target2 = monsters[action[:second]]
        end
        monsters = update(monsters, target2[:number],
                          monster_hit(target2, damage))
      end
      return player, monsters
    end
  end

  def legal_moves(player, monsters)
    live_monsters = monsters.reject(&method(:dead?))
    fail ArgumentError, 'no live monsters' if live_monsters.empty?

    # first == second は stab のほうが効果的か、first を一撃目で倒した場合は
    # first != second の手の1つに等しいはずなので、考慮の必要がないはず。
    # first と second が逆転した手は、考慮の必要がないはず。
    doubles = live_monsters.flat_map { |m1|
      live_monsters.flat_map { |m2|
        if m1[:number] >= m2[:number]
          []
        else
          [{type: :double, first: m1[:number], second: m2[:number]}]
        end
      }
    }
    return [
      *(player[:heal] > 0 ? [{type: :heal}] : []),
      {type: :swing},
      *live_monsters.map { |m| {type: :stab, target: m[:number]} },
      *doubles
    ]
  end

  def pick_random_action(player, monsters)
    return legal_moves(player, monsters).sample
  end

  # (モンスター, プレーヤー) → (モンスター, プレーヤー)
  def monster_attack(monster, player)
    fail ArgumentError, 'player' unless player
    fail ArgumentError, 'monster' unless monster
    case monster[:type]
    when :yote1
      atk = randval(monster[:atk])
      case rand(2)
      when 0
        return monster, player
      when 1
        return monster, update(player, :hp) { |hp| hp - atk }
      end
    when :orc
      return monster,
             update(player, :hp) { |hp| hp - randval(monster[:club_level]) }
    when :hydra
      x = randval(monster[:health].div(2))
      return update(monster, :health, &:succ),
             update(player, :hp) { |hp| hp - x }
    when :slime_mold
      x = randval(monster[:sliminess])
      if player[:agi] > 0
        return monster,
               update(player, :agi) { |agi| [0, agi - x].max }
      else
        return monster,
               update(player, :hp) { |hp| hp - x }
      end
    when :brigand
      target = [:hp, :agi, :str].max_by { |s| player[s] }
      return monster,
             update(player, target) { |val| val - monster[:atk] }
    else
      fail monster[:type].inspect
    end
  end

  def evaluation(player, monsters)
    if dead?(player)
      return -1.0
    else
      if $DEBUG
        fail unless monsters.all?(&method(:dead?))
      end
      return (player[:hp] +
              player[:heal]*(player[:maxhp] + player[:maxagi] + player[:maxstr]) +
              player[:str]*0.5 +
              player[:agi]*0.5).to_f
    end
  end

  def number_of_attacks(player)
    # (agi/15)+1 回、こちらのターンで攻撃できる。
    1 + [player[:agi], 0].max.div(15)
  end

  # {player: プレーヤー, monsters: モンスターの配列} → :win | :lose
  def do_battle(player, monsters, k)
    $logger&.debug(player)
    $logger&.debug(monsters)
    if $DEBUG
      if dead?(player)
        fail ArgumentError, 'player is dead'
      end
      if monsters.all?(&method(:dead?))
        fail ArgumentError, 'monsters are dead'
      end
    end

    k.times do
      action = pick_random_action(player, monsters)
      player, monsters = player_attack(player, monsters, action)
      if monsters.all?(&method(:dead?))
        return evaluation(player, monsters)
      end
    end

    monsters = monsters.map do |m|
      if dead?(m)
        m
      else
        m1, player = monster_attack(m, player)
        m1
      end
    end

    if dead?(player)
      return evaluation(player, monsters)
    else
      return do_battle(player, monsters, number_of_attacks(player))
    end
  end

  def print_monsters(monsters)
    monsters.each do |m|
      puts "#{m[:type]} Lv#{monster_level(m)}"
    end
  end

  def monster_level(monster)
    case monster[:type]
    when :orc
      monster[:club_level]
    when :hydra
      monster[:health]
    when :slime_mold
      monster[:sliminess]
    when :brigand, :yote1
      monster[:atk]
    end
  end
end

if __FILE__ == $0
  include OrcBattle
  require 'pp'
  pp make_orc(5)
  pp init_monsters(n: 8, monster_level: 5)

  fail unless dead?(make_player()) == false
  fail unless dead?(make_player().merge(hp: 0)) == true

  player = make_player #.merge(str: 100, maxstr: 100)
  monsters = init_monsters(n: 4, monster_level: 1)
  print_monsters(monsters)
  result = 100.times.map { do_battle(player, monsters) }
  puts "#{result.count(:win)}/#{result.size}"
end
