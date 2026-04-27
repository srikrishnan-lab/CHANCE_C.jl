
"""
    BuildingDevelopment(agent::BlockGroup, model::ABM; stock_increase_mode="simple_perc", stock_increase_perc=0.05)

-Simulates the construction of new housing units within a block group based on unmet demand.
-For each housing category, if demand exceeds supply at the current model tick, new units are
-constructed proportional to the level of excess demand and the number of currently occupied units.

The number of new units is determined by scaling the occupied units by a percentage factor
('stock_increase_perc') and the ratio of unmet demand to total units. Categories with zero
existing units are skipped.

# Arguments
- 'agent::BlockGroup': The block group agent whose housing stock is being updated.
- 'model::ABM': The agent-based model containing global state, including the current time step ('tick').

# Parameter
- 'stock_increase_mode::String="simple_perc"': Specifies the method used to calculate housing growth
  (currently only a simple percentage-based approach is implemented).
- 'stock_increase_perc::Float64=0.05': Base percentage used to scale new construction relative to
  occupied units and unmet demand.

# Behavior
- Iterates over all housing categories in 'agent.demand_exceeds_supply'.
- If unmet demand is non-negative at the current tick, new units may be constructed.
- Skips categories with zero total units (no existing housing stock).
- Updates:
  - 'agent.available_units' by adding newly constructed units.
  - 'agent.new_units_constructed' with the number of units built in the current step.
- New construction is proportional to both demand pressure and existing occupancy.
- The result is rounded to the nearest integer before being applied.

# Returns
 'Nothing'
"""
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
