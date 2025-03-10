#Load Project Environment
import Pkg
Pkg.activate(dirname(@__DIR__))
Pkg.instantiate()

#Load Packages
using CSV, DataFrames
using DataStructures
using Agents
using Statistics,StatsBase,Distributions

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C



###Load Input data:
##For flood history input
f_df = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data", "synth_flood_phil.csv")))

##For BG
#open bg file
phil_bg = DataFrame(CSV.File(joinpath(dirname(@__DIR__), "data/philly_bg_2019.csv")))
#groupby BG
grouped_phil_bg = groupby(phil_bg, :GEOID)

##load pop data
phil_cbsa_base_pop = DataFrame(CSV.File(joinpath(dirname(dirname(@__DIR__)), "philadelphia-data/census_data/synth_pop/pop_files/philly_cbsa_pop_0.csv")))
#drop missing values
dropmissing!(phil_cbsa_base_pop, :NP)

#Subset to Phil. County (Not part of function)
phil_base_pop = subset(phil_cbsa_base_pop, :county => x -> x .== 42101)

#Define input Parameters
no_of_years = 35
start_year = 1980
no_hhs_per_agent=10
grouped = true
group_col = "adj_income_2019"
cutoff_dict = OrderedDict("low"=> [-60000.00,25000.00], "medium"=>[25000.00,75000.00], "high"=>[75000.00, 1e7])
bg_cat = Dict(:col =>"income_cat", :group => ["low", "medium", "high"])
house_budget_mode = "perc"
house_choice_mode = "flood_mem_utility"
risk_averse = 0.3
flood_mem = 10
seed = 1500

### Calculate Flood matrix and Dict for ABM input
f_dict, f_matrix = CHANCE_C.flood_history(f_df; no_of_years = no_of_years, start_year = start_year)

### Initialize ABM
phil_abm = CHANCE_C.Simulator(phil_bg, phil_base_pop, f_dict, f_matrix, CHANCE_C.model_step!; no_of_years = no_of_years, no_hhs_per_agent = no_hhs_per_agent,
house_budget_mode = house_budget_mode, house_choice_mode = house_choice_mode, grouped = grouped, group_col = group_col, cutoff_dict = cutoff_dict, bg_cat = bg_cat,
risk_averse = risk_averse, flood_mem = flood_mem, seed = seed)




### Test model functions
test_bg = phil_abm[10]
println("Occupied: ",test_bg.occupied_units)
println("Available: ",test_bg.available_units)
println("Population: ",test_bg.population)

#CHANCE_C.agent_prob!(test_bg, phil_abm)

