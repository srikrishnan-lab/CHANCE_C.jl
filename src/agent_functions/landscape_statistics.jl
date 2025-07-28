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




function LocationUpdate(model::ABM; bg_cat = Dict(:col =>"income_cat", :occ_cat => [1,2,3]), grouped = true)
    # Create mapping from (GEOID, category) to row indices for fast lookup
    if grouped
        row_lookup = Dict{Tuple{Int64, Int64}, Int64}()
        for (i, row) in enumerate(eachrow(model.df))
            row_lookup[(row.GEOID, row[bg_cat[:col]])] = i
        end

        #Update model df from Block Group updates
        bgs = [a for a in allids(model) if model[a] isa BlockGroup]
        for bg in bgs 
            for cat in bg_cat[:occ_cat]
                if haskey(row_lookup, (model[bg].GEOID, cat))
                    row_idx = row_lookup[(model[bg].GEOID, cat)]
                    model.df[row_idx, :occupied_units] = model[bg].occupied_units[cat]
                    model.df[row_idx, :available_units] = model[bg].available_units[cat]
                    model.df[row_idx, :average_income] = model[bg].avg_hh_income
                    model.df[row_idx, :market_value] = model[bg].new_price[cat]
                end
            end
        end
    else
        # For ungrouped case
        row_lookup = Dict{Int64, Int64}()
        for (i, row) in enumerate(eachrow(model.df))
            row_lookup[row.GEOID] = i
        end
        bgs = [a for a in allids(model) if model[a] isa BlockGroup]
        for bg in bgs 
            if haskey(row_lookup, model[bg].GEOID)
                row_idx = row_lookup[model[bg].GEOID]
                model.df[row_idx, :occupied_units] = model[bg].occupied_units
                model.df[row_idx, :available_units] = model[bg].available_units
                model.df[row_idx, :average_income] = model[bg].avg_hh_income
                model.df[row_idx, :market_value] = model[bg].new_price
            end
        end
    end

    # Calculate normalized income
    valid_incomes = filter(!isnan, model.df.average_income)
    if !isempty(valid_incomes)
        model.df[!, :average_income_norm] = model.df.average_income ./ maximum(valid_incomes)
    end
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