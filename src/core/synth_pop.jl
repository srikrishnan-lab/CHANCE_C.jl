### File holds functions to initialize household agents with census demographic data
##Function to calculate agent utility 
function calc_utility(row, house_choice_mode; levee = false, f_e = 0.0,
     cd_dict = Dict(:a=>0.4,:b=>0.4,:c=>0.2), anova_coef = [-121428, 294707, 130553, 128990, 154887, 72443], flood_coef = -500000)

    #Determine if flood disamenity is reduced from levee presence
    scale_factor = levee ? 1.0 - (10 * f_e) : 1.0
    
    if house_choice_mode == "cobb_douglas_utility"
        util = row.average_income_norm ^ cd_dict[:a] * row.prox_cbd_norm ^ cd_dict[:b] * row.flood_risk_norm ^ cd_dict[:c]

    elseif house_choice_mode == "simple_flood_utility"
        util = anova_coef[1] + (anova_coef[2] * row.N_MeanSqfeet) + (anova_coef[3] * row.N_MeanAge) + (anova_coef[4] * row.N_MeanNoOfStories) + 
        (anova_coef[5] * row.N_MeanFullBathNumber) + (flood_coef * row.perc_fld_area) + (1 * row.residuals)
        
    elseif house_choice_mode == "flood_mem_utility"
        util = anova_coef[1] + (anova_coef[2] * row.total_livable_area) + (anova_coef[3] * row.house_age) + (anova_coef[4] * row.stories_n) + 
        (anova_coef[5] * row.number_of_bathrooms) + (anova_coef[5] * (row.cbd_dist_norm + row.water_dist_norm)) #(scale_factor * flood_coef * (model[Int(prop.GEOID)].flood_hazard/model.relo_sampler[:mem])) #+ (1 * row.residuals)

    elseif house_choice_mode == "flood_ind_utility" #Treats amenities as an index
        util = (anova_coef[1] * (row.total_livable_area + row.stories_n)) + (anova_coef[2] * (row.cbd_dist_norm + row.water_dist_norm))

    else #house_choice_mode == "simple_anova_utility" or house_choice_mode == "budget_reduction" or house_choice_mode == "simple_avoidance_utility"
        util = anova_coef[1] + (anova_coef[2] * row.N_MeanSqfeet) + (anova_coef[3] * row.N_MeanAge) + (anova_coef[4] * row.N_MeanNoOfStories) + 
        (anova_coef[5] * row.N_MeanFullBathNumber) + (1 * row.residuals)
    end
    return util 
end


##For BlockGroup Agents
function create_bg_balt(row, no_of_years)
    """
    Function creates BlockGroup Agent Object
    to late be inputted into an ABM
    inputs: row from DF, col name to initialize agent fields
    output: BlockGroup Object
    """

    new_bg = BlockGroup(Int(row.fid_1),(0,0),row.GEOID, row.ALAND, 
    row.AJWME001, 0, row.pop1990, row.mhi1990, row.hhsize1990,
    row.coastdist, row.cbddist, row.hhtrans1993, 
    0,0,"no",row.new_price,0, 0,0,0.0,"no",repeat([false], no_of_years),0,0.0,0.0,0.0)
    
    return new_bg
end

function create_bg_phil(row, no_of_years; agent_id = 1, categories = [1,2,3], house_choice_mode = "flood_mem_utility", 
    simple_anova_coefficients = Dict(1=> [-121428, 294707, 130553, 128990, 154887, 72443], 2=> [-121428, 294707, 130553, 128990, 154887, 72443], 3=> [-121428, 294707, 130553, 128990, 154887, 72443]))
    """
    Function creates BlockGroup Agent Object
    to late be inputted into an ABM
    inputs: row from DF, col name to initialize agent fields
    output: BlockGroup Object
    """
    if typeof(row) == SubDataFrame{DataFrame, DataFrames.Index, Vector{Int64}}
        #Categories with no properties in the Block Group may have missing values,
        #Convert all missing market values to 0.0
        market_vals = [ismissing(row[row.income_cat .== i,:].market_value[1]) ? 0.0 : row[row.income_cat .== i,:].market_value[1] for i in categories]
        new_price = Dict(categories .=> market_vals)

        occupied_units = Dict(categories .=> 0) 
        available_units = Dict(i => row[row.income_cat .== i,:].counts[1] for i in categories) #number of properties in income category
        new_units_constructed = Dict(categories .=> 0)
        demand_exceeds_supply = Dict(i => zeros(no_of_years) for i in categories)

        #Calculate agent utility for living in Block Group
        base_utility = Dict(categories .=> 0.0)
        for cat in categories
            utility = calc_utility(row[row.income_cat .== cat,:][1,:], house_choice_mode; anova_coef = simple_anova_coefficients[cat])
            base_utility[cat] = ismissing(utility) ? -90000.0 : utility
        end
         

        new_bg = BlockGroup(agent_id,(0,0),row.GEOID[1], row.ALAND[1], 
    0, row.perc_flpn_area[1], 0, 0, 0.0, 0.0, 0, 0.0, base_utility, base_utility, new_price, 0, occupied_units, available_units, 
    0.0, demand_exceeds_supply, new_units_constructed, 0.0, 0.0, 0.0)
    
    elseif typeof(row) == DataFrameRow{DataFrame, DataFrames.Index}
        new_price = row.new_price
        occupied_units = 0
        available_units = 0
        new_units_constructed = 0
        demand_exceeds_supply = repeat([false], no_of_years)

        new_bg = BlockGroup(agent_id, (0,0), row.GEOID, row.ALAND, 
    0, 0, 0, 0, 0.0, 0.0, 0, 0.0, row.new_price, 0, occupied_units, available_units, 
    0.0, demand_exceeds_supply, new_units_constructed, 0.0, 0.0, 0.0)
    end

    return new_bg
