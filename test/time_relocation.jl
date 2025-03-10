### For timing of model executions and specific evolution functions
import Pkg
Pkg.activate(dirname(@__DIR__))
Pkg.instantiate()

include(joinpath(dirname(@__DIR__), "src/CHANCE_C.jl"))
using .CHANCE_C #add period since module is local to repository
using CSV, DataFrames
using DataStructures
using Statistics,StatsBase,Distributions
using Agents

using BenchmarkTools, TimerOutputs

### Load input Data
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


#Define relevant parameters
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

tmr = TimerOutput()
#Define agent relocation function
function ag_locate(agent::CHANCE_C.Queue, model::ABM; levee = false, f_e = 0.0, bg_sample_size = 10, house_choice_mode = "simple_anova_utility",
    budget_reduction_perc = 0.10, penalty = 50, migrate_prob = 0.05)

    loc_df = copy(model.df)
    # Create a GEOID-to-BlockGroup lookup
    geoid_to_bg = Dict{Int64, Int64}()
    for bg in allagents(model)
        if bg isa BlockGroup
            geoid_to_bg[bg.GEOID] = bg.id
        end
    end

    # Use view or filter instead of multiple list comprehensions
    moving_agents = sort!([a for a in agents_in_position(agent, model) if a isa HHAgent], by=a -> a.income, rev=true)

    current_index = 1
    #Preallocate some vectors to reduce memory allocations
    hh_ids = Vector{Int64}(undef, bg_sample_size * length(moving_agents))
    bg_ids = Vector{Int64}(undef, bg_sample_size * length(moving_agents))
    bg_GEOID = Vector{Int64}(undef, bg_sample_size* length(moving_agents))
    bg_cat = Vector{String}(undef, bg_sample_size* length(moving_agents))
    bg_utilities = Vector{Float64}(undef, bg_sample_size * length(moving_agents))

    for hh_agent in moving_agents
        @timeit tmr "Budget Subsetting" begin
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
        end

        # Use a more efficient sampling approach
        try
            @timeit tmr "Sample Locations" begin
                # Precompute weights to avoid repeated calculations
                weights = ProbabilityWeights(bg_budget.available_units ./ sum(bg_budget.available_units))
                
                # Check for available locations more efficiently
                valid_locations = findall(weights .> 0)
                if isempty(valid_locations)
                    throw(ErrorException("No affordable locations with available units"))
                end

                #Sample from affordable locations based on weights
                sample_size = min(length(valid_locations), bg_sample_size)
                sampled_indices = sample(abmrng(model), valid_locations, sample_size, replace=false)
            end

            #Grab utilities from sampled locations
            @timeit tmr "Grab Utilities" begin
                #bg_sel = Iterators.filter(bg -> bg isa BlockGroup && bg.GEOID in bg_budget[sampled_indices, :GEOID], allagents(model))
                loc_utilities = [model[geoid_to_bg[row.GEOID]].current_utility[row.income_cat] for row in eachrow(bg_budget[sampled_indices, [:GEOID, :income_cat]])]
                # Find indices of block groups with better utilities than current agent location
                current_utility = first(values(hh_agent.utility))
                opt_locs = findall(>(current_utility), loc_utilities)

                # Check if any moves are possible
                if isempty(opt_locs)
                    throw(ErrorException("No better locations found"))
                end
                best_indices = sampled_indices[opt_locs]
            end

            @timeit tmr "Prop. Append" begin
                #Append future block group properties to vectors
                ind_length = length(best_indices)

                copyto!(hh_ids, current_index, fill(hh_agent.id, ind_length), 1, ind_length)
                copyto!(bg_ids, current_index, getindex.(Ref(geoid_to_bg), bg_budget[best_indices,:GEOID]), 1, ind_length)
                copyto!(bg_GEOID, current_index, bg_budget[best_indices, :GEOID], 1, ind_length)
                copyto!(bg_cat, current_index, bg_budget[best_indices, :income_cat], 1, ind_length)
                copyto!(bg_utilities, current_index, loc_utilities[opt_locs], 1, ind_length)

                current_index += ind_length
            end

        catch
            @timeit tmr "Relocate" begin
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
            end
        end
    end
    
    ##Create df from vectors, append to model properties df
    #Remove extra undef values by using current index
    bg_sample = DataFrame(hh_id = hh_ids[1:current_index-1], bg_id = bg_ids[1:current_index-1], 
    GEOID = bg_GEOID[1:current_index-1], cat = bg_cat[1:current_index-1], bg_utility = bg_utilities[1:current_index-1])
    
    append!(model.hh_utilities_df, bg_sample)
end

function ag_step!(agent::CHANCE_C.BlockGroup, model::ABM)
    CHANCE_C.flooded!(agent, model; model.flood_hazard...)
    CHANCE_C.agent_prob!(agent, model; model.relo_sampler...)
end

## Calculate Flood matrix and Dict for ABM input
f_dict, f_matrix = CHANCE_C.flood_history(f_df; no_of_years = no_of_years, start_year = start_year)

### Initialize ABM
phil_abm = CHANCE_C.Simulator(phil_bg, phil_base_pop, f_dict, f_matrix, evo_step!; no_of_years = no_of_years, no_hhs_per_agent = no_hhs_per_agent,
house_budget_mode = house_budget_mode, house_choice_mode = house_choice_mode, grouped = grouped, group_col = group_col, cutoff_dict = cutoff_dict, bg_cat = bg_cat,
risk_averse = risk_averse, flood_mem = flood_mem, seed = seed)

#Update Year
phil_abm.tick += 1
for id in filter!(id -> phil_abm[id] isa CHANCE_C.BlockGroup, collect(Agents.schedule(phil_abm)))
    ag_step!(phil_abm[id],phil_abm)
end

ag_locate(phil_abm[0], phil_abm)
show(tmr)
reset_timer!(tmr)