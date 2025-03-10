
function HousingPricing(agent::BlockGroup, model::ABM; housing_pricing_mode = "simple_perc", price_increase_perc = 0.05)
    for key in keys(agent.demand_exceeds_supply)
        if agent.demand_exceeds_supply[key][model.tick]
            agent.new_price[key] *= (1 + price_increase_perc)
            #update bg new price in dataframe
        end

        if model.tick >= 5
            if !any(last(agent.demand_exceeds_supply[key][1:model.tick],5))
                agent.new_price[key] *= (1 - price_increase_perc)
            end
        end
    end
end