end


## For HHAgent Agents
function agent_bin_cont(bg_id::Int64, pop_df::DataFrame; no_hhs_per_agent::Int64, group_col::String, cutoffs::OrderedDict{Int64, Vector{Float64}}, house_budget_mode::String, hh_budget_perc::Float64)
    bg_df = subset(pop_df, :GEOID => x -> x .== bg_id) 
    
    #Calculate number of vacant households within BG
    vacant_hh = nrow(subset(bg_df, :NP => x -> x .== 0.0))
    #Convert to count of vacant agents
    vac_units = div(vacant_hh,no_hhs_per_agent)

    #Subset to only occupied households
    bg_hh_df = subset(bg_df, :NP => x -> x .> 0.0)
    
    #calculate avg HH income
    avg_inc = mean(bg_hh_df.adj_income_2019)
    #calculate avg HH size
    avg_hh_size = mean(bg_hh_df.NP)
    

    #Create group labels by group col
    bg_hh_df[:, :category] = cut(bg_hh_df[:, group_col], unique(reduce(vcat, collect(values(cutoffs)))), labels = collect(keys(cutoffs)))
    #groupby category column 
    grouped_df = groupby(bg_hh_df, :category)
    #Create empty DataFrame
    agent_df = DataFrame(nrow = Int64[], cat = Int64[], race = Float64[], avg_hh_size = Float64[], avg_income = Float64[])
    for sub_df in grouped_df
        sort!(sub_df, :adj_income_2019)
        sub_df[:,:group] = map(x->div(x,no_hhs_per_agent), 1:nrow(sub_df))
        hh_bins = combine(groupby(sub_df, :group), nrow, :category => (c -> mode(c)) => :cat, :RAC1P => (r -> mode(r)) => :race,  [:NP, :adj_income_2019] .=> mean .=> [:avg_hh_size, :avg_income])
        append!(agent_df, hh_bins[:,2:end])
    end
    
    #Calculate agent budgets
    if house_budget_mode == "rhea"
        agent_df.budget = exp.(4.96 .+ (0.63 .* log.(agent_df.avg_income)))
    elseif house_budget_mode == "perc"
        agent_df.budget = agent_df.avg_income .* (1 + hh_budget_perc)
    end
    #Calculate number of occupied households within BG
    occ_units = nrow(agent_df)
    #Calculate model BG population
    bg_pop = ceil(sum(agent_df.avg_hh_size .* no_hhs_per_agent))
    #Create dict for Bg summary Statistics
    bg_dict = Dict(:vacant => vac_units, :occupied => occ_units, :total_pop => bg_pop, :avg_hh_size => avg_hh_size, :avg_inc => avg_inc)
    
    #Return dict and agent DataFrame
    return bg_dict, agent_df
end



##For this function, Household agents are created within each block group, We'll subset by the given input block group, then group by a categorical category, such as race.
function agent_bin_cat(bg_id::Int64, pop_df::DataFrame; no_hhs_per_agent::Int64, group_col::String, house_budget_mode::String, hh_budget_perc::Float64)
    bg_df = subset(pop_df, :GEOID => x -> x .== bg_id) 
    
    #Calculate number of vacant households within BG
    vacant_hh = nrow(subset(bg_df, :NP => x -> x .== 0.0))
    #Calculate number of occupied households within BG
    bg_hh_df = subset(bg_df, :NP => x -> x .> 0.0)
    occupied_hh = nrow(bg_hh_df)
    
    #calculate avg HH income
    avg_inc = mean(bg_hh_df.adj_income_2019)
    #calculate avg HH size
    avg_hh_size = mean(bg_hh_df.NP)
    #Calculate BG population
    bg_pop = sum(bg_hh_df.NP)

    #Group households in BG by race
    rac_gdf = groupby(bg_hh_df, group_col)
    
    #Create empty DataFrame
    agent_df = DataFrame(nrow = Int64[], race = Float64[], avg_hh_size = Float64[], avg_income = Float64[])
    for sub_df in rac_gdf
        sort!(sub_df, :adj_income_2019)
        sub_df[:,:group] = map(x->div(x,no_hhs_per_agent), 1:nrow(sub_df))
        hh_bins = combine(groupby(sub_df, :group), nrow, :RAC1P => maximum => :race,  [:NP, :adj_income_2019] .=> mean .=> [:avg_hh_size, :avg_income])
        append!(agent_df, hh_bins[:,2:end])
    end
    
    #Calculate agent budgets
    if house_budget_mode == "rhea"
        transform!(agent_df, )
        agent_df.budget = exp.(4.96 .+ (0.63 .* log.(agent_df.avg_income)))
    elseif house_budget_mode == "perc"
        agent_df.budget = agent_df.avg_income .* (1 + hh_budget_perc)
    end

    #Create dict for Bg summary Statistics
    bg_dict = Dict(:vacant => vacant_hh, :occupied => occupied_hh, :total_pop => bg_pop, :avg_hh_size => avg_hh_size, :avg_inc => avg_inc)
    
    #Return dict and agent DataFrame
    return bg_dict, agent_df
end


#default function that uses block group averages
#Assign BG flood area value based on 100 year event (7th column of matrix is 100 yr event)
#bg.perc_fld_area = model.flood_matrix[bg.id,7,1]







