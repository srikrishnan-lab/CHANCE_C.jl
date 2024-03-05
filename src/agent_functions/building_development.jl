

function BuildingDevelopment(agent::BlockGroup, model::ABM; stock_increase_mode = "simple_perc", stock_increase_perc = 0.05)
    if agent.demand_exceeds_supply[model.tick]
        new_units_constructed = round(agent.occupied_units * stock_increase_perc)
        agent.available_units += Int(new_units_constructed)
    end
end