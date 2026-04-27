"""
    HousingPricing(agent::BlockGroup, model::ABM; housing_pricing_mode="simple_perc", price_increase_perc=0.05)

Updates housing prices within a block group based on the relationship between demand and supply.
For each housing category, prices are adjusted proportionally to the level of excess demand
relative to the total number of housing units (available + occupied).

If demand exceeds supply, prices increase; if demand is lower, prices may decrease. However,
a minimum price threshold is enforced to prevent prices from dropping below a fixed baseline.

# Arguments
- `agent::BlockGroup`: The block group agent containing housing stock, demand data, and pricing information.
- `model::ABM`: The overall agent-based model, providing access to the current simulation tick.

# Parameter
- 'housing_pricing_mode::String="simple_perc"': Specifies the pricing adjustment method (currently only simple percentage scaling is implemented).
- 'price_increase_perc::Float64=0.05': Base percentage used to scale price adjustments based on demand pressure.

# Returns
Nothing. Updates 'agent.new_price' in place for each housing category.
"""
function HousingPricing(agent::BlockGroup, model::ABM; housing_pricing_mode = "simple_perc", price_increase_perc = 0.05)
    for key in keys(agent.demand_exceeds_supply)
        tot_units = agent.available_units[key] + agent.occupied_units[key]
        if tot_units == 0 #No housing present in that Category 
            continue
        else
            #update bg new price in dataframe
            new_price = agent.new_price[key] * (1 + (price_increase_perc*(agent.demand_exceeds_supply[key][model.tick]/tot_units)))
            #Set lower limit ($10000) for housing price so that prices arent driven to 0
            agent.new_price[key] = new_price < 10000 ? 10000 : new_price
        end
    end
end