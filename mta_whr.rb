require 'set'
require 'whole_history_rating'
require 'fileutils'

# TODO: Not a fan of require_relative since it can be hard to trace the path.
require_relative 'client/smashgg_client'
require_relative 'client/challonge_client'
require_relative 'csv_reader'
require_relative 'csv_writer'

# Some players have multiple accounts. In this case, combine them.
PLAYER_ID_MAP = {
    # Challonge to smash.gg
    "C105677281" => "S1259099", # LukeFlow
    "C105669947" => "S1259790", # NatRop2
    "C105656521" => "S1151677", # krispy.jin
    "C105964270" => "S1039897", # Pito
    "C105962886" => "S804769",  # PkKirby
    "C105960969" => "S875683",  # mtadavid
    "C105806128" => "S1011138", # Vee
    "C105963851" => "S981358",  # Nintendart
    "C105638687" => "S875600",  # Angie
    "C105635165" => "S804800",  # Hooky
    "C105952954" => "S812825",  # PieHat
    "C107324989" => "S812825",  # PieHat
    "C105637494" => "S802340",  # Schwell
    "C105781624" => "S898077",  # IT!Darki
    "C105759168" => "S296273",  # DevilWolf
    "C105702926" => "S1152788", # Macman
    "C105635893" => "S877501",  # lilbigestjake
    "C105760412" => "S830764",  # crispy jr
    "C107063457" => "S1466323", # lxpu
    "C107064251" => "S494940",  # Ghostgodzilla
    "C107063608" => "S1499888", # Danguitos
    "C105635170" => "S1584255", # Breazzy

    # smash.gg duplicates
    "S419570" => "S1030534",  # Pelupelu
    "S1112712" => "S733592",  # ibuprofen
    "S880718" => "S1085661",  # Statsdotzip
    "S963723" => "S1252257",  # Xeno
    "S1256064" => "S1153395", # Benny Burrito
    "S877308" => "S1245341",  # OmeGa 0oF
}

# TODO: Store results locally so we don't need to refetch everything.
#       Should be done since the first call to smash.gg's API returns incomplete results.
SMASHGG_EVENT_IDS = [

    # Season 1: HEEHEE~
    218231, # PKHat's Weejapahlooza
    225693, # PKHat's Warmupahlooza!
    209015, # Aces Championship Series: Qualifier 1
    231973, # PKHat's Birdopalooza
    237695, # PKHat's JesusChompahlooza!
    213935, # Aces Championship Series: Qualifier 2
    246018, # PKHat's DaisyPeluza
    249405, # Drops 'n Lobs 2
    213937, # Aces Championship Series: Qualifier 3
    248397, # Double Bagel Fridays 1
    258092, # PKHat's Comebackpahlooza!
    213942, # Aces Championship Series: Qualifier 4
    258067, # Double Bagel Fridays 2
    213943, # Aces Championship Series: FINALE

    # Season 2: NEW SEASON, NEW CHARACTERS
    267731, # Hookshotz Replacementpaluza
    265099, # Cross-Court Chaos #1
    273743, # Cross-Court Chaos #2
    268984, # Double Bagel Fridays 3
    268639, # Aces Club Holiday Extravaganza!
    281197, # Double Bagel Fridays 4
    229370, # FellowsTV Open Circuit 2
    314488, # Cross-Court Chaos #3
    274465, # Heart of Battle
    319430, # MariTeni: Boom Boom's Day Off
    323798, # 2 Good Guys impromptu open
    330947, # MariTeni: Luigisuccapalooza
    327824, # Mario Tennis Aces Club Open #4

    # Season 3: I DON'T WANT THE NEW CHARACTERS NO MORE
    229370, # GatorLAN Spring 2019
    341744, # MariTeni: Bill (Standard Singles)
    341746, # MariTeni: Bill (Low Tier Standard)
    352416, # Mario Tennis Aces - Swiss!
    354814, # Mario Tennis Aces Club Open 5 - The Finale
    364952, # Switchfest 2
    401039, # PKHat Peteypahlooza
    406125, # Trick Shot Tourney #3
    411090, # Trick Shot Tourney #4
    417786, # Trick Shot Tourney #5
    421480, # Trick Shot Tourney #6
    424688, # Aces Club Holiday Extravaganza: The Second Coming
    439357, # Trick Shot Tourney #8
]

