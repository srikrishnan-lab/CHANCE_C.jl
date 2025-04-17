##Calculating Population Characteristics
BG(agent) = agent isa BlockGroup
HH(agent) = agent isa HHAgent && agent.bg_id >= 1
#Pop. Category Pop
hh_low(agent) = agent.group == 1 ? 1 : 0
hh_med(agent) = agent.group == 2 ? 1 : 0
hh_high(agent) = agent.group == 3 ? 1 : 0
#Occupancy Pop
occ_low(agent) = agent.occupied_units[1]
occ_med(agent) = agent.occupied_units[2]
occ_high(agent) = agent.occupied_units[3]

##Calculating Transaction Characteristics
function moved(model, cat)
    count = 0
    cat_ids = [id for id in allids(model) if model[id] isa HHAgent && model[id].bg_id >= 1 && model[id].occ_cat == cat]
    for id in cat_ids
        count += model[id].year_of_residence == model.tick ? 1.0 : 0.0
    end
    return count  
end

moved_low(model) = moved(model, 1)
moved_med(model) = moved(model, 2)
moved_high(model) = moved(model, 3)

price_low(agent) = agent.new_price[1]
price_med(agent) = agent.new_price[2]
price_high(agent) = agent.new_price[3]
