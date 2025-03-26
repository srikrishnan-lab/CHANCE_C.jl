#update model dataframe with newly calculated blockgroup attributes
"""
collect agent data and update dataframe through model function. Update bg attributes in bg specific functions.
Updating avg_hh_income should be in a bg specific function
"""
#BG agent attributes needing updating 
#agent.population


function LandscapeStatistics(model::ABM; bg_cat = Dict(:col =>"income_cat", :group => [1,2,3]))
    # model BG df attributes needing updating:
    update_df = DataFrame(id = Int64[], cat = Int64[], occupied_units = Int64[], available_units = Int64[], average_income = Float64[], market_value = Float64[])
    #Update df with collected updated BlockGroupattributes
    for cat in bg_cat[:group]
        push!.(Ref(update_df),[[a.GEOID, cat, a.occupied_units[cat], a.available_units[cat], a.avg_hh_income, a.new_price[cat]] for a in allagents(model) if a isa BlockGroup])
    end
    #join model df with update df
    inter_df = leftjoin(model.df,update_df, on = ["GEOID" => "id", bg_cat[:col] => "cat"], makeunique=true)
    #update model columns
    for col in ["occupied_units", "available_units", "average_income", "market_value"]
        model.df[!, col] = inter_df[!, col * "_1"]
    end

    ## calculate normalized statistics for block groups
    model.df[!,"average_income_norm"] = model.df[!, "average_income"] / maximum(filter(!isnan,model.df.average_income));
end

"""
### For Data Collection ###
#Calculate BG statistics based on agent properties within each BG
    #Future: Set income/size to NaN if avg == 0 (no agents in block group) 
    agent.avg_hh_income = mean([a.income for a in agents_in_position(bg.pos, model) if a isa HHAgent])
    agent.avg_hh_size = mean([a.hh_size for a in agents_in_position(bg.pos, model) if a isa HHAgent])

    agent.pop_density = agent.population / agent.area

    model.avg_hh_income
    model.avg_hh_size
"""