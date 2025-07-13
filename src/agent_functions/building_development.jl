
function BuildingDevelopment(agent::BlockGroup, model::ABM; stock_increase_mode = "simple_perc", stock_increase_perc = 0.05)
    for key in keys(agent.demand_exceeds_supply)
        if agent.demand_exceeds_supply[key][model.tick] >= 0.0
            #Total units across all categories
            tot_units = agent.available_units[key] + agent.occupied_units[key]
            if tot_units == 0 #No housing present in that Category 
                continue
            else
                new_units_constructed = round(agent.occupied_units[key] * (stock_increase_perc * (agent.demand_exceeds_supply[key][model.tick]/tot_units)))
                #Update properties
                agent.available_units[key] += Int(new_units_constructed)
                agent.new_units_constructed[key] = Int(new_units_constructed)
            end
        end
    end
    #If no units present in category
end
