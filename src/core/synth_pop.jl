### File holds functions to initialize household agents with census demographic data
using CSV, DataFrames
using DataFrameMacros
using Chain
using Statistics

#load pop data
phil_cbsa_base_pop = DataFrame(CSV.File(joinpath(dirname(pwd()), "philadelphia-data/synth_pop/pop_files/philly_cbsa_pop_0.csv")))
#drop missing values
dropmissing!(phil_cbsa_base_pop, :NP)

#Subset to Phil. County (Not part of function)
phil_base_pop = subset(phil_cbsa_base_pop, :county => x -> x .== 42101)


#Group by Block group (GEOID)
phil_pop_gdf = groupby(phil_base_pop, :GEOID)

#Check vacants by BG 
combine(subset(phil_pop_gdf, :NP => x -> x .== 0.0, ungroup=false), nrow)
#Check households (NP > 0) by BG
combine(subset(phil_pop_gdf, :NP => x -> x .> 0.0, ungroup=false), nrow)

##For this function, Household agents are created within each block group, We'll subset by the given input block group, then group by race category.
#test_bg = 421010355003
function agent_bin(bg_id::Int64, pop_df::DataFrame; no_hhs_per_agent::Int64, group_col::Symbol, house_budget_mode::String, hh_budget_perc::Float64)
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

#check function:

dict, ag_df = agent_bin(421010355003, phil_base_pop; no_hhs_per_agent=10, group_col = :RAC1P, house_budget_mode = "rhea", hh_budget_perc = 0.33)

#default function that uses block group averages
#Assign BG flood area value based on 100 year event (7th column of matrix is 100 yr event)
bg.perc_fld_area = model.flood_matrix[bg.id,7,1]
function bg_bin(bg_id::Int64, pop_df::DataFrame; no_hhs_per_agent::Int64)
    bg_df = subset(pop_df, :GEOID => x -> x .== bg_id) 
    
    #Calculate number of vacant households within BG
    vacant_hh = nrow(subset(bg_df, :NP => x -> x .== 0.0))
    #Calculate number of occupied households within BG
    bg_hh_df = subset(bg_df, :NP => x -> x .> 0.0)
    occupied_hh = nrow(bg_hh_df)

    #Calculate BG population
    bg_pop = sum(bg_hh_df.NP)

    #Calculate avg hh size
    avg_hhsize = mean(bg_hh_df.NP)
    #calculate avg income 
    avg_income = mean(bg_hh_df.adj_income_2019)


    no_of_hhs = round(bg_pop / avg_hhsize)
    no_of_agents = fld(no_of_hhs, no_hhs_per_agent)

    #create dataframe
    agent_df = DataFrame(nrow = repeat([no_hhs_per_agent], no_of_agents), race = Float64[], avg_hh_size = repeat([avg_hhsize], no_of_agents), avg_income = repeat([avg_income], no_of_agents))


    #Create dict for Bg summary Statistics
    bg_dict = Dict(:vacant => vacant_hh, :occupied => occupied_hh, :total_pop => bg_pop)
    #Return dict and agent DataFrame
    return bg_dict, agent_df
end


if bg.hhsize90 != 0.0 && isfinite(bg.hhsize90)
    no_of_hhs = round(bg.pop90 / bg.hhsize90)
    no_of_agents = fld(fld(no_of_hhs + no_hhs_per_agent, 2), no_hhs_per_agent) #division with rounding to nearest integer

    #bg.population = Int(round(no_of_agents * no_hhs_per_agent * bg.hhsize90))
    bg.population = bg.pop90

else  # if hh size is 0.0 or nan (i.e., data error) using median household size for population
    bg.hhsize90 = median(skipmissing(model.df.hhsize1990))

    no_of_hhs = round(bg.pop90 / bg.hhsize90)
    no_of_agents = fld(fld(no_of_hhs + no_hhs_per_agent, 2), no_hhs_per_agent) #division with rounding to nearest integer

    #bg.population = Int(round(no_of_agents * no_hhs_per_agent * bg.hhsize90))
    bg.population = bg.pop90

end




"""
#Calculate number of created agents
sub_df1 = rac_gdf[1]
sort!(sub_df1, :HINCP)
sub_df1[:,:group] = map(x->div(x,no_hhs_per_agent), 1:nrow(sub_df1))
hh_bins = combine(groupby(sub_df1, :group), nrow, :RAC1P => maximum => :race, [:NP, :adj_income_2019] .=> mean .=> [:avg_hh_size, :avg_income])
hh_bins[:,2:end]
append!(agent_df, hh_bins[:,2:end])
"""
