
function BuildingDevelopment(agent::BlockGroup, model::ABM; stock_increase_mode = "simple_perc", stock_increase_perc = 0.05)
    for key in keys(agent.demand_exceeds_supply)
        if agent.demand_exceeds_supply[key][model.tick]
            new_units_constructed = round(agent.occupied_units[key] * stock_increase_perc)
            agent.available_units[key] += Int(new_units_constructed)
        end
    end
end