function agent_locate(agent::CHANCE_C.Queue, model::ABM; levee = false, f_e = 0.0, bg_sample_size = 10, house_choice_mode = "simple_anova_utility",
    budget_reduction_perc = 0.10, penalty = 50, migrate_prob = 0.05)
    
    loc_df = copy(model.df)
    # Preallocate the DataFrame with a reasonable initial capacity
    bg_sample = DataFrame(hh_id = Int64[], bg_id = Int64[], GEOID = Int64[], cat = String[], bg_utility = Float64[])

    # Use view or filter instead of multiple list comprehensions
    moving_agents = sort!([a for a in agents_in_position(agent, model) if a isa HHAgent], by=a -> a.income, rev=true)

    # Preallocate some vectors to reduce memory allocations
    bg_ids = Vector{Int64}(undef, bg_sample_size)
    bg_GEOID = Vector{Int64}(undef, bg_sample_size)
    bg_cat = Vector{String}(undef, bg_sample_size)
    bg_utilities = Vector{Float64}(undef, bg_sample_size)

    for hh_agent in moving_agents
        # Consolidate budget selection logic
        bg_budget = if house_choice_mode == "simple_avoidance_utility"
            hh_agent.avoidance ? 
                subset(loc_df, :perc_fld_area => n -> n .<= 0.10) :
                subset(loc_df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true)
        elseif house_choice_mode == "budget_reduction"
            new_house_budget = hh_agent.house_budget * (1 - budget_reduction_perc)
            hh_budget = ifelse.(loc_df.perc_fld_area .>= 0.10, new_house_budget, hh_agent.house_budget)
            subset(loc_df, :market_value => n -> n .<= hh_budget, skipmissing=true, view = true)
        else
            subset(loc_df, :market_value => n -> n .<= hh_agent.house_budget, skipmissing=true, view = true)
        end

        # Use a more efficient sampling approach
        try
            # Precompute weights to avoid repeated calculations
            weights = ProbabilityWeights(bg_budget.available_units ./ sum(bg_budget.available_units))
            
            # Check for available locations more efficiently
            valid_locations = findall(weights .> 0)
            if isempty(valid_locations)
                throw(ErrorException("No affordable locations with available units"))
            end

            # Efficient sampling
            sample_size = min(length(valid_locations), bg_sample_size)
            sampled_indices = sample(abmrng(model), valid_locations, sample_size, replace=false)
            #bg_options = bg_budget[sampled_indices, :]
            bg_budget[sampled_indices, "GEOID"]
            #Grab utilities from sampled locations
            #bg_sel = first(Iterators.filter(bg -> bg isa BlockGroup && bg.GEOID == row.GEOID, allagents(model)))
            #bg_utilities[i] = getindex(getproperty(bg_sel, :current_utility), row.income_cat)
            """
            # More efficient way to get block group and utility information
            resize!(bg_ids, sample_size)
            resize!(bg_GEOID, sample_size)
            resize!(bg_cat, sample_size)
            resize!(bg_utilities, sample_size)

            @inbounds for (i, row) in enumerate(eachrow(bg_options))
                # Find block group more efficiently
                bg_sel = first(Iterators.filter(bg -> bg isa BlockGroup && bg.GEOID in row.GEOID, allagents(model)))
                
                bg_ids[i] = bg_sel.id
                bg_GEOID[i] = row.GEOID
                bg_cat[i] = row.income_cat
                bg_utilities[i] = getindex(getproperty(bg_sel, :current_utility), row.income_cat)
            end

            # Create move DataFrame more efficiently
            move_df = DataFrame(
                hh_id = fill(hh_agent.id, sample_size), 
                bg_id = bg_ids[1:sample_size], 
                GEOID = bg_GEOID[1:sample_size], 
                cat = bg_cat[1:sample_size], 
                bg_utility = bg_utilities[1:sample_size]
            )

            # Filter moves with higher utility
            current_utility = first(values(hh_agent.utility))
            move_df = move_df[move_df.bg_utility .> current_utility, :]

            # Check if any moves are possible
            if isempty(move_df)
                throw(ErrorException("No better locations found"))
            end

            # Append to bg_sample
            append!(bg_sample, move_df)
        """
        catch
            println("Didnt work!")
            """
            # Migration logic remains similar
            if rand(abmrng(model), Binomial(1, migrate_prob)) == 1
                last_bg = model[first(keys(hh_agent.utility))]
                move_agent!(hh_agent, last_bg.pos, model)
                last_bg.occupied_units[hh_agent.group] += 1
                last_bg.available_units[hh_agent.group] -= 1
                last_bg.population += getproperty(hh_agent, :no_hhs_per_agent) * getproperty(hh_agent, :hh_size)
            else
                remove_agent!(hh_agent, model)
            end
            """
        end
    end

    append!(model.hh_utilities_df, bg_sample)
end


bg_s = agent_locate(phil_abm[0], phil_abm)

phil_abm.tick += 1
CHANCE_C.flooded!(test_bg, phil_abm)

CHANCE_C.agent_prob!(test_bg, phil_abm)

CHANCE_C.AgentLocation(phil_abm[0], phil_abm)

CHANCE_C.HousingMarket(phil_abm)

CHANCE_C.BuildingDevelopment(test_bg, phil_abm)
CHANCE_C.HousingPricing(test_bg, phil_abm)

phil_abm[test_bg.id].avg_hh_income = mean([a.income for a in agents_in_position(phil_abm[test_bg.id].pos, phil_abm) if a isa HHAgent])

CHANCE_C.LandscapeStatistics(phil_abm)
