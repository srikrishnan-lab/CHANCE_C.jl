
function HousingPricing(agent::BlockGroup, model::ABM; housing_pricing_mode = "simple_perc", price_increase_perc = 0.05)
    for key in keys(agent.demand_exceeds_supply)
        tot_units = agent.available_units[key] + agent.occupied_units[key]
        if tot_units == 0 #No housing present in that Category 
            continue
        else
            #update bg new price in dataframe
            agent.new_price[key] *= (1 + (price_increase_perc*(agent.demand_exceeds_supply[key][model.tick]/tot_units)))
        end
    end
end