CHALLONGE_EVENT_IDS = [
    "7453651",  # Trick Shot Tournament 1
    "wfcsnku7", # Torneo Mansion Espejismo
]

def sort_by_date(sets)
    sets.sort! { |a, b| a.day_number <=> b.day_number }
end

def map_player_ids(players, sets)
    PLAYER_ID_MAP.keys.each do |player_id|
        players.delete(Player.new(player_id))
    end

    sets.each do |set|
        if PLAYER_ID_MAP.key?(set.player1_id)
            set.player1_id = PLAYER_ID_MAP[set.player1_id]
        end

        if PLAYER_ID_MAP.key?(set.player2_id)
            set.player2_id = PLAYER_ID_MAP[set.player2_id]
        end
    end
end

def create_whr_games(whr, sets)
    sets.each do |set|
        whr.create_game(set.player1_id,
                        set.player2_id,
                        set.winner,
                        set.day_number,
                        0)
    end
end

# Concatenate players and sets from all tournaments.
events = Set.new()
players = Set.new()
sets = []

challonge_client = ChallongeClient.new(ENV["CHALLONGE_API_TOKEN"])
smashgg_client = SmashggClient.new('1e31ebdee811bd14479b05553e638765')
csv_reader = CsvReader.new()
csv_writer = CsvWriter.new()

# TODO: Create a class to do all of this and dedupe.
CHALLONGE_EVENT_IDS.each do |challonge_event_id|
    event = nil
    event_players = []
    event_sets = []

    directory = "csv/C%s" % challonge_event_id
    if File.directory?(directory)
        event = csv_reader.read_events(directory + "/events.csv")[0]
        event_players = csv_reader.read_players(directory + "/players.csv")
        event_sets = csv_reader.read_sets(directory + "/sets.csv")
    else
        event, event_players, event_sets = challonge_client.get_event(challonge_event_id)
        FileUtils.mkdir_p(directory)
        csv_writer.write_events(directory + "/events.csv", [event])
        csv_writer.write_players(directory + "/players.csv", event_players)
        csv_writer.write_sets(directory + "/sets.csv", event_sets)
    end

    events.add(event)
    players.merge(event_players)
    sets.concat(event_sets)
end

SMASHGG_EVENT_IDS.each do |smashgg_event_id|
    event = nil
    event_players = []
    event_sets = []

    directory = "csv/S%d" % smashgg_event_id
    if File.directory?(directory)
        event = csv_reader.read_events(directory + "/events.csv")[0]
        event_players = csv_reader.read_players(directory + "/players.csv")
        event_sets = csv_reader.read_sets(directory + "/sets.csv")
    else
        event, event_players, event_sets = smashgg_client.get_event(smashgg_event_id)
        FileUtils.mkdir_p(directory)
        csv_writer.write_events(directory + "/events.csv", [event])
        csv_writer.write_players(directory + "/players.csv", event_players)
        csv_writer.write_sets(directory + "/sets.csv", event_sets)
    end
    
    events.add(event)
    players.merge(event_players)
    sets.concat(event_sets)
end

# w2 is the variability of the ratings over time.
# The default value of 300 is considered fairly high, but given the relatively few tournaments we have,
# it may be necessary.
whr = WholeHistoryRating::Base.new(:w2 => 300)

map_player_ids(players, sets)
sort_by_date(sets)
create_whr_games(whr, sets)

whr.iterate(100)
whr.print_ordered_ratings()

csv_writer.write_players("csv/players.csv", players)
csv_writer.write_events("csv/events.csv", events)
csv_writer.write_sets("csv/sets.csv", sets)
csv_writer.write_ratings("csv/ratings.csv", whr)
puts "Generated CSV files. Commit them into mta-whr."
